import Foundation

public struct ShellResult: Sendable, Hashable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String
    public var succeeded: Bool { exitCode == 0 }

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum ShellError: Error, Sendable, Equatable {
    case executableNotFound(String)
    case timedOut
    case launchFailed(String)
}

public protocol ShellRunning: Sendable {
    func run(
        _ executable: String, arguments: [String], currentDirectory: URL?,
        input: Data?, timeout: Duration
    ) async throws -> ShellResult
}

public extension ShellRunning {
    func run(_ executable: String, _ arguments: [String]) async throws -> ShellResult {
        try await run(executable, arguments: arguments, currentDirectory: nil, input: nil, timeout: .seconds(120))
    }
}

/// Directories searched (after `PATH`) when resolving a bare executable name.
private func extraSearchDirectories() -> [String] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        home + "/.cargo/bin", home + "/.local/bin", home + "/go/bin",
    ]
}

private func searchDirectories() -> [String] {
    var dirs: [String] = []
    let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    for d in envPath.split(separator: ":").map(String.init) + extraSearchDirectories()
    where !d.isEmpty && !dirs.contains(d) {
        dirs.append(d)
    }
    return dirs
}

/// Resolves an executable name (or absolute path) to an executable file path.
public func resolveExecutable(_ name: String) -> String? {
    let fm = FileManager.default
    if name.contains("/") {
        return fm.isExecutableFile(atPath: name) ? name : nil
    }
    for dir in searchDirectories() {
        let candidate = dir + "/" + name
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: candidate, isDirectory: &isDir), !isDir.boolValue,
           fm.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

private final class ProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    /// Registers the running process; returns false if cancellation already happened.
    func attach(_ p: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        process = p
        return !cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        guard let p, p.isRunning else { return }
        p.terminate()
        let pid = p.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if p.isRunning { kill(pid, SIGKILL) }
        }
    }
}

public struct ProcessShellRunner: ShellRunning {
    public init() {}

    public func run(
        _ executable: String, arguments: [String], currentDirectory: URL?,
        input: Data?, timeout: Duration
    ) async throws -> ShellResult {
        guard let path = resolveExecutable(executable) else {
            throw ShellError.executableNotFound(executable)
        }
        let seconds = Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1e18
        let dirs = searchDirectories().joined(separator: ":")

        let handle = ProcessHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.currentDirectoryURL = currentDirectory
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = dirs
                process.environment = env

                let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                process.standardInput = input != nil ? inPipe : FileHandle.nullDevice

                let done = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in done.signal() }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ShellError.launchFailed(error.localizedDescription))
                    return
                }
                if !handle.attach(process) { handle.cancel() }
                // Writing to a child that already exited must not raise SIGPIPE in the host.
                _ = fcntl(inPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

                let outBox = DataBox(), errBox = DataBox()
                let group = DispatchGroup()
                let readQueue = DispatchQueue.global(qos: .userInitiated)
                group.enter()
                readQueue.async {
                    outBox.set((try? outPipe.fileHandleForReading.readToEnd()) ?? Data())
                    group.leave()
                }
                group.enter()
                readQueue.async {
                    errBox.set((try? errPipe.fileHandleForReading.readToEnd()) ?? Data())
                    group.leave()
                }
                if let input {
                    readQueue.async {
                        try? inPipe.fileHandleForWriting.write(contentsOf: input)
                        try? inPipe.fileHandleForWriting.close()
                    }
                }

                let timedOut = done.wait(timeout: .now() + seconds) == .timedOut
                if timedOut {
                    process.terminate()
                    if done.wait(timeout: .now() + 2) == .timedOut {
                        kill(process.processIdentifier, SIGKILL)
                        _ = done.wait(timeout: .now() + 2)
                    }
                }
                _ = group.wait(timeout: .now() + 5)

                if handle.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if timedOut {
                    continuation.resume(throwing: ShellError.timedOut)
                    return
                }
                continuation.resume(returning: ShellResult(
                    exitCode: process.terminationStatus,
                    stdout: String(decoding: outBox.get(), as: UTF8.self),
                    stderr: String(decoding: errBox.get(), as: UTF8.self)
                ))
            }
        }
        } onCancel: {
            handle.cancel()
        }
    }
}

import Testing
import Foundation
@testable import CleanerKit

@Suite struct ShellTests {
    let shell = ProcessShellRunner()

    @Test func echoRoundTrip() async throws {
        let r = try await shell.run("echo", ["hello"])
        #expect(r.succeeded)
        #expect(r.stdout == "hello\n")
    }

    @Test func nonZeroExitCaptured() async throws {
        let r = try await shell.run("sh", ["-c", "echo oops >&2; exit 3"])
        #expect(r.exitCode == 3)
        #expect(!r.succeeded)
        #expect(r.stderr == "oops\n")
    }

    @Test func stdinPassedThrough() async throws {
        let r = try await shell.run("cat", arguments: [], currentDirectory: nil,
                                    input: Data("piped".utf8), timeout: .seconds(10))
        #expect(r.stdout == "piped")
    }

    @Test func timeoutThrows() async throws {
        await #expect(throws: ShellError.timedOut) {
            _ = try await shell.run("sleep", arguments: ["5"], currentDirectory: nil,
                                    input: nil, timeout: .milliseconds(500))
        }
    }

    @Test func largeOutputDoesNotDeadlock() async throws {
        let r = try await shell.run("sh", ["-c", "head -c 3000000 /dev/zero | tr '\\0' 'a'; head -c 2000000 /dev/zero | tr '\\0' 'b' >&2"])
        #expect(r.succeeded)
        #expect(r.stdout.utf8.count == 3_000_000)
        #expect(r.stderr.utf8.count == 2_000_000)
    }

    @Test func missingExecutable() async throws {
        await #expect(throws: ShellError.executableNotFound("definitely-not-a-binary-xyz")) {
            _ = try await shell.run("definitely-not-a-binary-xyz", [])
        }
    }

    @Test func resolveFindsStandardTools() {
        #expect(resolveExecutable("ls") != nil)
        #expect(resolveExecutable("definitely-not-a-binary-xyz") == nil)
    }
}

import Darwin
import Foundation

public enum ActiveProjectDetector {
    static let processNames: Set<String> = [
        "Xcode", "Code", "Cursor", "Windsurf", "studio", "idea", "zsh", "bash", "fish",
        "node", "java", "gradle", "dart", "flutter",
    ]

    /// Current working directories of well-known dev processes. Best effort: unreadable processes are ignored.
    public static func currentWorkingDirectories() async -> [URL] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let bytes = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return [] }
        let n = Int(bytes) / MemoryLayout<pid_t>.size

        var seen = Set<String>()
        var result: [URL] = []
        for pid in pids.prefix(n) where pid > 0 {
            var nameBuf = [CChar](repeating: 0, count: 256)
            let nameLen = Int(proc_name(pid, &nameBuf, UInt32(nameBuf.count)))
            guard nameLen > 0,
                  processNames.contains(String(decoding: nameBuf.prefix(nameLen).map { UInt8(bitPattern: $0) }, as: UTF8.self))
            else { continue }
            var info = proc_vnodepathinfo()
            let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { continue }
            let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if !path.isEmpty, seen.insert(path).inserted {
                result.append(URL(fileURLWithPath: path, isDirectory: true))
            }
        }
        return result
    }
}

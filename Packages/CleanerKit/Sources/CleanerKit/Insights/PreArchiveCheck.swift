import Foundation

public struct ArchiveRisk: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable { case dirty, unpushed(Int), stashes(Int) }
    public var projectURL: URL
    public var kind: Kind
    public var id: String { "\(projectURL.path)|\(kind)" }

    public var message: String {
        switch kind {
        case .dirty: "\(projectURL.lastPathComponent) has uncommitted changes"
        case .unpushed(let n): "\(projectURL.lastPathComponent) has \(n) unpushed commit(s)"
        case .stashes(let n): "\(projectURL.lastPathComponent) has \(n) stash(es)"
        }
    }
}

public enum PreArchiveCheck {
    public static func risks(projects: [Project]) -> [ArchiveRisk] {
        var out: [ArchiveRisk] = []
        for p in projects {
            guard let git = p.git else { continue }
            if git.isDirty { out.append(ArchiveRisk(projectURL: p.url, kind: .dirty)) }
            if let n = git.unpushedCommitCount, n > 0 { out.append(ArchiveRisk(projectURL: p.url, kind: .unpushed(n))) }
            if git.stashCount > 0 { out.append(ArchiveRisk(projectURL: p.url, kind: .stashes(git.stashCount))) }
        }
        return out
    }
}

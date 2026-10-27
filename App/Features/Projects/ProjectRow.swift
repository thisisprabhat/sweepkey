import SweepkeyKit
import Foundation

/// One row of the hierarchical projects table: a project, or one of its candidates.
struct ProjectRow: Identifiable, Hashable {
    let id: String
    let name: String
    let ecosystemNames: String
    let ecosystemIDs: [String]
    let lastActivity: Date?
    let bytes: Int64
    let risk: RiskLevel?
    let project: Project?
    let candidate: Candidate?
    var children: [ProjectRow]?

    var lastActivitySort: Date { lastActivity ?? .distantPast }
    var riskSort: RiskLevel { risk ?? .safe }

    init(project: Project) {
        id = project.id
        name = project.name
        ecosystemIDs = project.ecosystemIDs
        ecosystemNames = project.ecosystemIDs.map { Ecosystem.named($0).name }.joined(separator: ", ")
        lastActivity = project.lastActivity
        bytes = project.reclaimableBytes
        risk = project.candidates.map(\.risk).max()
        self.project = project
        candidate = nil
        children = project.candidates.map { ProjectRow(candidate: $0) }
    }

    init(candidate: Candidate) {
        id = candidate.id
        name = candidate.title
        ecosystemIDs = [candidate.ecosystemID]
        ecosystemNames = Ecosystem.named(candidate.ecosystemID).name
        lastActivity = candidate.lastModified
        bytes = candidate.sizeBytes
        risk = candidate.risk
        project = nil
        self.candidate = candidate
        children = nil
    }
}

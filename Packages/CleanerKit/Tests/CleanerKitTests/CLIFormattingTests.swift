import Foundation
import Testing
@testable import CleanerKit

@Suite struct CLIFormattingTests {
    @Test func parsesSizes() {
        #expect(CLIFormatting.parseSize("100MB") == Int64(100 * 1_048_576))
        #expect(CLIFormatting.parseSize("1.5 GB") == 1_610_612_736)
        #expect(CLIFormatting.parseSize("2g") == Int64(2 * 1_073_741_824))
        #expect(CLIFormatting.parseSize("512") == 512)
        #expect(CLIFormatting.parseSize("10 kb") == 10_240)
    }

    @Test func rejectsBadSizes() {
        #expect(CLIFormatting.parseSize("") == nil)
        #expect(CLIFormatting.parseSize("abc") == nil)
        #expect(CLIFormatting.parseSize("10XB") == nil)
        #expect(CLIFormatting.parseSize("-5MB") == nil)
        #expect(CLIFormatting.parseSize("1.2.3MB") == nil)
    }

    @Test func formatsBytes() {
        #expect(CLIFormatting.formatBytes(0) == "0 B")
        #expect(CLIFormatting.formatBytes(1023) == "1023 B")
        #expect(CLIFormatting.formatBytes(1536) == "1.5 KB")
        #expect(CLIFormatting.formatBytes(5 * 1_073_741_824) == "5.0 GB")
    }

    @Test func formatsAge() {
        let now = Date()
        #expect(CLIFormatting.formatAge(nil) == "-")
        #expect(CLIFormatting.formatAge(now.addingTimeInterval(-3 * 86_400), now: now) == "3d ago")
        #expect(CLIFormatting.formatAge(now.addingTimeInterval(-60), now: now) == "today")
    }

    @Test func alignsTable() {
        let out = CLIFormatting.table(
            headers: ["Name", "Size"], rows: [["a", "1 KB"], ["longer", "10 MB"]], rightAligned: [1])
        let lines = out.split(separator: "\n").map(String.init)
        #expect(lines.count == 4)
        #expect(lines[0] == "Name     Size")
        #expect(lines[2] == "a        1 KB")
        #expect(lines[3] == "longer  10 MB")
    }

    /// One version source: CleanerVersion.current matches project.yml's MARKETING_VERSION, and
    /// the line has the exact shape scripts/release.sh stamps.
    @Test func versionHasOneSource() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let yml = try String(contentsOf: repo.appendingPathComponent("project.yml"), encoding: .utf8)
        let line = try #require(yml.split(separator: "\n").first { $0.contains("MARKETING_VERSION:") })
        let marketing = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
        #expect(marketing == CleanerVersion.current)
        let source = try String(
            contentsOf: repo.appendingPathComponent("Packages/CleanerKit/Sources/CleanerKit/CLISupport/Version.swift"),
            encoding: .utf8)
        #expect(source.contains("public static let current = \"\(CleanerVersion.current)\""))
    }
}

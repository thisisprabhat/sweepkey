import Foundation
import Testing
@testable import CleanerKit

@Suite struct RuleResourcesTests {
    @Test func findsBundleBesideRealExecutableThroughSymlink() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rr-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let install = root.appendingPathComponent("install")
        let links = root.appendingPathComponent("links")
        let bundle = install.appendingPathComponent(RuleResources.bundleName)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        try fm.createDirectory(at: links, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: bundle.appendingPathComponent("rules.json"))
        let exe = install.appendingPathComponent("cleaner")
        fm.createFile(atPath: exe.path, contents: Data())
        let link = links.appendingPathComponent("cleaner")
        try fm.createSymbolicLink(at: link, withDestinationURL: exe)

        let url = RuleResources.rulesURL(executablePath: link.path, mainResourceURL: nil)
        #expect(url?.lastPathComponent == "rules.json")
    }

    @Test func returnsNilWhenMissing() {
        #expect(RuleResources.rulesURL(executablePath: "/nonexistent/dir/cleaner", mainResourceURL: nil) == nil)
    }

    @Test func bundledLoadsInDebugAndNeverTrapsWhenShippedLookupFails() throws {
        // RuleResources finds nothing in the test runner; the DEBUG-only Bundle.module fallback
        // supplies rules. In release builds the same path throws LoadError.resourceMissing.
        #if DEBUG
        #expect(try !RuleSet.bundled().isEmpty)
        #else
        #expect(throws: RuleSet.LoadError.self) { try RuleSet.bundled() }
        #endif
    }
}

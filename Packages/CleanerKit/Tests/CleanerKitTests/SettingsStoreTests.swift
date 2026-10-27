import Testing
import Foundation
@testable import CleanerKit

@Suite struct SettingsStoreTests {
    @Test func roundTrip() async throws {
        try await withTempDir { dir in
            let store = SettingsStore(fileURL: dir.appending(path: "nested/settings.json"))
            var s = CleanerSettings()
            s.scanRoots = [dir.appending(path: "Projects")]
            s.staleAfterDays = 45
            s.defaultDeleteMode = .trash
            s.ruleOverrides = ["javascript.node_modules": false]
            s.vault.keepVersions = 9
            s.vault.defaultFormat = .zip
            s.schedule.autoScanEnabled = true
            try store.save(s)
            #expect(store.load() == s)
        }
    }

    @Test func missingFileGivesDefaults() async throws {
        try await withTempDir { dir in
            #expect(SettingsStore(fileURL: dir.appending(path: "none.json")).load() == CleanerSettings())
        }
    }

    @Test func corruptFileGivesDefaults() async throws {
        try await withTempDir { dir in
            let f = dir.appending(path: "s.json")
            try "not json".write(to: f, atomically: true, encoding: .utf8)
            #expect(SettingsStore(fileURL: f).load() == CleanerSettings())
        }
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        let s = try JSONDecoder().decode(CleanerSettings.self, from: Data("{}".utf8))
        #expect(s == CleanerSettings())
        #expect(s.staleAfterDays == 30)
        #expect(s.defaultDeleteMode == .permanent)
        #expect(s.vault.alwaysCollect == ["pubspec.yaml"])
        #expect(s.vault.keepVersions == 5)
        #expect(s.lowSpaceThresholdGB == 20)
        #expect(s.showMenuBarExtra)
    }

    @Test func unknownKeysAndPartialNestedWork() throws {
        let json = #"{"staleAfterDays": 10, "futureKey": [1,2], "vault": {"keepVersions": 2, "zzz": true}}"#
        let s = try JSONDecoder().decode(CleanerSettings.self, from: Data(json.utf8))
        #expect(s.staleAfterDays == 10)
        #expect(s.vault.keepVersions == 2)
        #expect(s.vault.alwaysCollect == ["pubspec.yaml"])
    }

    @Test func savedJSONIsSortedAndPretty() async throws {
        try await withTempDir { dir in
            let f = dir.appending(path: "s.json")
            try SettingsStore(fileURL: f).save(CleanerSettings())
            let text = try String(contentsOf: f, encoding: .utf8)
            #expect(text.contains("\n"))
            let a = try #require(text.range(of: "\"defaultDeleteMode\""))
            let b = try #require(text.range(of: "\"staleAfterDays\""))
            #expect(a.lowerBound < b.lowerBound)
        }
    }
}

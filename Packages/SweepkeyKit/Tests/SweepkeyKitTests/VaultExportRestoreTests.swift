import Foundation
import Testing
@testable import SweepkeyKit

private func iso(_ n: Int) -> @Sendable () -> Date {
    let box = ClockBox()
    return { box.next(n) }
}
private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock(); private var i = 0
    func next(_ step: Int) -> Date { lock.lock(); defer { lock.unlock() }; i += 1; return Date(timeIntervalSince1970: 1_700_000_000 + Double(i * step)) }
}

private func perms(_ url: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
}

private func fixture(_ dir: URL) throws -> (root: URL, files: [SecretFile], jks: URL) {
    let root = dir.appendingPathComponent("Root", isDirectory: true)
    let jks = root.appendingPathComponent("app/android/app/upload.jks")
    try writeText("KEYSTORE-1", to: jks)
    try writeText("A=1", to: root.appendingPathComponent("app/.env"))
    return (root, [try makeFile(jks, root: root), try makeFile(root.appendingPathComponent("app/.env"), root: root)], jks)
}

/// Never the real Trash: files a restore replaces are moved into `<dir>/TestTrash`.
private func testRestorer(_ dir: URL) -> VaultRestorer {
    let bin = dir.appendingPathComponent("TestTrash", isDirectory: true)
    return VaultRestorer(trash: { url in
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))
    })
}

@Suite struct VaultExportRestoreTests {
    @Test
    func folderExportMirrorsModeAndManifest() async throws {
        try await withTempDir { dir in
            let (_, files, jks) = try fixture(dir)
            let dest = dir.appendingPathComponent("vault")
            let res = try await VaultExporter().export(.init(files: files, destination: dest, format: .folder))
            let copy = dest.appendingPathComponent("Root/app/android/app/upload.jks")
            #expect(try Data(contentsOf: copy) == Data(contentsOf: jks))
            #expect(try perms(copy) == 0o600)
            #expect(try perms(copy.deletingLastPathComponent()) == 0o700)
            #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent(".metadata_never_index").path))
            let m = try JSONDecoder.vault.decode(VaultManifest.self, from: Data(contentsOf: dest.appendingPathComponent("manifest.json")))
            let e = try #require(m.entries.first { $0.vaultPath == "Root/app/android/app/upload.jks" })
            #expect(e.sha256 == (try VaultHashing.sha256(of: jks)))
            #expect(e.sourcePath == jks.path)
            #expect(res.copiedCount == 2 && res.unchangedCount == 0)
            let again = try await VaultExporter().export(.init(files: files, destination: dest, format: .folder))
            #expect(again.copiedCount == 0 && again.unchangedCount == 2)
        }
    }

    @Test
    func changedFileIsVersionedAndPruned() async throws {
        try await withTempDir { dir in
            let (_, files, jks) = try fixture(dir)
            let dest = dir.appendingPathComponent("vault")
            let exporter = VaultExporter(now: iso(10))
            _ = try await exporter.export(.init(files: files, destination: dest, format: .folder, keepVersions: 2))
            let versions = dest.appendingPathComponent(".versions/Root/app/android/app/upload.jks")
            for i in 2...5 {
                try writeText("KEYSTORE-\(i)", to: jks)
                let f = [try makeFile(jks, root: files[0].scanRoot)]
                let r = try await exporter.export(.init(files: f, destination: dest, format: .folder, keepVersions: 2))
                #expect(r.copiedCount == 1)
            }
            let names = try FileManager.default.contentsOfDirectory(atPath: versions.path).sorted()
            #expect(names.count == 2)
            let newest = try String(contentsOf: versions.appendingPathComponent(names[1]), encoding: .utf8)
            #expect(newest == "KEYSTORE-4")
            // manifest merged: .env entry retained
            let m = try JSONDecoder.vault.decode(VaultManifest.self, from: Data(contentsOf: dest.appendingPathComponent("manifest.json")))
            #expect(m.entries.count == 2)
        }
    }

    @Test
    func zipExportListable() async throws {
        try await withTempDir { dir in
            let (_, files, _) = try fixture(dir)
            let zip = dir.appendingPathComponent("out/v.zip")
            _ = try await VaultExporter().export(.init(files: files, destination: zip, format: .zip))
            let r = try await ProcessShellRunner().run("/usr/bin/zipinfo", ["-1", zip.path])
            #expect(r.stdout.contains("Root/app/android/app/upload.jks"))
            #expect(r.stdout.contains("manifest.json"))
            let restorer = testRestorer(dir)
            let opened = try await restorer.open(zip, password: nil)
            #expect(opened.manifest.entries.count == 2)
            await restorer.close(opened)
            #expect(!FileManager.default.fileExists(atPath: opened.root.path))
        }
    }

    @Test
    func zipAndImageOutputsAreOwnerOnly() async throws {
        try await withTempDir { dir in
            let (_, files, _) = try fixture(dir)
            let zip = dir.appendingPathComponent("out/v.zip")
            _ = try await VaultExporter().export(.init(files: files, destination: zip, format: .zip))
            #expect(try perms(zip) == 0o600)
        }
    }

    @Test
    func overwriteFailsSafelyWhenTrashFails() async throws {
        struct NoTrash: Error {}
        try await withTempDir { dir in
            let (_, files, jks) = try fixture(dir)
            let vault = dir.appendingPathComponent("vault")
            _ = try await VaultExporter().export(.init(files: files, destination: vault, format: .folder))
            let restorer = VaultRestorer(trash: { _ in throw NoTrash() })
            let opened = try await restorer.open(vault, password: nil)
            try writeText("CHANGED", to: jks)
            let plan = try await restorer.planRestore(opened, strategy: .originalPaths)
            let res = try await restorer.restore(plan.filter { $0.destinationURL == jks }, overwrite: true)
            #expect(res.failed.count == 1 && res.restored.isEmpty)
            #expect(try String(contentsOf: jks, encoding: .utf8) == "CHANGED")
            let leftovers = try FileManager.default.contentsOfDirectory(atPath: jks.deletingLastPathComponent().path)
            #expect(leftovers == ["upload.jks"])
        }
    }

    @Test
    func planSkipsEntriesWhoseSourceDoesNotMatchVaultPath() async throws {
        try await withTempDir { dir in
            let (_, files, _) = try fixture(dir)
            let vault = dir.appendingPathComponent("vault")
            _ = try await VaultExporter().export(.init(files: files, destination: vault, format: .folder))
            // Tamper with the manifest: aim the .env entry at an unrelated file.
            let manifestURL = vault.appendingPathComponent("manifest.json")
            var manifest = try JSONDecoder.vault.decode(VaultManifest.self, from: Data(contentsOf: manifestURL))
            let i = try #require(manifest.entries.firstIndex { $0.vaultPath == "Root/app/.env" })
            manifest.entries[i].sourcePath = dir.appendingPathComponent("Library/LaunchAgents/evil.plist").path
            try VaultCoding.encoder().encode(manifest).write(to: manifestURL)
            let restorer = testRestorer(dir)
            let opened = try await restorer.open(vault, password: nil)
            let (actions, warnings) = try await restorer.planRestoreWithWarnings(opened, strategy: .originalPaths)
            #expect(actions.map(\.entry.vaultPath) == ["Root/app/android/app/upload.jks"])
            #expect(warnings.count == 1 && warnings[0].contains("Root/app/.env"))
        }
    }

    @Test
    func sourceMatchRules() {
        func entry(_ vaultPath: String, _ source: String) -> VaultManifestEntry {
            VaultManifestEntry(vaultPath: vaultPath, sourcePath: source, sha256: "", sizeBytes: 0,
                               collectedAt: Date(), reason: .patternMatch)
        }
        #expect(VaultRestorer.sourceMatchesVaultPath(entry("Projects/app/.env", "/Users/me/Projects/app/.env")))
        #expect(VaultRestorer.sourceMatchesVaultPath(entry("Projects-1a2b3c4d/app/.env", "/Volumes/W/Projects/app/.env")))
        #expect(!VaultRestorer.sourceMatchesVaultPath(entry("Projects/app/.env", "/Users/me/other/.env")))
        #expect(!VaultRestorer.sourceMatchesVaultPath(entry("Projects/app/.env", "relative/app/.env")))
        #expect(!VaultRestorer.sourceMatchesVaultPath(entry("Projects/app/.env", "/x/../app/.env")))
        #expect(!VaultRestorer.sourceMatchesVaultPath(entry("Projects", "/Users/me/Projects")))
        #expect(!VaultRestorer.sourceMatchesVaultPath(entry("../app/.env", "/app/.env")))
    }

    @Test
    func encryptedImageRequiresPassword() async throws {
        try await withTempDir { dir in
            let (_, files, _) = try fixture(dir)
            await #expect(throws: VaultError.passwordRequired) {
                try await VaultExporter().export(.init(files: files, destination: dir.appendingPathComponent("v.dmg"), format: .encryptedImage))
            }
        }
    }

    @Test(.enabled(if: hdiutilAvailable))
    func encryptedImageRoundTrip() async throws {
        try await withTempDir { dir in
            let (_, files, jks) = try fixture(dir)
            let original = try Data(contentsOf: jks)
            let dmg = dir.appendingPathComponent("v.dmg")
            _ = try await VaultExporter().export(.init(files: files, destination: dmg, format: .encryptedImage, password: "pw-123"))
            let restorer = testRestorer(dir)
            await #expect(throws: VaultError.wrongPassword) { try await restorer.open(dmg, password: "nope") }
            await #expect(throws: VaultError.passwordRequired) { try await restorer.open(dmg, password: nil) }

            let opened = try await restorer.open(dmg, password: "pw-123")
            do {
                let actions = try await restorer.planRestore(opened, strategy: .originalPaths)
                try FileManager.default.removeItem(at: jks)
                let planned = try await restorer.planRestore(opened, strategy: .originalPaths)
                #expect(actions.count == 2)
                let res = try await restorer.restore(planned, overwrite: false)
                #expect(res.restored.contains("Root/app/android/app/upload.jks"))
                #expect(res.skipped.contains("Root/app/.env"))
                #expect(try Data(contentsOf: jks) == original)
                #expect(try perms(jks) == 0o600)
            } catch {
                await restorer.close(opened)
                throw error
            }
            await restorer.close(opened)
            #expect(!FileManager.default.fileExists(atPath: opened.root.path))
        }
    }

    @Test
    func conflictOverwriteAndSymlink() async throws {
        try await withTempDir { dir in
            let (_, files, jks) = try fixture(dir)
            let vault = dir.appendingPathComponent("vault")
            _ = try await VaultExporter().export(.init(files: files, destination: vault, format: .folder))
            let restorer = testRestorer(dir)
            let opened = try await restorer.open(vault, password: nil)
            try writeText("CHANGED", to: jks)
            let envURL = jks.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".env")

            var plan = try await restorer.planRestore(opened, strategy: .originalPaths)
            let jksAction = try #require(plan.first { $0.destinationURL == jks })
            #expect(jksAction.destinationExists && !jksAction.identical)
            #expect(try #require(plan.first { $0.destinationURL == envURL }).identical)

            var res = try await restorer.restore(plan, overwrite: false)
            #expect(res.skipped.count == 2 && res.restored.isEmpty)
            #expect(try String(contentsOf: jks, encoding: .utf8) == "CHANGED")

            res = try await restorer.restore(plan, overwrite: true)
            #expect(res.restored == ["Root/app/android/app/upload.jks"])
            #expect(try String(contentsOf: jks, encoding: .utf8) == "KEYSTORE-1")
            // The overwritten file went to the (test) Trash, not into the void.
            let binned = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("TestTrash").path)
            #expect(binned.count == 1)
            #expect(try String(contentsOf: dir.appendingPathComponent("TestTrash/\(binned[0])"), encoding: .utf8) == "CHANGED")

            // symlink destination fails, target untouched
            let target = dir.appendingPathComponent("target.txt")
            try writeText("T", to: target)
            try FileManager.default.removeItem(at: envURL)
            try FileManager.default.createSymbolicLink(at: envURL, withDestinationURL: target)
            plan = try await restorer.planRestore(opened, strategy: .originalPaths)
            res = try await restorer.restore(plan, overwrite: true)
            #expect(res.failed["Root/app/.env"] != nil)
            #expect(try String(contentsOf: target, encoding: .utf8) == "T")

            // missing parent dirs are created
            try FileManager.default.removeItem(at: jks.deletingLastPathComponent().deletingLastPathComponent())
            plan = try await restorer.planRestore(opened, strategy: .originalPaths)
            res = try await restorer.restore(plan, overwrite: false)
            #expect(res.restored.contains("Root/app/android/app/upload.jks"))
        }
    }

    @Test
    func zipRefusesDirectoryDestinationAndReplacesFile() async throws {
        try await withTempDir { dir in
            let (_, files, _) = try fixture(dir)
            let keep = dir.appendingPathComponent("existing.zip", isDirectory: true)
            try writeText("precious", to: keep.appendingPathComponent("a.txt"))
            await #expect(throws: VaultError.self) {
                try await VaultExporter().export(.init(files: files, destination: keep, format: .zip))
            }
            #expect(FileManager.default.fileExists(atPath: keep.appendingPathComponent("a.txt").path))
            let zip = dir.appendingPathComponent("v.zip")
            try writeText("old", to: zip)
            _ = try await VaultExporter().export(.init(files: files, destination: zip, format: .zip))
            _ = try await VaultExporter().export(.init(files: files, destination: zip, format: .zip))
            let r = try await ProcessShellRunner().run("/usr/bin/zipinfo", ["-1", zip.path])
            #expect(r.stdout.contains("manifest.json"))
            let left = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix(".tmp-") }
            #expect(left.isEmpty)
        }
    }

    @Test
    func restoreRejectsSymlinkParentAndNonRegularDestination() async throws {
        try await withTempDir { dir in
            let (_, files, jks) = try fixture(dir)
            let vault = dir.appendingPathComponent("vault")
            _ = try await VaultExporter().export(.init(files: files, destination: vault, format: .folder))
            let restorer = testRestorer(dir)
            let opened = try await restorer.open(vault, password: nil)
            let real = dir.appendingPathComponent("elsewhere", isDirectory: true)
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
            let androidDir = jks.deletingLastPathComponent().deletingLastPathComponent()
            try FileManager.default.removeItem(at: androidDir)
            try FileManager.default.createSymbolicLink(at: androidDir, withDestinationURL: real)
            // .env destination is a directory
            let envURL = androidDir.deletingLastPathComponent().appendingPathComponent(".env")
            try FileManager.default.removeItem(at: envURL)
            try FileManager.default.createDirectory(at: envURL, withIntermediateDirectories: true)
            let plan = try await restorer.planRestore(opened, strategy: .originalPaths)
            let res = try await restorer.restore(plan, overwrite: true)
            #expect(res.failed.count == 2)
            #expect(res.restored.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: real.path).isEmpty)
        }
    }

    @Test
    func normalizesRemotes() {
        #expect(VaultRestorer.normalizeRemote("git@GitHub.com:acme/app.git") == "https://github.com/acme/app")
        #expect(VaultRestorer.normalizeRemote("https://GitHub.com/acme/app.git") == "https://github.com/acme/app")
        #expect(VaultRestorer.normalizeRemote("ssh://git@github.com/acme/app") == "https://github.com/acme/app")
        #expect(VaultRestorer.normalizeRemote("ssh://git@github.com:22/acme/app.git") == "https://github.com/acme/app")
        #expect(VaultRestorer.normalizeRemote("GitHub.com:acme/app.git") == "https://github.com/acme/app")
        #expect(VaultRestorer.normalizeRemote("ssh://git@host:2222/a/b") == "https://host:2222/a/b")
    }

    @Test(.enabled(if: vaultGitAvailable), arguments: [false, true])
    func restoreByGitRemoteIntoFreshClone(fileRemote: Bool) async throws {
        try await withTempDir { dir in
            let (root, app) = try makeFixtureRepo(in: dir)
            let origin = fileRemote ? "file://" + app.path : "https://github.com/acme/app.git"
            try vaultGit(["remote", "add", "origin", origin], in: app)
            let found = try await SecretFinder().findSecrets(VaultCollectOptions(roots: [root]))
            let vault = dir.appendingPathComponent("vault")
            _ = try await VaultExporter().export(.init(files: found, destination: vault, format: .folder))

            let clones = dir.appendingPathComponent("clones", isDirectory: true)
            try FileManager.default.createDirectory(at: clones, withIntermediateDirectories: true)
            try vaultGit(["clone", "-q", app.path, "fresh"], in: clones)
            let fresh = clones.appendingPathComponent("fresh")
            if fileRemote {
                try vaultGit(["remote", "set-url", "origin", origin], in: fresh)
            } else {
                try vaultGit(["remote", "set-url", "origin", "git@github.com:acme/app.git"], in: fresh)
            }
            #expect(!FileManager.default.fileExists(atPath: fresh.appendingPathComponent(".env").path))

            let restorer = testRestorer(dir)
            let opened = try await restorer.open(vault, password: nil)
            let plan = try await restorer.planRestore(opened, strategy: .matchGitRemote(searchRoots: [clones]))
            #expect(plan.count == 3)
            let res = try await restorer.restore(plan, overwrite: false)
            #expect(res.failed.isEmpty)
            #expect(try String(contentsOf: fresh.appendingPathComponent(".env"), encoding: .utf8) == "SECRET=1\n")
            #expect(FileManager.default.fileExists(atPath: fresh.appendingPathComponent("android/app/upload.jks").path))
            #expect(res.skipped.contains { $0.hasSuffix("pubspec.yaml") })
        }
    }
}

extension JSONDecoder {
    static var vault: JSONDecoder { VaultCoding.decoder() }
}

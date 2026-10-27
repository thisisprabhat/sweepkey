import Foundation
import Testing
@testable import CleanerKit

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
            let restorer = VaultRestorer()
            let opened = try await restorer.open(zip, password: nil)
            #expect(opened.manifest.entries.count == 2)
            await restorer.close(opened)
            #expect(!FileManager.default.fileExists(atPath: opened.root.path))
        }
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
            let restorer = VaultRestorer()
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
            let restorer = VaultRestorer()
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
    func normalizesRemotes() {
        #expect(VaultRestorer.normalizeRemote("git@GitHub.com:acme/app.git") == "https://github.com/acme/app")
        #expect(VaultRestorer.normalizeRemote("https://GitHub.com/acme/app.git") == "https://github.com/acme/app")
        #expect(VaultRestorer.normalizeRemote("ssh://git@github.com/acme/app") == "https://github.com/acme/app")
    }

    @Test(.enabled(if: gitAvailable))
    func restoreByGitRemoteIntoFreshClone() async throws {
        try await withTempDir { dir in
            let (root, app) = try makeFixtureRepo(in: dir)
            try runGit(["remote", "add", "origin", "https://github.com/acme/app.git"], in: app)
            let found = try await SecretFinder().findSecrets(VaultCollectOptions(roots: [root]))
            let vault = dir.appendingPathComponent("vault")
            _ = try await VaultExporter().export(.init(files: found, destination: vault, format: .folder))

            let clones = dir.appendingPathComponent("clones", isDirectory: true)
            try FileManager.default.createDirectory(at: clones, withIntermediateDirectories: true)
            try runGit(["clone", "-q", app.path, "fresh"], in: clones)
            let fresh = clones.appendingPathComponent("fresh")
            try runGit(["remote", "set-url", "origin", "git@github.com:acme/app.git"], in: fresh)
            #expect(!FileManager.default.fileExists(atPath: fresh.appendingPathComponent(".env").path))

            let restorer = VaultRestorer()
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

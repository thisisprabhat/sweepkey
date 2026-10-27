import CryptoKit
import Foundation

public enum VaultError: Error, Sendable, Equatable {
    case passwordRequired
    case manifestMissing
    case commandFailed(String)
    case wrongPassword
}

enum VaultHashing {
    /// Streamed sha256 (hex) of the file at `url`.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum VaultCoding {
    static let manifestName = "manifest.json"

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Directory names never descended into when looking for secrets.
enum VaultArtifactDirs {
    static let names: Set<String> = [
        "node_modules", "build", ".venv", "venv", "target", "Pods", ".dart_tool", ".gradle",
        "DerivedData", ".build", "dist", ".next", ".git",
    ]

    static func containsArtifact(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { names.contains(String($0)) }
    }
}

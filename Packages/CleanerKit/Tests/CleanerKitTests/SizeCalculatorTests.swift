import Testing
import Foundation
@testable import CleanerKit

@Suite struct SizeCalculatorTests {
    let calc = SizeCalculator()

    @Test func nestedFilesSum() async throws {
        try await withTempDir { dir in
            try write(100_000, to: dir.appending(path: "a.bin"))
            try write(200_000, to: dir.appending(path: "sub/deep/b.bin"))
            let size = calc.allocatedSize(of: dir)
            #expect(size >= 300_000)
            #expect(size < 300_000 + 200_000)
        }
    }

    @Test func hardLinkCountedOnce() async throws {
        try await withTempDir { dir in
            let a = dir.appending(path: "a.bin")
            try write(1_000_000, to: a)
            try FileManager.default.linkItem(at: a, to: dir.appending(path: "b.bin"))
            let size = calc.allocatedSize(of: dir)
            #expect(size >= 1_000_000)
            #expect(size < 1_900_000)
        }
    }

    @Test func symlinkDoesNotAddTarget() async throws {
        try await withTempDir { dir in
            let outside = dir.appending(path: "outside/big.bin")
            try write(5_000_000, to: outside)
            let tree = dir.appending(path: "tree")
            try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: tree.appending(path: "link"), withDestinationURL: outside)
            try FileManager.default.createSymbolicLink(
                at: tree.appending(path: "dirlink"), withDestinationURL: dir.appending(path: "outside"))
            #expect(calc.allocatedSize(of: tree) < 1_000_000)
        }
    }

    @Test func missingPathIsZero() {
        #expect(calc.allocatedSize(of: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")) == 0)
    }

    @Test func concurrentSizes() async throws {
        try await withTempDir { dir in
            let a = dir.appending(path: "a"), b = dir.appending(path: "b")
            try write(100_000, to: a.appending(path: "f"))
            try write(300_000, to: b.appending(path: "f"))
            let sizes = await calc.allocatedSizes(of: [a, b], maxConcurrency: 2)
            #expect(sizes.count == 2)
            #expect(sizes[a]! >= 100_000)
            #expect(sizes[b]! >= 300_000)
        }
    }
}

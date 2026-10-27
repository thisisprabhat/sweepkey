import Testing
@testable import CleanerKit

@Suite struct GlobTests {
    @Test func eggInfo() {
        #expect(Glob.matches("*.egg-info", "mypkg.egg-info"))
        #expect(!Glob.matches("*.egg-info", "mypkg.egg"))
    }
    @Test func cmakeBuild() {
        #expect(Glob.matches("cmake-build-*", "cmake-build-debug"))
        #expect(!Glob.matches("cmake-build-*", "build"))
    }
    @Test func literal() {
        #expect(Glob.matches("node_modules", "node_modules"))
        #expect(!Glob.matches("node_modules", "node_modules2"))
    }
    @Test func questionMarkAndBrackets() {
        #expect(Glob.matches("v?", "v1"))
        #expect(!Glob.matches("v?", "v12"))
        #expect(Glob.matches("file[0-9].txt", "file7.txt"))
        #expect(!Glob.matches("file[0-9].txt", "fileA.txt"))
    }
}

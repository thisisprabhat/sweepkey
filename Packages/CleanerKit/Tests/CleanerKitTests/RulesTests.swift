import Foundation
import Testing
@testable import CleanerKit

@Suite struct RulesTests {
    @Test func bundledRulesDecodeValidateAndAreUnique() throws {
        let rules = try RuleSet.bundled()
        #expect(!rules.isEmpty)
        let set = RuleSet(rules: rules)
        for rule in rules {
            #expect(set.validate(rule).isEmpty, "\(rule.id): \(set.validate(rule))")
        }
        #expect(Set(rules.map(\.id)).count == rules.count)
        let known = Set(Ecosystem.builtIn.map(\.id))
        #expect(rules.allSatisfy { known.contains($0.ecosystemID) })
    }

    @Test func bundledRulesCoverSpecAndRiskFlags() throws {
        let rules = try RuleSet.bundled()
        let byID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        for id in ["javascript.dist", "python.env", "python.dist", "go.bin", "go.vendor"] {
            #expect(byID[id]?.enabledByDefault == false)
            #expect(byID[id]?.risk == .caution)
        }
        #expect(byID["unity.library"]?.risk == .caution)
        #expect(byID["unreal.derived_data_cache"]?.risk == .caution)
        #expect(byID["javascript.node_modules"]?.risk == .safe)
        #expect(byID["flutter.build"]?.markers == ["pubspec.yaml"])
        #expect(byID["rust.target"]?.markers == ["Cargo.toml"])
        #expect(byID["php.vendor"]?.markers == ["composer.json"])
        let targets = Set(rules.map(\.target))
        for t in ["node_modules", ".angular/cache", "*.egg-info", "ios/Pods", "android/app/build", ".flutter-plugins*",
                  "Carthage/Build", "cmake-build-*", "vendor/bundle", "bazel-*", ".terraform", "DerivedDataCache", "zig-out"] {
            #expect(targets.contains(t), "\(t)")
        }
    }

    @Test func effectiveRulesHonorOverridesAndAppendCustom() throws {
        let rules = try RuleSet.bundled()
        let set = RuleSet(rules: rules)
        let custom = Rule(id: "custom.x", ecosystemID: "generic", markers: ["x.txt"], target: "out-x",
                          risk: .safe, enabledByDefault: true)
        let eff = set.effectiveRules(overrides: ["javascript.node_modules": false, "javascript.dist": true], custom: [custom])
        #expect(!eff.contains { $0.id == "javascript.node_modules" })
        #expect(eff.contains { $0.id == "javascript.dist" })
        #expect(eff.last?.id == "custom.x")
        #expect(!eff.contains { $0.id == "go.vendor" })
    }

    @Test func validateFlagsProblems() {
        let set = RuleSet(rules: [])
        func rule(id: String = "a", markers: [String] = ["m"], target: String = "t") -> Rule {
            Rule(id: id, ecosystemID: "generic", markers: markers, target: target, risk: .safe, enabledByDefault: true)
        }
        #expect(set.validate(rule()).isEmpty)
        #expect(!set.validate(rule(id: "")).isEmpty)
        #expect(!set.validate(rule(target: "")).isEmpty)
        #expect(!set.validate(rule(target: "../x")).isEmpty)
        #expect(!set.validate(rule(target: "a/../b")).isEmpty)
        #expect(!set.validate(rule(target: "/usr")).isEmpty)
        #expect(!set.validate(rule(markers: [])).isEmpty)
    }

    @Test func matcherRequiresMarkerAndTarget() async throws {
        try await withTempDir { dir in
            try write(1, to: dir.appendingPathComponent("build/a.txt"))
            let r = Rule(id: "t.build", ecosystemID: "generic", markers: ["Makefile", "*.mk"], target: "build",
                         risk: .safe, enabledByDefault: true)
            #expect(RuleMatcher.matches(in: dir, childNames: ["build"], rules: [r]).isEmpty)
            try write(1, to: dir.appendingPathComponent("x.mk"))
            let m = RuleMatcher.matches(in: dir, childNames: ["build", "x.mk"], rules: [r])
            #expect(m.count == 1)
            #expect(m.first?.targets == [dir.appendingPathComponent("build")])
            #expect(RuleMatcher.matches(in: dir, childNames: ["x.mk"], rules: [r]).isEmpty)
        }
    }
}

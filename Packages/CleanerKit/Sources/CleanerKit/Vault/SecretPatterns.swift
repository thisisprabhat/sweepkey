import Foundation

public enum SecretPatterns {
    public static let defaults: [String] = [
        ".env", ".env.*", ".dev.vars", "*.jks", "*.keystore", "key.properties",
        "google-services.json", "GoogleService-Info.plist", "*.p12", "*.p8", "*.pem", "*.key",
        "*.cer", "*.mobileprovision", "id_rsa*", "id_ed25519*", "*.ppk", "credentials.json",
        "service-account*.json", "secrets.*", "terraform.tfvars", "*.tfstate", ".npmrc", ".pypirc",
        ".netrc", "sentry.properties", "master.key", "appsettings.*.json",
        "docker-compose.override.yml",
    ]

    /// Off by default; exposed for the UI.
    public static let optional: [String] = ["local.properties", ".firebaserc", ".env.example"]

    /// Excluded unless explicitly added as an extra pattern.
    public static let excludedByDefault: [String] = [".env.example", ".env.sample", ".env.template"]

    /// Returns the first pattern matching the file at `relativePath` (slash separated), or nil.
    /// Patterns without "/" match the last path component; patterns with "/" match the path suffix.
    public static func firstMatch(relativePath: String, extra: [String] = []) -> String? {
        let comps = relativePath.split(separator: "/").map(String.init)
        guard let name = comps.last else { return nil }
        let excluded = excludedByDefault.contains(name) && !extra.contains(where: { matches($0, comps) })
        if excluded { return nil }
        for p in defaults + extra where matches(p, comps) { return p }
        return nil
    }

    private static func matches(_ pattern: String, _ comps: [String]) -> Bool {
        if pattern.contains("/") {
            let n = pattern.split(separator: "/").count
            guard comps.count >= n else { return false }
            return Glob.matches(pattern, comps.suffix(n).joined(separator: "/"))
        }
        guard let name = comps.last else { return false }
        return Glob.matches(pattern, name)
    }
}

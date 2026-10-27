import Foundation

/// The one place the CLI's version lives. scripts/release.sh stamps the release version here
/// (and passes the same value to the app as MARKETING_VERSION); a test keeps it equal to
/// project.yml's MARKETING_VERSION for local builds.
public enum SweepkeyVersion {
    public static let current = "0.1.0"
}

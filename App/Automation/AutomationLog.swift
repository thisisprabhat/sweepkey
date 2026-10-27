import Foundation
import os

/// Automation diagnostics. Goes to the unified log (subsystem `com.prabhatkumar.Sweepkey`) and,
/// in DEBUG builds, also to stderr so a launch from a terminal shows what happened.
enum AutomationLog {
    private static let logger = Logger(subsystem: "com.prabhatkumar.Sweepkey", category: "automation")

    static func info(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        #if DEBUG
        FileHandle.standardError.write(Data("[Sweepkey.automation] \(message)\n".utf8))
        #endif
    }
}

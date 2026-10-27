import Foundation
import os

/// Automation diagnostics. Goes to the unified log (subsystem `com.prabhatkumar.Cleaner`) and,
/// in DEBUG builds, also to stderr so a launch from a terminal shows what happened.
enum AutomationLog {
    private static let logger = Logger(subsystem: "com.prabhatkumar.Cleaner", category: "automation")

    static func info(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        #if DEBUG
        FileHandle.standardError.write(Data("[Cleaner.automation] \(message)\n".utf8))
        #endif
    }
}

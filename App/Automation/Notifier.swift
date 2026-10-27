import AppKit
import Foundation
import UserNotifications

/// Local notifications. Authorization is requested lazily, the first time something is posted.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    static let lowSpaceCategory = "SWEEPKEY_LOW_SPACE"
    static let cleanSafeAction = "SWEEPKEY_CLEAN_SAFE"

    private var configured = false

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    /// Registers the delegate and the action category. Does not prompt for authorization.
    func configure() {
        guard !configured else { return }
        configured = true
        center.delegate = self
        let clean = UNNotificationAction(identifier: Self.cleanSafeAction, title: "Clean safe items", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: Self.lowSpaceCategory, actions: [clean], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    /// Posts a notification; returns false when the user has not allowed notifications.
    @discardableResult
    func post(title: String, body: String, category: String? = nil) async -> Bool {
        configure()
        guard await isAuthorized() else {
            AutomationLog.info("notification skipped (not authorized): \(title)")
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await center.add(request)
            AutomationLog.info("notification posted: \(title)")
            return true
        } catch {
            AutomationLog.info("notification failed: \(error.localizedDescription)")
            return false
        }
    }

    private func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined:
            AutomationLog.info("requesting notification authorization")
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        await MainActor.run {
            // Both the action button and a click on the notification open the pre-filled sheet.
            // Nothing is deleted without the in-app confirmation.
            if action == Notifier.cleanSafeAction || action == UNNotificationDefaultActionIdentifier {
                AppRouter.openCleanSafe()
            }
        }
    }
}

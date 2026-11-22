import AppKit
import UserNotifications

/// Local notifications: scan results, scheduled reminders, low disk space, cleaning done.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Opens the main window when a notification is clicked; set by the app at launch.
    var onOpen: (() -> Void)?
    private var didSetup = false

    func setup() {
        guard !didSetup else { return }
        didSetup = true
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks once, the first time Prune has something to tell (the user's first scan).
    func requestPermissionIfNeeded() {
        guard Prefs.notifications else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    func post(_ id: String, title: String, body: String) {
        guard Prefs.notifications else { return }
        let content = UNMutableNotificationContent()
        content.title = tr(title)
        content.body = tr(body)
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            NSApp.activate()
            self.onOpen?()
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

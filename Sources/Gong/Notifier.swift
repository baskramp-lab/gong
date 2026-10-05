import Foundation
import UserNotifications
import GongCore

/// Soft notifications. Only works when running from Gong.app (needs a bundle identifier).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestPermission(completion: (@Sendable (Bool) -> Void)? = nil) {
        guard available else { NSLog("Notifier: no bundle, notifications disabled (run from Gong.app)"); completion?(false); return }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error { NSLog("Notifier: authorization error \(error)") }
            else { NSLog("Notifier: granted=\(granted)") }
            completion?(granted)
        }
    }

    /// Whether macOS currently lets Gong post banners (the user can turn this off at any time).
    func isAllowed(_ completion: @escaping @Sendable (Bool) -> Void) {
        guard available else { completion(false); return }
        UNUserNotificationCenter.current().getNotificationSettings { s in
            completion([.authorized, .provisional].contains(s.authorizationStatus))
        }
    }

    /// Without this, macOS suppresses the banner whenever Gong is the frontmost app
    /// (which it typically is right after the modal or settings window activated it).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func send(meeting: Meeting, minutesBefore: Int) {
        guard available else { NSLog("Notifier (no bundle): \(meeting.title) in \(minutesBefore) min"); return }
        let content = UNMutableNotificationContent()
        content.title = meeting.title
        let actualMinutes = max(0, Int((meeting.start.timeIntervalSinceNow / 60).rounded()))
        content.body = L("At %1$@ — in %2$d min", Countdown.timeString(meeting.start), actualMinutes)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(meeting.id)-\(minutesBefore)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Notifier: add failed \(error)") }
        }
    }
}

import Foundation
import TobiasCore
import UserNotifications

enum Notifier {
    /// Notifies at most once a day, and only when the user turned it on and the app is a real bundle.
    static func notifyIfLow(disk: DiskSpace, reclaimable: Int64) {
        guard UserDefaults.standard.bool(forKey: "notifyLowSpace"),
              Bundle.main.bundleIdentifier != nil else { return }
        let lowSpace = disk.usedFraction > 0.85
        let lotToClean = reclaimable > 5 * 1_000_000_000
        guard lowSpace || lotToClean else { return }

        let last = UserDefaults.standard.object(forKey: "lastNotification") as? Date
        if let last, Date().timeIntervalSince(last) < 24 * 3600 { return }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Tobias"
            content.body = "\(ByteFormat.string(disk.availableRaw)) free. \(ByteFormat.string(reclaimable)) can be cleaned."
            center.add(UNNotificationRequest(identifier: "tobias.low-space", content: content, trigger: nil))
            UserDefaults.standard.set(Date(), forKey: "lastNotification")
        }
    }
}

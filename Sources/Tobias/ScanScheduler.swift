import Foundation

/// Periodic background scan. The system picks the exact moment within the tolerance window.
final class ScanScheduler: @unchecked Sendable {
    private var activity: NSBackgroundActivityScheduler?

    func start(every interval: TimeInterval, action: @escaping @Sendable () async -> Void) {
        activity?.invalidate()
        let scheduler = NSBackgroundActivityScheduler(identifier: "app.tobias.Tobias.scan")
        scheduler.repeats = true
        scheduler.interval = interval
        scheduler.tolerance = interval / 6
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task {
                await action()
                completion(.finished)
            }
        }
        activity = scheduler
    }
}

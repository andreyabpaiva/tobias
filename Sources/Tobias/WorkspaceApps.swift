import AppKit
import TobiasCore

struct WorkspaceApps: RunningApps {
    func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func quit(bundleID: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
    }
}

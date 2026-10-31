import Foundation

/// Every user-visible string lives here so copy can change without touching views.
enum Strings {
    static let appName = "Tobias"
    static let scanNow = "Scan now"
    static let scanning = "Scanning…"
    static let neverScanned = "Not scanned yet"
    static let cleanSelected = "Clean selected…"
    static let nothingSelected = "Select what to clean"
    static let cancel = "Cancel"
    static let close = "Close"
    static let copy = "Copy"
    static let copied = "Copied"
    static let quitApp = "Quit app"

    static let freeSpace = "Free space"
    static let reclaimable = "Reclaimable"
    static let free = "free"
    static let used = "Used"
    static let freeLegend = "Free"
    static let blocked = "Blocked"
    static let blockedHint = "Grant Full Disk Access to Tobias in System Settings → Privacy & Security."
    static let manual = "Manual"
    static let manualHint = "Needs administrator rights. Tobias never runs sudo; run this yourself in Terminal."
    static let manualShort = "Needs administrator rights."
    static let empty = "Nothing to clean"
    static let notFound = "Not found on this Mac"
    static let redownloads = "Downloads again"
    static let regenerates = "Rebuilt automatically"

    static let groupKnown = "Known targets"
    static let groupAppCaches = "Other app caches"
    static let groupLeftovers = "Leftovers"
    static let selectAll = "Select all"
    static let appRemoved = "App removed"
    static let ownerUnknown = "No matching app"

    static let confirmTitle = "Delete these files?"
    static let confirmBody = "Files are deleted permanently, not moved to the Trash."
    static let redownloadWarning = "This will have to be downloaded again if you use it."
    static let deleteButton = "Delete"
    static let running = "Cleaning…"
    static let resultsTitle = "Done"
    static let rejected = "Not allowed"

    static let restartTitle = "Restart your Mac"
    static let restartBody = "The System Data figure in System Settings only updates after a restart. Free space shown here is the reliable number."
    static let dismiss = "Dismiss"

    static let settings = "Settings"
    static let launchAtLogin = "Open Tobias at login"
    static let scanEvery = "Scan every"
    static let lowSpaceAlert = "Notify me when free space is low"
    static let showData = "Show data folder"
    static let openTobias = "Open Tobias"
    static let quit = "Quit Tobias"

    static func hours(_ n: Int) -> String { n == 1 ? "1 hour" : "\(n) hours" }
    static func selected(_ n: Int) -> String { n == 1 ? "1 selected" : "\(n) selected" }
    static func freed(_ size: String) -> String { "Freed \(size)" }
    static func lastScan(_ relative: String) -> String { "Scanned \(relative)" }
    static func quitFirst(_ apps: String) -> String { "Quit first: \(apps)" }
    static func ofTotal(_ size: String) -> String { "of \(size)" }
    static func legend(_ label: String, _ size: String) -> String { "\(label) · \(size)" }
    static let tipLead = "Clean everything reclaimable and you get to "
    static func tipFigure(_ size: String) -> String { "\(size) free" }
    static func showCommand(_ label: String) -> String { "Show command for \(label)" }
}

import Foundation

public enum OwnerStatus: String, Sendable, Hashable {
    /// An installed app owns this folder.
    case installed
    /// The folder is named after a bundle id and no installed app has it.
    case appRemoved
    /// The folder has a plain name and no installed app matches it.
    case ownerUnknown
}

/// What discovery found out about a generated target. Not part of `catalog.json`.
public struct DiscoveryInfo: Sendable, Hashable {
    public var status: OwnerStatus
    public var appName: String?
}

public struct InstalledApp: Sendable, Hashable {
    public var name: String
    public var bundleID: String

    public init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

/// The apps installed on this Mac, used to tell a live app's cache from a leftover.
public struct AppIndex: Sendable {
    public var apps: [InstalledApp]
    private let bundleFallback: @Sendable (String) -> Bool

    /// `bundleFallback` is asked about a bundle id the index does not know (Spotlight in production).
    public init(apps: [InstalledApp], bundleFallback: @escaping @Sendable (String) -> Bool = { _ in false }) {
        self.apps = apps
        self.bundleFallback = bundleFallback
    }

    public static func system(home: String = NSHomeDirectory()) -> AppIndex {
        let dirs = [
            "/Applications", "/Applications/Utilities", "/System/Applications",
            "/System/Applications/Utilities", home + "/Applications",
        ]
        return AppIndex(apps: scan(directories: dirs), bundleFallback: spotlightKnows)
    }

    /// Reads `Contents/Info.plist` of every `.app` in the folders and one level below them.
    public static func scan(directories: [String]) -> [InstalledApp] {
        let fm = FileManager.default
        var found: [InstalledApp] = []
        func visit(_ dir: String, depth: Int) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for name in names where !name.hasPrefix(".") {
                let path = dir + "/" + name
                if name.hasSuffix(".app") {
                    if let app = readApp(at: path) { found.append(app) }
                } else if depth == 0 {
                    visit(path, depth: 1)
                }
            }
        }
        directories.forEach { visit($0, depth: 0) }
        return found
    }

    private static func readApp(at path: String) -> InstalledApp? {
        let plist = NSDictionary(contentsOfFile: path + "/Contents/Info.plist")
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let name = (plist?["CFBundleDisplayName"] as? String) ?? (plist?["CFBundleName"] as? String) ?? stem
        let id = (plist?["CFBundleIdentifier"] as? String) ?? ""
        return InstalledApp(name: name, bundleID: id)
    }

    // MARK: - Matching

    /// Apps whose bundle id equals `id` or sits directly above or below it (`com.x.App` vs `com.x.App.helper`).
    public func apps(matchingBundleID id: String) -> [InstalledApp] {
        apps.filter { app in
            !app.bundleID.isEmpty
                && (app.bundleID == id || id.hasPrefix(app.bundleID + ".") || app.bundleID.hasPrefix(id + "."))
        }
    }

    public func knowsBundleID(_ id: String) -> Bool {
        !apps(matchingBundleID: id).isEmpty || bundleFallback(id)
    }

    /// Apps a plain folder name (`zen`, `BraveSoftware`, `JetBrains`) could belong to. Matches the app
    /// name, its words and the parts of its bundle id, so a vendor folder finds the vendor's apps.
    /// Errs towards "installed": a wrong match only means a leftover is not labelled as one.
    public func apps(matchingName folder: String) -> [InstalledApp] {
        let f = Self.normalize(folder)
        guard !f.isEmpty else { return [] }
        return apps.filter { app in Self.tokens(of: app).contains { Self.matches(f, $0) } }
    }

    static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static let genericParts: Set<String> = ["com", "org", "net", "io", "app", "co", "dev", "www", "mac", "macos"]

    static func tokens(of app: InstalledApp) -> Set<String> {
        var out: Set<String> = [normalize(app.name)]
        for word in app.name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            out.insert(normalize(String(word)))
        }
        for part in app.bundleID.split(separator: ".") where !genericParts.contains(part.lowercased()) {
            out.insert(normalize(String(part)))
        }
        return out.filter { $0.count >= 3 }
    }

    static func matches(_ folder: String, _ token: String) -> Bool {
        if folder == token { return true }
        if token.count >= 4 && folder.hasPrefix(token) { return true }
        if folder.count >= 4 && token.hasPrefix(folder) { return true }
        return false
    }

    /// Asks Spotlight whether an app with this bundle id exists anywhere on the Mac.
    static func spotlightKnows(_ id: String) -> Bool {
        guard id.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemCFBundleIdentifier == '\(id)'"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .contains { $0.hasSuffix(".app") && !$0.contains("/.Trash/") }
    }
}

/// Finds per-app folders in `~/Library/Caches` and `~/Library/Logs` that the catalog does not list,
/// and turns each into an ordinary `removeContents` target. Everything still goes through the
/// preview, the confirmation and `PathGuard`; discovery only enumerates, it never deletes.
public struct CacheDiscovery: Sendable {
    public static let defaultMinBytes: Int64 = 20 * 1024 * 1024

    private let pathGuard: PathGuard
    private let apps: AppIndex

    public init(pathGuard: PathGuard, apps: AppIndex = .system()) {
        self.pathGuard = pathGuard
        self.apps = apps
    }

    private struct Root {
        let relative: String
        let idPrefix: String
        let noun: String
    }

    private static let roots = [
        Root(relative: "Library/Caches", idPrefix: "cache", noun: "cache"),
        Root(relative: "Library/Logs", idPrefix: "logs", noun: "logs"),
    ]

    /// System-owned or self-managed folders that are never offered.
    private static let skipped: Set<String> = ["CloudKit", "Metadata", "FamilyCircle", "GeoServices", "Tobias", "app.tobias.Tobias"]

    public func discover(excluding catalog: [Target]) -> [Target] {
        let covered = catalog.flatMap { $0.resolvedPaths(using: pathGuard) }.map(PathGuard.canonical)
        var out: [Target] = []
        for root in Self.roots {
            let dir = pathGuard.home + "/" + root.relative
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
            for name in names where isCandidate(name) {
                let path = dir + "/" + name
                guard isPlainDirectory(path) else { continue }
                let canonical = PathGuard.canonical(path)
                if covered.contains(where: { isUnder(canonical, $0) || isUnder($0, canonical) }) { continue }
                let pattern = "~/" + root.relative + "/" + name
                guard (try? pathGuard.validatePattern(pattern)) != nil else { continue }
                out.append(makeTarget(name: name, pattern: pattern, root: root))
            }
        }
        return out
    }

    /// Generated targets that are big enough to be worth listing.
    public static func keepingLarge(_ found: [Target], sizes: [TargetSize], minBytes: Int64 = defaultMinBytes) -> [Target] {
        let bytes = Dictionary(uniqueKeysWithValues: sizes.map { ($0.id, $0.bytes) })
        return found.filter { (bytes[$0.id] ?? 0) >= minBytes }
    }

    // MARK: - Internals

    private func isCandidate(_ name: String) -> Bool {
        if name.hasPrefix(".") || name.hasPrefix("com.apple.") || Self.skipped.contains(name) { return false }
        // `Glob.expand` would treat these as a pattern and could select other folders.
        return !name.contains { "*?[]{}~".contains($0) }
    }

    private func isPlainDirectory(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    private func isUnder(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    static func looksLikeBundleID(_ name: String) -> Bool {
        guard name.contains("."), !name.contains(" ") else { return false }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty }), let first = parts.first else { return false }
        return first.allSatisfy { $0.isLetter && $0.isLowercase }
    }

    private func makeTarget(name: String, pattern: String, root: Root) -> Target {
        let isBundle = Self.looksLikeBundleID(name)
        var matched = isBundle ? apps.apps(matchingBundleID: name) : apps.apps(matchingName: name)
        var quit = matched.map(\.bundleID).filter { !$0.isEmpty }
        if matched.isEmpty && isBundle && apps.knowsBundleID(name) {
            quit = [name]
            matched = [InstalledApp(name: name, bundleID: name)]
        }

        let status: OwnerStatus = matched.isEmpty ? (isBundle ? .appRemoved : .ownerUnknown) : .installed
        let appName = matched.count == 1 ? matched[0].name : nil
        let shown = appName ?? name
        let note: String
        switch status {
        case .installed:
            note = "\(root.noun == "logs" ? "Log files" : "Cache") of \(appName ?? "an installed app"). Rebuilt by the app. Quit it first."
        case .appRemoved:
            note = "The app that wrote this is no longer installed."
        case .ownerUnknown:
            note = "No installed app matches this name. It may be left from a removed app or belong to a command-line tool; it is rebuilt if still used."
        }
        return Target(
            id: "\(root.idPrefix):\(name)", label: "\(shown) \(root.noun)", note: note, paths: [pattern],
            action: .removeContents, quitApps: Array(Set(quit)).sorted(), risk: .regenerates,
            discovery: DiscoveryInfo(status: status, appName: appName)
        )
    }
}

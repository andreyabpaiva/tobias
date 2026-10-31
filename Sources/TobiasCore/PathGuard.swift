import Foundation

public enum GuardError: Error, Equatable, CustomStringConvertible {
    case notAbsolute(String)
    case traversal(String)
    case symlinkTarget(String)
    case outsideAllowedRoots(String)
    case protectedPath(String)
    case tooBroad(String)

    public var description: String {
        switch self {
        case .notAbsolute(let p): return "Path is not absolute: \(p)"
        case .traversal(let p): return "Path contains '..': \(p)"
        case .symlinkTarget(let p): return "Path is a symbolic link: \(p)"
        case .outsideAllowedRoots(let p): return "Path is outside the allowed folders: \(p)"
        case .protectedPath(let p): return "Path is protected: \(p)"
        case .tooBroad(let p): return "Pattern is too broad: \(p)"
        }
    }
}

/// Decides which paths Tobias may ever delete. Every removal goes through here.
public struct PathGuard: Sendable {
    public let home: String
    public let allowedRoots: [String]
    private let protectedExact: Set<String>
    private let protectedTrees: [String]

    public init(home: String = NSHomeDirectory(), extraRoots: [String] = ["/opt/homebrew"]) {
        let h = PathGuard.canonical(home)
        self.home = h
        self.allowedRoots = [h] + extraRoots.map { PathGuard.canonical($0) }

        var exact: Set<String> = ["/"]
        for root in allowedRoots { exact.insert(root) }
        for sub in [
            "Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Public",
            "Applications", "Library/Application Support", "Library/Caches", "Library/Containers",
            "Library/Group Containers", "Library/Preferences", "Library/Logs", "Library/Developer",
        ] {
            exact.insert(h + "/" + sub)
        }
        for root in extraRoots.map({ PathGuard.canonical($0) }) {
            exact.insert(root + "/Cellar")
            exact.insert(root + "/bin")
        }
        self.protectedExact = exact
        self.protectedTrees = [
            ".ssh", ".gnupg", "Library/Keychains", "Library/Mail", "Library/Messages",
            "Library/Mobile Documents",
        ].map { h + "/" + $0 }
    }

    // MARK: - Path helpers

    public static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    public func expand(_ path: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }

    private func isUnder(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    private func underAllowedRoot(_ path: String) -> Bool {
        allowedRoots.contains { isUnder(path, $0) }
    }

    private func checkProtected(_ resolved: String) throws {
        if protectedExact.contains(resolved) { throw GuardError.protectedPath(resolved) }
        if protectedTrees.contains(where: { isUnder(resolved, $0) }) {
            throw GuardError.protectedPath(resolved)
        }
    }

    // MARK: - Validation

    /// Static check of a catalog pattern, done once at load time.
    public func validatePattern(_ pattern: String) throws {
        let expanded = expand(pattern)
        guard expanded.hasPrefix("/") else { throw GuardError.notAbsolute(pattern) }
        guard !expanded.split(separator: "/").contains("..") else { throw GuardError.traversal(pattern) }

        if Glob.hasMagic(expanded) {
            let firstMagic = expanded.firstIndex { "*?[{".contains($0) }!
            let literal = String(expanded[..<firstMagic])
            guard let slash = literal.lastIndex(of: "/") else { throw GuardError.tooBroad(pattern) }
            let dir = PathGuard.canonical(String(literal[..<slash]))
            guard underAllowedRoot(dir) else { throw GuardError.outsideAllowedRoots(pattern) }
            // A wildcard directly under a protected folder would select unrelated apps' data.
            if protectedExact.contains(dir) || protectedTrees.contains(where: { isUnder(dir, $0) }) {
                throw GuardError.tooBroad(pattern)
            }
        } else {
            let resolved = PathGuard.canonical(expanded)
            guard underAllowedRoot(resolved) else { throw GuardError.outsideAllowedRoots(pattern) }
            try checkProtected(resolved)
        }
    }

    /// Runtime check right before touching a concrete path. Returns the resolved path.
    @discardableResult
    public func validateForRemoval(_ path: String) throws -> String {
        let expanded = expand(path)
        guard expanded.hasPrefix("/") else { throw GuardError.notAbsolute(path) }
        guard !expanded.split(separator: "/").contains("..") else { throw GuardError.traversal(path) }

        var st = stat()
        if lstat(expanded, &st) == 0, (st.st_mode & S_IFMT) == S_IFLNK {
            throw GuardError.symlinkTarget(path)
        }
        let resolved = PathGuard.canonical(expanded)
        guard underAllowedRoot(resolved) else { throw GuardError.outsideAllowedRoots(resolved) }
        try checkProtected(resolved)
        return resolved
    }
}

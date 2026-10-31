import Foundation

public struct TargetSize: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var bytes: Int64
    public var files: Int
    public var exists: Bool
    public var blocked: Bool
    public var timedOut: Bool

    public init(id: String, bytes: Int64 = 0, files: Int = 0, exists: Bool = false, blocked: Bool = false, timedOut: Bool = false) {
        self.id = id
        self.bytes = bytes
        self.files = files
        self.exists = exists
        self.blocked = blocked
        self.timedOut = timedOut
    }
}

public struct Measurement: Sendable, Equatable {
    public var bytes: Int64 = 0
    public var files: Int = 0
    public var exists = false
    public var blocked = false
    public var timedOut = false

    public init() {}
}

/// Measures allocated size on disk. Read-only. Skips symlinks, stays on one device, counts hard links once.
public struct DiskScanner: Sendable {
    public var perTargetTimeout: TimeInterval
    public var concurrency: Int

    public init(perTargetTimeout: TimeInterval = 60, concurrency: Int = 4) {
        self.perTargetTimeout = perTargetTimeout
        self.concurrency = max(1, concurrency)
    }

    public func measure(paths: [String], timeout: TimeInterval? = nil) -> Measurement {
        let deadline = Date().addingTimeInterval(timeout ?? perTargetTimeout)
        var result = Measurement()
        var seen = Set<InodeKey>()
        for path in paths {
            walk(path, deadline: deadline, result: &result, seen: &seen)
            if result.timedOut { break }
        }
        return result
    }

    public func measure(_ target: Target, pathGuard: PathGuard) -> TargetSize {
        let m = measure(paths: target.resolvedPaths(using: pathGuard))
        return TargetSize(id: target.id, bytes: m.bytes, files: m.files, exists: m.exists, blocked: m.blocked, timedOut: m.timedOut)
    }

    /// Scans all targets with bounded concurrency. Results keep the input order.
    public func scan(_ targets: [Target], pathGuard: PathGuard) async -> [TargetSize] {
        var results = [TargetSize?](repeating: nil, count: targets.count)
        await withTaskGroup(of: (Int, TargetSize).self) { group in
            var next = 0
            func launch() {
                guard next < targets.count else { return }
                let index = next
                let target = targets[index]
                next += 1
                group.addTask {
                    await withCheckedContinuation { cont in
                        DispatchQueue.global(qos: .utility).async {
                            cont.resume(returning: (index, self.measure(target, pathGuard: pathGuard)))
                        }
                    }
                }
            }
            for _ in 0..<concurrency { launch() }
            while let (index, size) = await group.next() {
                results[index] = size
                launch()
            }
        }
        return results.enumerated().map { $0.element ?? TargetSize(id: targets[$0.offset].id) }
    }

    // MARK: - Walking

    private struct InodeKey: Hashable {
        let dev: Int32
        let ino: UInt64
    }

    private func walk(_ root: String, deadline: Date, result: inout Measurement, seen: inout Set<InodeKey>) {
        var st = stat()
        if lstat(root, &st) != 0 {
            if errno == EPERM || errno == EACCES { result.blocked = true; result.exists = true }
            return
        }
        result.exists = true
        let mode = st.st_mode & S_IFMT
        if mode == S_IFLNK { return }
        if mode == S_IFREG {
            add(st, to: &result, seen: &seen)
            return
        }
        guard mode == S_IFDIR else { return }

        let rootDev = st.st_dev
        var blocked = false
        let url = URL(fileURLWithPath: root)
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, error in
                let ns = error as NSError
                if ns.code == NSFileReadNoPermissionError
                    || (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(EPERM)
                    || (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(EACCES) {
                    blocked = true
                }
                return true
            }
        )
        var counter = 0
        while let item = enumerator?.nextObject() as? URL {
            counter += 1
            if counter % 256 == 0, Date() > deadline {
                result.timedOut = true
                break
            }
            var s = stat()
            guard lstat(item.path, &s) == 0 else { continue }
            let m = s.st_mode & S_IFMT
            if m == S_IFDIR {
                if s.st_dev != rootDev { enumerator?.skipDescendants() }
            } else if m == S_IFREG {
                add(s, to: &result, seen: &seen)
            }
        }
        if blocked { result.blocked = true }
    }

    private func add(_ st: stat, to result: inout Measurement, seen: inout Set<InodeKey>) {
        if st.st_nlink > 1 {
            let key = InodeKey(dev: st.st_dev, ino: UInt64(st.st_ino))
            if !seen.insert(key).inserted { return }
        }
        result.bytes += Int64(st.st_blocks) * 512
        result.files += 1
    }
}

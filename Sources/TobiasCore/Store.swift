import Foundation

public struct Snapshot: Codable, Sendable, Equatable {
    public var date: Date
    public var disk: DiskSpace
    public var sizes: [TargetSize]

    public init(date: Date, disk: DiskSpace, sizes: [TargetSize]) {
        self.date = date
        self.disk = disk
        self.sizes = sizes
    }
}

public struct HistoryPoint: Codable, Sendable, Equatable {
    public var date: Date
    public var availableRaw: Int64

    public init(date: Date, availableRaw: Int64) {
        self.date = date
        self.availableRaw = availableRaw
    }
}

public struct StoredState: Codable, Sendable, Equatable {
    public var lastScan: Snapshot?
    public var history: [HistoryPoint]

    public init(lastScan: Snapshot? = nil, history: [HistoryPoint] = []) {
        self.lastScan = lastScan
        self.history = history
    }
}

public struct AuditEntry: Codable, Sendable, Equatable {
    public var time: Date
    public var id: String
    public var status: String
    public var freedBytes: Int64
    public var detail: String

    public init(time: Date = Date(), id: String, status: String, freedBytes: Int64, detail: String) {
        self.time = time
        self.id = id
        self.status = status
        self.freedBytes = freedBytes
        self.detail = detail
    }
}

/// State and audit log under ~/Library/Application Support/Tobias (override with TOBIAS_HOME).
public final class Store: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private let maxHistory = 200

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let env = ProcessInfo.processInfo.environment["TOBIAS_HOME"], !env.isEmpty {
            self.directory = URL(fileURLWithPath: env, isDirectory: true)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.directory = base.appendingPathComponent("Tobias", isDirectory: true)
        }
    }

    public var stateURL: URL { directory.appendingPathComponent("state.json") }
    public var auditURL: URL { directory.appendingPathComponent("audit.log") }
    public var userTargetsURL: URL { directory.appendingPathComponent("targets.json") }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func load() -> StoredState {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? decoder.decode(StoredState.self, from: data) else { return StoredState() }
        return state
    }

    public func save(_ state: StoredState) throws {
        lock.lock(); defer { lock.unlock() }
        try ensureDirectory()
        var s = state
        if s.history.count > maxHistory { s.history = Array(s.history.suffix(maxHistory)) }
        try encoder.encode(s).write(to: stateURL, options: .atomic)
    }

    public func record(snapshot: Snapshot) throws -> StoredState {
        var state = load()
        state.lastScan = snapshot
        state.history.append(HistoryPoint(date: snapshot.date, availableRaw: snapshot.disk.availableRaw))
        try save(state)
        return state
    }

    public func appendAudit(_ entry: AuditEntry) {
        lock.lock(); defer { lock.unlock() }
        do {
            try ensureDirectory()
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            e.outputFormatting = [.sortedKeys]
            var line = try e.encode(entry)
            line.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: auditURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: auditURL, options: .atomic)
            }
        } catch {
            // Audit failure must never block the caller; the result is still returned to the UI.
        }
    }
}

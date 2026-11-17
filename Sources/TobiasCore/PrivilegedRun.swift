import Foundation

/// Runs a `rootCommand` through `sudo`, streaming its output. The password is asked every run
/// and passed straight to sudo, never kept.
public final class PrivilegedRun: @unchecked Sendable {
    public enum Event: Sendable, Equatable {
        case output(String)
        case passwordPrompt
        case exited(Int32)
    }

    public static let promptMarker = "__TOBIAS_SUDO__"
    public static let sudo = "/usr/bin/sudo"

    /// What `start()` runs for `command`: sudo, then a plain `sh -c`.
    public static func arguments(for command: String) -> [String] {
        ["-S", "-k", "-p", promptMarker, "/bin/sh", "-c", command]
    }

    public let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private var pending = ""

    /// `executable` and `arguments` are for tests; the app uses the defaults.
    public init(command: String, executable: String = PrivilegedRun.sudo, arguments: [String]? = nil) {
        (events, continuation) = AsyncStream.makeStream(of: Event.self)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments ?? Self.arguments(for: command)
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        process.currentDirectoryURL = URL(fileURLWithPath: "/")
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
    }

    public func start() throws {
        // Writing a password after sudo has gone away must not kill the app.
        signal(SIGPIPE, SIG_IGN)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }
        process.terminationHandler = { [weak self] process in
            // Give output already in the pipe a moment to arrive. Reading to end of file instead would
            // hang after `stop()`, because a child the shell started can keep the pipe open.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                guard let self else { return }
                self.output.fileHandleForReading.readabilityHandler = nil
                self.flush()
                try? self.input.fileHandleForWriting.close()
                self.continuation.yield(.exited(process.terminationStatus))
                self.continuation.finish()
            }
        }
        do {
            try process.run()
        } catch {
            continuation.yield(.output("Could not start: \(error.localizedDescription)\n"))
            continuation.yield(.exited(-1))
            continuation.finish()
            throw error
        }
    }

    public func sendPassword(_ password: String) {
        try? input.fileHandleForWriting.write(contentsOf: Data((password + "\n").utf8))
    }

    public func stop() {
        if process.isRunning { process.terminate() }
    }

    // MARK: - Output

    private func consume(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        pending += String(decoding: data, as: UTF8.self)
        while let range = pending.range(of: Self.promptMarker) {
            let before = String(pending[..<range.lowerBound])
            if !before.isEmpty { continuation.yield(.output(before)) }
            continuation.yield(.passwordPrompt)
            pending = String(pending[range.upperBound...])
        }
        // Hold back a tail that could be the start of a marker split across reads.
        let keep = Self.markerPrefixLength(at: pending)
        let ready = String(pending.dropLast(keep))
        if !ready.isEmpty { continuation.yield(.output(ready)) }
        pending = String(pending.suffix(keep))
    }

    private func flush() {
        lock.lock()
        defer { lock.unlock() }
        if !pending.isEmpty { continuation.yield(.output(pending)) }
        pending = ""
    }

    /// Length of the longest suffix of `text` that is a proper prefix of the marker.
    static func markerPrefixLength(at text: String) -> Int {
        let marker = promptMarker
        for length in stride(from: min(marker.count - 1, text.count), to: 0, by: -1)
        where text.hasSuffix(marker.prefix(length)) {
            return length
        }
        return 0
    }
}

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
    private var exitStatus: Int32?
    private var outputClosed = false
    private var finished = false

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
        // The handlers hold `self` strongly until the run finishes, so the stream always ends.
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                self.closeOutput()
            } else {
                self.consume(data)
            }
        }
        process.terminationHandler = { process in
            self.markExited(process.terminationStatus)
            // A child the shell started can keep the output open after `stop()`, so don't wait for it.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { self.closeOutput() }
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

    // MARK: - Finishing

    private func markExited(_ status: Int32) {
        lock.lock()
        exitStatus = status
        lock.unlock()
        finishIfDone()
    }

    private func closeOutput() {
        lock.lock()
        outputClosed = true
        lock.unlock()
        finishIfDone()
    }

    /// Ends the stream once: after the process exited and its output closed (or the grace period passed).
    private func finishIfDone() {
        lock.lock()
        guard !finished, let status = exitStatus, outputClosed else {
            lock.unlock()
            return
        }
        finished = true
        if !pending.isEmpty { continuation.yield(.output(pending)) }
        pending = ""
        lock.unlock()
        output.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? input.fileHandleForWriting.close()
        continuation.yield(.exited(status))
        continuation.finish()
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

import Foundation

public protocol RunningApps: Sendable {
    func isRunning(bundleID: String) -> Bool
}

public struct NoRunningApps: RunningApps {
    public init() {}
    public func isRunning(bundleID: String) -> Bool { false }
}

public struct CommandOutput: Sendable, Equatable {
    public var exit: Int32
    public var output: String
    public var timedOut: Bool

    public init(exit: Int32, output: String, timedOut: Bool = false) {
        self.exit = exit
        self.output = output
        self.timedOut = timedOut
    }
}

public protocol CommandRunner: Sendable {
    func run(_ command: String, timeout: TimeInterval) async -> CommandOutput
}

/// Runs a fixed catalog string in a login shell so nvm and Homebrew paths resolve.
/// A Finder-launched app starts in `/`, the read-only system volume, and tools like pnpm pick
/// their cache location (and write temp files) relative to the working directory, so commands
/// run from the home folder instead.
public struct ZshRunner: CommandRunner {
    public var workingDirectory: String

    public init(workingDirectory: String = NSHomeDirectory()) {
        self.workingDirectory = workingDirectory
    }

    public func run(_ command: String, timeout: TimeInterval) async -> CommandOutput {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                let outURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("tobias-\(UUID().uuidString).log")
                FileManager.default.createFile(atPath: outURL.path, contents: nil)
                defer { try? FileManager.default.removeItem(at: outURL) }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-ilc", command]
                process.currentDirectoryURL = URL(fileURLWithPath: self.workingDirectory)
                if let handle = try? FileHandle(forWritingTo: outURL) {
                    process.standardOutput = handle
                    process.standardError = handle
                }
                process.standardInput = FileHandle.nullDevice

                var timedOut = false
                do {
                    try process.run()
                } catch {
                    cont.resume(returning: CommandOutput(exit: -1, output: "Could not start: \(error)"))
                    return
                }
                let killer = DispatchWorkItem {
                    if process.isRunning { timedOut = true; process.terminate() }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                process.waitUntilExit()
                killer.cancel()

                let data = (try? Data(contentsOf: outURL)) ?? Data()
                let text = String(decoding: data.suffix(4000), as: UTF8.self)
                cont.resume(returning: CommandOutput(exit: process.terminationStatus, output: text, timedOut: timedOut))
            }
        }
    }
}

public struct PreviewItem: Sendable, Equatable {
    public var path: String
    public var bytes: Int64
}

public struct CleanPreview: Sendable, Equatable {
    public var id: String
    public var label: String
    public var action: ActionKind
    public var risk: Risk
    public var totalBytes: Int64
    public var items: [PreviewItem]
    public var command: String?
    public var manualCommand: String?
    public var runningApps: [String]
    public var rejection: String?

    public var canRun: Bool { action != .manual && runningApps.isEmpty && rejection == nil }
}

public enum CleanStatus: String, Codable, Sendable {
    case cleaned
    case blocked
    case failed
    case manual
    case nothingToDo
}

public struct CleanResult: Sendable, Equatable {
    public var id: String
    public var status: CleanStatus
    public var freedBytes: Int64
    public var detail: String
}

public final class Executor: @unchecked Sendable {
    private let pathGuard: PathGuard
    private let scanner: DiskScanner
    private let store: Store?
    private let apps: RunningApps
    private let runner: CommandRunner
    private let commandTimeout: TimeInterval

    public init(
        pathGuard: PathGuard, scanner: DiskScanner = DiskScanner(), store: Store? = nil,
        apps: RunningApps = NoRunningApps(), runner: CommandRunner = ZshRunner(),
        commandTimeout: TimeInterval = 300
    ) {
        self.pathGuard = pathGuard
        self.scanner = scanner
        self.store = store
        self.apps = apps
        self.runner = runner
        self.commandTimeout = commandTimeout
    }

    // MARK: - CleanPreview (read-only)

    public func preview(_ target: Target) -> CleanPreview {
        let running = target.quitApps.filter { apps.isRunning(bundleID: $0) }
        var p = CleanPreview(
            id: target.id, label: target.label, action: target.action, risk: target.risk,
            totalBytes: 0, items: [], command: target.command, manualCommand: target.manualCommand,
            runningApps: running, rejection: nil
        )
        let paths = target.resolvedPaths(using: pathGuard)
        p.totalBytes = scanner.measure(paths: paths).bytes

        guard target.action == .removeContents else { return p }
        var children: [PreviewItem] = []
        for path in paths {
            do {
                let resolved = try pathGuard.validateForRemoval(path)
                for child in childPaths(of: resolved) {
                    children.append(PreviewItem(path: child, bytes: scanner.measure(paths: [child], timeout: 10).bytes))
                }
            } catch {
                p.rejection = "\(error)"
                return p
            }
        }
        p.items = Array(children.sorted { $0.bytes > $1.bytes }.prefix(8))
        return p
    }

    // MARK: - Run

    public func run(_ target: Target) async -> CleanResult {
        let result = await execute(target)
        store?.appendAudit(AuditEntry(id: target.id, status: result.status.rawValue, freedBytes: result.freedBytes, detail: result.detail))
        return result
    }

    private func execute(_ target: Target) async -> CleanResult {
        if target.action == .manual {
            return CleanResult(id: target.id, status: .manual, freedBytes: 0, detail: "Run this yourself: \(target.manualCommand ?? "")")
        }
        let running = target.quitApps.filter { apps.isRunning(bundleID: $0) }
        if !running.isEmpty {
            return CleanResult(id: target.id, status: .blocked, freedBytes: 0, detail: "Quit first: \(running.joined(separator: ", "))")
        }

        let paths = target.resolvedPaths(using: pathGuard)
        let before = scanner.measure(paths: paths).bytes

        switch target.action {
        case .removeContents:
            return removeContents(target, paths: paths, before: before)
        case .command:
            guard let command = target.command else {
                return CleanResult(id: target.id, status: .failed, freedBytes: 0, detail: "No command")
            }
            let out = await runner.run(command, timeout: commandTimeout)
            let after = scanner.measure(paths: target.resolvedPaths(using: pathGuard)).bytes
            let freed = max(0, before - after)
            if out.timedOut {
                return CleanResult(id: target.id, status: .failed, freedBytes: freed, detail: "Timed out running: \(command)")
            }
            if out.exit != 0 {
                return CleanResult(id: target.id, status: .failed, freedBytes: freed, detail: "Exit \(out.exit): \(out.output.suffix(300))")
            }
            return CleanResult(id: target.id, status: .cleaned, freedBytes: freed, detail: "Ran: \(command)")
        case .manual:
            return CleanResult(id: target.id, status: .manual, freedBytes: 0, detail: "")
        }
    }

    private func removeContents(_ target: Target, paths: [String], before: Int64) -> CleanResult {
        if paths.isEmpty {
            return CleanResult(id: target.id, status: .nothingToDo, freedBytes: 0, detail: "Nothing found")
        }
        var removed = 0
        var failures: [String] = []
        for path in paths {
            let resolved: String
            do { resolved = try pathGuard.validateForRemoval(path) } catch {
                return CleanResult(id: target.id, status: .failed, freedBytes: 0, detail: "Rejected: \(error)")
            }
            for child in childPaths(of: resolved) {
                do {
                    try FileManager.default.removeItem(atPath: child)
                    removed += 1
                } catch {
                    failures.append((child as NSString).lastPathComponent)
                }
            }
        }
        let after = scanner.measure(paths: paths).bytes
        let freed = max(0, before - after)
        if removed == 0 && failures.isEmpty {
            return CleanResult(id: target.id, status: .nothingToDo, freedBytes: 0, detail: "Already empty")
        }
        if removed == 0 {
            return CleanResult(id: target.id, status: .failed, freedBytes: freed, detail: "Could not remove \(failures.count) items. Grant Full Disk Access if this keeps happening.")
        }
        let tail = failures.isEmpty ? "" : " (\(failures.count) items skipped)"
        return CleanResult(id: target.id, status: .cleaned, freedBytes: freed, detail: "Removed \(removed) items\(tail)")
    }

    private func childPaths(of directory: String) -> [String] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory, isDirectory: &isDir), isDir.boolValue else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        return names.map { (directory as NSString).appendingPathComponent($0) }
    }
}

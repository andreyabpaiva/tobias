import Foundation
@testable import TobiasCore

/// A throwaway home directory so tests never touch real files.
final class Sandbox {
    let home: URL
    let pathGuard: PathGuard

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("tobias-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        home = base.resolvingSymlinksInPath()
        pathGuard = PathGuard(home: home.path, extraRoots: [])
    }

    deinit { try? FileManager.default.removeItem(at: home) }

    func path(_ relative: String) -> String { home.appendingPathComponent(relative).path }

    @discardableResult
    func makeDir(_ relative: String) throws -> String {
        let p = path(relative)
        try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }

    @discardableResult
    func makeFile(_ relative: String, kilobytes: Int = 64) throws -> String {
        let p = path(relative)
        try FileManager.default.createDirectory(
            atPath: (p as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: kilobytes * 1024).write(to: URL(fileURLWithPath: p))
        return p
    }

    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: path(relative)) }
}

struct StubRunner: CommandRunner {
    var exit: Int32 = 0
    var onRun: (@Sendable (String) -> Void)? = nil
    func run(_ command: String, timeout: TimeInterval) async -> CommandOutput {
        onRun?(command)
        return CommandOutput(exit: exit, output: "stub")
    }
}

struct StubApps: RunningApps {
    var running: Set<String>
    func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }
}

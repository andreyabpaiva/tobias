import Foundation
import Testing
@testable import TobiasCore

@Suite struct ExecutorTests {
    private func target(_ sb: Sandbox, _ rel: String, quit: [String] = []) -> Target {
        Target(id: "t", label: "T", paths: [sb.path(rel)], action: .removeContents, quitApps: quit)
    }

    @Test func removesChildrenButKeepsTheFolder() async throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/App/a.bin", kilobytes: 256)
        try sb.makeFile("Library/Caches/App/sub/b.bin", kilobytes: 256)
        let ex = Executor(pathGuard: sb.pathGuard)
        let result = await ex.run(target(sb, "Library/Caches/App"))
        #expect(result.status == .cleaned)
        #expect(result.freedBytes >= 512 * 1024)
        #expect(sb.exists("Library/Caches/App"))
        #expect(!sb.exists("Library/Caches/App/a.bin"))
        #expect(!sb.exists("Library/Caches/App/sub"))
    }

    @Test func doesNotFollowSymlinksOutOfTheTarget() async throws {
        let sb = try Sandbox()
        let precious = try sb.makeFile("Documents/precious.txt", kilobytes: 4)
        try sb.makeDir("Library/Caches/App")
        try FileManager.default.createSymbolicLink(
            atPath: sb.path("Library/Caches/App/link"), withDestinationPath: sb.path("Documents"))
        let ex = Executor(pathGuard: sb.pathGuard)
        _ = await ex.run(target(sb, "Library/Caches/App"))
        #expect(FileManager.default.fileExists(atPath: precious))
        #expect(!sb.exists("Library/Caches/App/link"))
    }

    @Test func refusesProtectedFolders() async throws {
        let sb = try Sandbox()
        try sb.makeFile("Documents/keep.txt", kilobytes: 4)
        let ex = Executor(pathGuard: sb.pathGuard)
        let result = await ex.run(target(sb, "Documents"))
        #expect(result.status == .failed)
        #expect(sb.exists("Documents/keep.txt"))
    }

    @Test func blocksWhileAppIsRunning() async throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/App/a.bin")
        let ex = Executor(pathGuard: sb.pathGuard, apps: StubApps(running: ["com.example.app"]))
        let result = await ex.run(target(sb, "Library/Caches/App", quit: ["com.example.app"]))
        #expect(result.status == .blocked)
        #expect(sb.exists("Library/Caches/App/a.bin"))
    }

    @Test func manualTargetsNeverRun() async throws {
        let sb = try Sandbox()
        let counter = Counter()
        let t = Target(id: "m", label: "M", paths: [sb.path("x")], action: .manual, manualCommand: "sudo something")
        let ex = Executor(pathGuard: sb.pathGuard, runner: StubRunner(onRun: { _ in counter.bump() }))
        let result = await ex.run(t)
        #expect(result.status == .manual)
        #expect(counter.value == 0)
    }

    @Test func commandTargetsRunTheFixedCommand() async throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/Tool/a.bin")
        let seen = Box()
        let t = Target(id: "c", label: "C", paths: [sb.path("Library/Caches/Tool")], action: .command, command: "tool clean")
        let ex = Executor(pathGuard: sb.pathGuard, runner: StubRunner(onRun: { seen.value = $0 }))
        let result = await ex.run(t)
        #expect(result.status == .cleaned)
        #expect(seen.value == "tool clean")
    }

    @Test func failedCommandIsReported() async throws {
        let sb = try Sandbox()
        let t = Target(id: "c", label: "C", paths: [sb.path("x")], action: .command, command: "tool clean")
        let ex = Executor(pathGuard: sb.pathGuard, runner: StubRunner(exit: 2))
        let result = await ex.run(t)
        #expect(result.status == .failed)
    }

    @Test func previewListsLargestChildrenWithoutDeleting() throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/App/small.bin", kilobytes: 4)
        try sb.makeFile("Library/Caches/App/big.bin", kilobytes: 512)
        let p = Executor(pathGuard: sb.pathGuard).preview(target(sb, "Library/Caches/App"))
        #expect(p.items.first?.path.hasSuffix("big.bin") == true)
        #expect(p.totalBytes >= 516 * 1024)
        #expect(p.canRun)
        #expect(sb.exists("Library/Caches/App/big.bin"))
    }

    @Test func previewReportsRejection() throws {
        let sb = try Sandbox()
        try sb.makeDir("Documents")
        let p = Executor(pathGuard: sb.pathGuard).preview(target(sb, "Documents"))
        #expect(p.rejection != nil)
        #expect(!p.canRun)
    }

    @Test func writesAuditLine() async throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/App/a.bin")
        let store = Store(directory: sb.home.appendingPathComponent("state"))
        let ex = Executor(pathGuard: sb.pathGuard, store: store)
        _ = await ex.run(target(sb, "Library/Caches/App"))
        let log = try String(contentsOf: store.auditURL, encoding: .utf8)
        #expect(log.contains("\"status\":\"cleaned\""))
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var v = ""
    var value: String {
        get { lock.lock(); defer { lock.unlock() }; return v }
        set { lock.lock(); v = newValue; lock.unlock() }
    }

    @Test func commandsRunFromTheWorkingDirectoryNotRoot() async throws {
        let sb = try Sandbox()
        let out = await ZshRunner(workingDirectory: sb.home.path).run("pwd", timeout: 30)
        #expect(out.output.contains(sb.home.lastPathComponent))
    }
}

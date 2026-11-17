import Foundation
import Testing
@testable import TobiasCore

@Suite struct CatalogTests {
    @Test func bundledCatalogIsValidForARealHome() throws {
        let catalog = try Catalog.load(userFile: nil, pathGuard: PathGuard())
        #expect(catalog.rejected.isEmpty)
        #expect(catalog.targets.count >= 10)
        let ids = catalog.targets.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func userTargetReplacesBundledId() throws {
        let sb = try Sandbox()
        let file = sb.home.appendingPathComponent("targets.json")
        let json = """
        [{"id":"npm","label":"My npm","paths":["~/.npm"],"action":"command","command":"npm cache clean --force"}]
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
        let catalog = try Catalog.load(userFile: file, pathGuard: sb.pathGuard)
        #expect(catalog.targets.first { $0.id == "npm" }?.label == "My npm")
    }

    @Test func unsafeUserTargetIsRejectedNotFatal() throws {
        let sb = try Sandbox()
        let file = sb.home.appendingPathComponent("targets.json")
        let json = """
        [{"id":"bad","label":"Bad","paths":["~/Documents"],"action":"removeContents"},
         {"id":"worse","label":"Worse","paths":["/etc/*"],"action":"removeContents"},
         {"id":"ok","label":"Ok","paths":["~/Library/Caches/Mine"],"action":"removeContents"}]
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
        let catalog = try Catalog.load(userFile: file, pathGuard: sb.pathGuard)
        #expect(catalog.rejected.map(\.id).contains("bad"))
        #expect(catalog.rejected.map(\.id).contains("worse"))
        #expect(catalog.targets.contains { $0.id == "ok" })
        #expect(!catalog.targets.contains { $0.id == "bad" })
    }

    @Test func commandTargetNeedsACommand() throws {
        let sb = try Sandbox()
        let file = sb.home.appendingPathComponent("targets.json")
        try """
        [{"id":"nocmd","label":"X","paths":["~/.x"],"action":"command"}]
        """.write(to: file, atomically: true, encoding: .utf8)
        let catalog = try Catalog.load(userFile: file, pathGuard: sb.pathGuard)
        #expect(catalog.rejected.map(\.id).contains("nocmd"))
    }

    @Test func brokenUserFileDoesNotBreakBundledTargets() throws {
        let sb = try Sandbox()
        let file = sb.home.appendingPathComponent("targets.json")
        try "not json".write(to: file, atomically: true, encoding: .utf8)
        let catalog = try Catalog.load(userFile: file, pathGuard: sb.pathGuard)
        #expect(!catalog.targets.isEmpty)
        #expect(!catalog.rejected.isEmpty)
    }
}

@Suite struct StoreTests {
    @Test func roundTripsStateAndCapsHistory() throws {
        let sb = try Sandbox()
        let store = Store(directory: sb.home.appendingPathComponent("s"))
        var state = StoredState()
        for i in 0..<250 {
            state.history.append(HistoryPoint(date: Date(timeIntervalSince1970: Double(i)), availableRaw: Int64(i)))
        }
        try store.save(state)
        let loaded = store.load()
        #expect(loaded.history.count == 200)
        #expect(loaded.history.last?.availableRaw == 249)
    }

    @Test func missingStateLoadsEmpty() throws {
        let sb = try Sandbox()
        #expect(Store(directory: sb.home.appendingPathComponent("none")).load() == StoredState())
    }

    @Test func userTargetCannotAddRootCommand() throws {
        let sb = try Sandbox()
        let file = sb.home.appendingPathComponent("targets.json")
        let json = """
        [{"id":"system-logs","label":"Mine","paths":["/private/var/log"],"action":"manual",
          "manualCommand":"x","rootCommand":"rm -rf /private/var/log"},
         {"id":"extra","label":"Extra","paths":["/tmp"],"action":"manual","manualCommand":"x","rootCommand":"true"}]
        """
        try json.write(to: file, atomically: true, encoding: .utf8)
        let catalog = try Catalog.load(userFile: file, pathGuard: sb.pathGuard)
        #expect(catalog.rejected.map(\.id).contains("system-logs"))
        #expect(catalog.rejected.map(\.id).contains("extra"))
        // The built-in entry survives with its reviewed command.
        #expect(catalog.targets.first { $0.id == "system-logs" }?.label == "System logs")
    }

    /// Pins the one command Tobias runs as root, so changing it is always a deliberate, reviewed edit.
    @Test func systemLogsRootCommandIsTheReviewedOne() throws {
        let rooted = try Catalog.bundledTargets().filter { $0.rootCommand != nil }
        #expect(rooted.map(\.id) == ["system-logs"])
        #expect(rooted.first?.rootCommand == """
        du -sh /private/var/log; find /private/var/log -xdev -maxdepth 2 -type f \\( -name '*.gz' -o -name '*.bz2' -o -name '*.[0-9]' \\) -print -delete; du -sh /private/var/log
        """)
    }
}

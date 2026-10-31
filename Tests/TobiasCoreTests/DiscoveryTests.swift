import Foundation
import Testing
@testable import TobiasCore

@Suite struct DiscoveryTests {
    private let installed = [
        InstalledApp(name: "Dia", bundleID: "company.thebrowser.dia"),
        InstalledApp(name: "Brave Browser", bundleID: "com.brave.Browser"),
        InstalledApp(name: "Spotify", bundleID: "com.spotify.client"),
        InstalledApp(name: "IntelliJ IDEA", bundleID: "com.jetbrains.intellij"),
    ]

    private func discover(_ sb: Sandbox, catalog: [Target] = [], fallback: Bool = false) -> [String: Target] {
        let index = AppIndex(apps: installed, bundleFallback: { _ in fallback })
        let found = CacheDiscovery(pathGuard: sb.pathGuard, apps: index).discover(excluding: catalog)
        return Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
    }

    @Test func removedAppIsFlaggedAndInstalledAppIsNot() throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/zen/Profiles/a.bin")
        try sb.makeFile("Library/Caches/com.gone.editor/blob")
        try sb.makeFile("Library/Caches/Dia/blob")
        try sb.makeFile("Library/Caches/com.spotify.client/blob")
        try sb.makeFile("Library/Caches/BraveSoftware/blob")
        try sb.makeFile("Library/Caches/JetBrains/blob")

        let found = discover(sb)
        #expect(found["cache:zen"]?.discovery?.status == .ownerUnknown)
        #expect(found["cache:com.gone.editor"]?.discovery?.status == .appRemoved)
        #expect(found["cache:Dia"]?.discovery?.status == .installed)
        #expect(found["cache:Dia"]?.quitApps == ["company.thebrowser.dia"])
        #expect(found["cache:com.spotify.client"]?.discovery?.status == .installed)
        // Vendor folders match through the app name or the bundle id.
        #expect(found["cache:BraveSoftware"]?.discovery?.status == .installed)
        #expect(found["cache:JetBrains"]?.discovery?.status == .installed)
        #expect(found["cache:JetBrains"]?.quitApps == ["com.jetbrains.intellij"])
    }

    @Test func helperBundleIdBelongsToItsApp() throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/com.spotify.client.helper/blob")
        #expect(discover(sb)["cache:com.spotify.client.helper"]?.discovery?.status == .installed)
    }

    @Test func spotlightFallbackRescuesAnAppInOddLocation() throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/com.odd.place/blob")
        #expect(discover(sb, fallback: false)["cache:com.odd.place"]?.discovery?.status == .appRemoved)
        let rescued = discover(sb, fallback: true)["cache:com.odd.place"]
        #expect(rescued?.discovery?.status == .installed)
        #expect(rescued?.quitApps == ["com.odd.place"])
    }

    @Test func systemHiddenAndCoveredFoldersAreSkipped() throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/com.apple.Safari/blob")
        try sb.makeFile("Library/Caches/CloudKit/blob")
        try sb.makeFile("Library/Caches/.hidden/blob")
        try sb.makeFile("Library/Caches/odd[1]/blob")
        try sb.makeFile("Library/Caches/Homebrew/blob")
        try sb.makeFile("Library/Caches/Keep/blob")
        try sb.makeFile("Library/Caches/loose-file.txt")
        let covered = Target(id: "homebrew", label: "Homebrew", paths: ["~/Library/Caches/Homebrew"], action: .command, command: "brew cleanup")

        let found = discover(sb, catalog: [covered])
        #expect(Set(found.keys) == ["cache:Keep"])
    }

    @Test func foldersInsideACatalogTargetAreCovered() throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/Wide/inner/blob")
        let narrow = Target(id: "n", label: "N", paths: ["~/Library/Caches/Wide/inner"], action: .removeContents)
        #expect(discover(sb, catalog: [narrow]).isEmpty)
    }

    @Test func symlinkedFolderIsSkipped() throws {
        let sb = try Sandbox()
        let real = try sb.makeDir("elsewhere")
        try sb.makeDir("Library/Caches")
        try FileManager.default.createSymbolicLink(atPath: sb.path("Library/Caches/Linked"), withDestinationPath: real)
        #expect(discover(sb).isEmpty)
    }

    @Test func logsFolderIsDiscoveredToo() throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Logs/OldTool/run.log")
        let t = discover(sb)["logs:OldTool"]
        #expect(t?.label == "OldTool logs")
        #expect(t?.action == .removeContents)
    }

    @Test func smallFoldersAreDroppedAfterMeasuring() throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/Big/blob", kilobytes: 2048)
        try sb.makeFile("Library/Caches/Tiny/blob", kilobytes: 4)
        let found = Array(discover(sb).values)
        let sizes = found.map { DiskScanner().measure($0, pathGuard: sb.pathGuard) }
        let kept = CacheDiscovery.keepingLarge(found, sizes: sizes, minBytes: 1_000_000)
        #expect(kept.map(\.id) == ["cache:Big"])
    }

    @Test func discoveredTargetsPassTheGuardAndCleanOnlyContents() async throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/zen/Profiles/a.bin")
        let target = try #require(discover(sb)["cache:zen"])
        let exec = Executor(pathGuard: sb.pathGuard, runner: StubRunner())
        let result = await exec.run(target)
        #expect(result.status == .cleaned)
        #expect(sb.exists("Library/Caches/zen"))
        #expect(!sb.exists("Library/Caches/zen/Profiles"))
        #expect(sb.exists("Library/Caches"))
    }

    @Test func runningOwnerBlocksTheClean() async throws {
        let sb = try Sandbox()
        try sb.makeFile("Library/Caches/Dia/blob")
        let target = try #require(discover(sb)["cache:Dia"])
        let exec = Executor(pathGuard: sb.pathGuard, apps: StubApps(running: ["company.thebrowser.dia"]), runner: StubRunner())
        #expect(await exec.run(target).status == .blocked)
        #expect(sb.exists("Library/Caches/Dia/blob"))
    }

    @Test func appIndexReadsInfoPlists() throws {
        let sb = try Sandbox()
        let contents = try sb.makeDir("Applications/Zed.app/Contents")
        let plist: NSDictionary = ["CFBundleIdentifier": "dev.zed.Zed", "CFBundleName": "Zed"]
        plist.write(toFile: contents + "/Info.plist", atomically: true)
        try sb.makeDir("Applications/Vendor/Nested.app/Contents")

        let apps = AppIndex.scan(directories: [sb.path("Applications")])
        #expect(apps.contains(InstalledApp(name: "Zed", bundleID: "dev.zed.Zed")))
        #expect(apps.contains { $0.name == "Nested" })
    }

    @Test func bundleIdDetection() {
        #expect(CacheDiscovery.looksLikeBundleID("com.spotify.client"))
        #expect(CacheDiscovery.looksLikeBundleID("notion.id"))
        #expect(!CacheDiscovery.looksLikeBundleID("zen"))
        #expect(!CacheDiscovery.looksLikeBundleID("Python 3.13"))
        #expect(!CacheDiscovery.looksLikeBundleID("go1.21"))
    }
}

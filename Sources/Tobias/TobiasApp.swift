import AppKit
import ServiceManagement
import SwiftUI
import TobiasCore

@main
struct TobiasLauncher {
    static func main() async {
        let args = CommandLine.arguments
        if args.contains("--scan") {
            await ScanCLI.run()
            return
        }
        // Used by the `tobias` command line tool.
        if args.contains("--version") {
            print(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
            return
        }
        if args.contains("--login-status") {
            print(SMAppService.mainApp.status == .enabled ? "enabled" : "disabled")
            return
        }
        if args.contains("--unregister-login") {
            try? await SMAppService.mainApp.unregister()
            return
        }
        // Used by scripts/build-app.sh to make AppIcon.icns.
        if let i = args.firstIndex(of: "--write-icon"), i + 1 < args.count {
            let ok = PixelCat.writeAppIconPNG(to: URL(fileURLWithPath: args[i + 1]))
            if !ok { print("Could not write the icon") }
            exit(ok ? 0 : 1)
        }
        await TobiasApp.main()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A packaged app shows AppIcon.icns, which macOS restyles for the tinted and clear icon looks.
        // Only `swift run` (no bundle icon) needs the icon set here.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil {
            NSApp.applicationIconImage = PixelCat.appIcon()
        }
        Task { @MainActor in AppModel.shared.start() }
    }
}

struct TobiasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window(Strings.appName, id: "main") {
            ContentView(model: model)
                .frame(minWidth: 600, minHeight: 640)
        }
        .defaultSize(width: 760, height: 900)

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(nsImage: PixelCat.menuBarImage())
            if let disk = model.disk {
                Text(ByteFormat.whole(disk.availableRaw))
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

/// `Tobias --scan`: read-only table of sizes, handy for checking against du.
enum ScanCLI {
    static func run() async {
        let pathGuard = PathGuard()
        let store = Store()
        guard let catalog = try? Catalog.load(userFile: store.userTargetsURL, pathGuard: pathGuard) else {
            print("Could not load the catalog")
            return
        }
        let found = CacheDiscovery(pathGuard: pathGuard).discover(excluding: catalog.targets)
        let measured = await DiskScanner().scan(catalog.targets + found, pathGuard: pathGuard)
        let kept = Set(CacheDiscovery.keepingLarge(found, sizes: measured).map(\.id))
        let all = catalog.targets + found
        let pairs = zip(all, measured).filter { found.contains($0.0) == false || kept.contains($0.0.id) }
        if let disk = try? DiskSpace.read() {
            print("Free: \(ByteFormat.string(disk.availableRaw)) of \(ByteFormat.string(disk.total))")
        }
        for (target, size) in pairs.sorted(by: { $0.1.bytes > $1.1.bytes }) {
            let flag = size.blocked ? " [blocked]" : (size.exists ? "" : " [not found]")
            let tag = target.discovery.map { " (\($0.status.rawValue))" } ?? ""
            print("\(ByteFormat.string(size.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(target.label)\(tag)\(flag)")
        }
        for r in catalog.rejected { print("rejected \(r.id): \(r.reason)") }
    }
}

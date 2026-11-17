import AppKit
import Observation
import ServiceManagement
import TobiasCore

struct TargetRow: Identifiable, Equatable {
    let target: Target
    var size: TargetSize?

    var id: String { target.id }
    var bytes: Int64 { size?.bytes ?? 0 }
    var isManual: Bool { target.action == .manual }
    var canRunAsRoot: Bool { isManual && target.rootCommand != nil }
    var isBlocked: Bool { size?.blocked ?? false }
    var exists: Bool { size?.exists ?? false }
    var canSelect: Bool { !isManual && !isBlocked && exists && bytes > 0 }

    var group: RowGroup {
        switch target.discovery?.status {
        case nil: return .known
        case .installed: return .appCache
        case .appRemoved, .ownerUnknown: return .leftover
        }
    }
}

enum RowGroup: CaseIterable, Identifiable {
    case known, appCache, leftover
    var id: Self { self }
}

enum CleanPhase: Equatable {
    case idle, confirming, running, done
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var rows: [TargetRow] = []
    var disk: DiskSpace?
    var lastScanDate: Date?
    var isScanning = false
    var selection = Set<String>()
    var phase: CleanPhase = .idle
    var previews: [CleanPreview] = []
    var results: [CleanResult] = []
    var rejected: [RejectedTarget] = []
    var needsRestart: Bool = UserDefaults.standard.bool(forKey: "needsRestart") {
        didSet { UserDefaults.standard.set(needsRestart, forKey: "needsRestart") }
    }
    var launchAtLogin = false
    var statusMessage: String?
    var rootRun: RootRunSession?

    let store = Store()
    private let pathGuard = PathGuard()
    private let scanner = DiskScanner()
    private var executor: Executor
    private var catalogTargets: [Target] = []
    private var targets: [Target] = []
    private let scheduler = ScanScheduler()

    init() {
        executor = Executor(pathGuard: PathGuard(), scanner: DiskScanner(), store: store, apps: WorkspaceApps())
        reloadCatalog()
    }

    // MARK: - Derived

    var selectedRows: [TargetRow] { rows.filter { selection.contains($0.id) } }
    var selectedBytes: Int64 { selectedRows.reduce(0) { $0 + $1.bytes } }
    var reclaimableBytes: Int64 { rows.filter(\.canSelect).reduce(0) { $0 + $1.bytes } }
    var maxRowBytes: Int64 { rows.map(\.bytes).max() ?? 0 }

    func rows(in group: RowGroup) -> [TargetRow] { rows.filter { $0.group == group } }

    // MARK: - Lifecycle

    func start() {
        let state = store.load()
        if let snap = state.lastScan {
            apply(sizes: snap.sizes)
            disk = snap.disk
            lastScanDate = snap.date
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        scheduler.start(every: Self.scanInterval) { [weak self] in
            await self?.scan()
        }
        Task { await scan() }
    }

    func reloadCatalog() {
        let catalog = (try? Catalog.load(userFile: store.userTargetsURL, pathGuard: pathGuard))
            ?? Catalog(targets: [], rejected: [])
        catalogTargets = catalog.targets
        targets = catalog.targets
        rejected = catalog.rejected
        rows = targets.map { TargetRow(target: $0, size: nil) }
    }

    static var scanInterval: TimeInterval {
        let hours = UserDefaults.standard.integer(forKey: "scanIntervalHours")
        return TimeInterval(hours > 0 ? hours : 6) * 3600
    }

    func rescheduleScans() {
        scheduler.start(every: Self.scanInterval) { [weak self] in
            await self?.scan()
        }
    }

    // MARK: - Scan

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        // Discovery lists per-app folders in Library/Caches and Library/Logs that the catalog does not
        // cover. They are measured with everything else and kept only if they are big enough.
        let catalog = catalogTargets
        let pathGuard = self.pathGuard
        let found = await Task.detached { CacheDiscovery(pathGuard: pathGuard).discover(excluding: catalog) }.value
        let measured = await scanner.scan(catalog + found, pathGuard: pathGuard)
        let kept = CacheDiscovery.keepingLarge(found, sizes: measured)
        let keptIDs = Set(catalog.map(\.id) + kept.map(\.id))
        let sizes = measured.filter { keptIDs.contains($0.id) }
        targets = catalog + kept

        let disk = try? DiskSpace.read()
        apply(sizes: sizes)
        if let disk {
            self.disk = disk
            let snapshot = Snapshot(date: Date(), disk: disk, sizes: sizes)
            _ = try? store.record(snapshot: snapshot)
            lastScanDate = snapshot.date
            Notifier.notifyIfLow(disk: disk, reclaimable: reclaimableBytes)
        }
    }

    private func apply(sizes: [TargetSize]) {
        let byID = Dictionary(uniqueKeysWithValues: sizes.map { ($0.id, $0) })
        rows = targets.map { TargetRow(target: $0, size: byID[$0.id]) }
            .sorted { $0.bytes > $1.bytes }
        selection = selection.filter { id in rows.first { $0.id == id }?.canSelect == true }
    }

    // MARK: - Clean flow

    func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// Selects every leftover (removed app or unknown owner) that can be cleaned.
    func selectAll(in group: RowGroup) {
        selection.formUnion(rows(in: group).filter(\.canSelect).map(\.id))
    }

    func beginClean() async {
        let chosen = selectedRows.map(\.target)
        guard !chosen.isEmpty else { return }
        phase = .confirming
        previews = []
        let executor = self.executor
        previews = await Task.detached { chosen.map { executor.preview($0) } }.value
    }

    func refreshPreviews() async {
        let chosen = selectedRows.map(\.target)
        let executor = self.executor
        previews = await Task.detached { chosen.map { executor.preview($0) } }.value
    }

    func confirmClean() async {
        phase = .running
        results = []
        let byID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        for preview in previews where preview.canRun {
            guard let target = byID[preview.id] else { continue }
            results.append(await executor.run(target))
        }
        if results.contains(where: { $0.status == .cleaned && $0.freedBytes > 0 }) {
            needsRestart = true
        }
        phase = .done
        selection = []
        await scan()
    }

    func startRootRun(_ target: Target) {
        guard target.rootCommand != nil, phase == .idle else { return }
        let before = rows.first { $0.id == target.id }?.bytes ?? 0
        rootRun = RootRunSession(target: target) { [weak self] session, code, stopped in
            await self?.finishRootRun(session, code: code, stopped: stopped, before: before)
        }
    }

    func closeRootRun() {
        rootRun?.stop()
        rootRun = nil
    }

    private func finishRootRun(_ session: RootRunSession, code: Int32, stopped: Bool, before: Int64) async {
        // `scan()` returns at once while another scan runs, which would leave stale sizes; wait it out.
        while isScanning { try? await Task.sleep(for: .milliseconds(200)) }
        await scan()
        let after = rows.first { $0.id == session.target.id }?.bytes ?? before
        let freed = max(0, before - after)
        session.freedBytes = freed
        let detail = stopped ? "Stopped" : (code == 0 ? "Ran as administrator: \(session.target.rootCommand ?? "")" : "Exit \(code)")
        store.appendAudit(AuditEntry(
            id: session.target.id,
            status: code == 0 && !stopped ? CleanStatus.cleaned.rawValue : CleanStatus.failed.rawValue,
            freedBytes: freed,
            detail: detail
        ))
        if code == 0 && !stopped && freed > 0 { needsRestart = true }
    }

    func closeSheet() {
        phase = .idle
        previews = []
        results = []
    }

    func quitApp(bundleID: String) async {
        WorkspaceApps.quit(bundleID: bundleID)
        try? await Task.sleep(for: .seconds(2))
        await refreshPreviews()
    }

    // MARK: - Settings

    func setLaunchAtLogin(_ enabled: Bool) {
        Task {
            do {
                if enabled { try SMAppService.mainApp.register() } else { try await SMAppService.mainApp.unregister() }
                statusMessage = nil
            } catch {
                statusMessage = "Could not change login item: \(error.localizedDescription)"
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func revealDataFolder() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(store.directory)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

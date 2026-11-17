import SwiftUI
import TobiasCore

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.l) {
                    FreeSpaceHeader(model: model)
                    if model.needsRestart {
                        RestartBanner { model.needsRestart = false }
                            .padding(.top, Theme.Spacing.s)
                    }
                    TargetList(model: model)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, 28)
            }
            FooterBar(model: model)
        }
        .background(Theme.Palette.ground)
        .foregroundStyle(Theme.Palette.ink)
        .tint(Theme.Palette.accent)
        .sheet(isPresented: Binding(
            get: { model.phase != .idle },
            set: { if !$0 { model.closeSheet() } }
        )) {
            CleanSheet(model: model)
        }
        .sheet(isPresented: Binding(
            get: { model.rootRun != nil },
            set: { if !$0 { model.closeRootRun() } }
        )) {
            if let session = model.rootRun {
                RootRunSheet(model: model, session: session)
            }
        }
    }
}

struct FreeSpaceHeader: View {
    var model: AppModel

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            if let disk = model.disk, model.reclaimableBytes > 0 {
                StickyNote(tint: Theme.Palette.accentTint) {
                    Text("\(Text(Strings.tipLead))\(Text(Strings.tipFigure(ByteFormat.string(disk.availableRaw + model.reclaimableBytes))).foregroundColor(Theme.Palette.accentText)).")
                        .font(Theme.Typography.hand(18))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, Theme.Spacing.s)
            }
            diskCard
        }
    }

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(model.disk.map { ByteFormat.string($0.availableRaw) } ?? "–")
                        .font(Theme.Typography.figure)
                        .monospacedDigit()
                    Text(Strings.free).font(Theme.Typography.hand(22)).foregroundStyle(Theme.Palette.secondaryText)
                }
                Spacer()
                if let disk = model.disk {
                    Text(Strings.ofTotal(ByteFormat.string(disk.total)))
                        .font(Theme.Typography.hand(18))
                        .foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            if let disk = model.disk {
                DiskBar(disk: disk, reclaimable: model.reclaimableBytes)
                legend(disk)
            }
            DashedDivider(color: Theme.Palette.shadow)
            HStack {
                Text(lastScanText).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.tertiaryText)
                Spacer()
                Button {
                    Task { await model.scan() }
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        if model.isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .semibold))
                        }
                        Text(model.isScanning ? Strings.scanning : Strings.scanNow)
                    }
                }
                .buttonStyle(SketchButtonStyle())
                .disabled(model.isScanning)
            }
        }
        .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, Theme.Spacing.l)
        .sketch(.card, lineWidth: 2, shadow: Theme.Palette.shadow, shadowOffset: CGSize(width: 3, height: 4))
    }

    private func legend(_ disk: DiskSpace) -> some View {
        let reclaimable = model.reclaimableBytes
        return HStack(spacing: 28) {
            LegendItem(label: Strings.legend(Strings.used, ByteFormat.string(DiskBar.usedOnly(disk, reclaimable)))) {
                Theme.Palette.used
            }
            LegendItem(label: Strings.legend(Strings.reclaimable, ByteFormat.string(reclaimable))) {
                Stripes(width: 3)
            }
            LegendItem(label: Strings.legend(Strings.freeLegend, ByteFormat.string(disk.availableRaw))) {
                Theme.Palette.paper
            }
        }
        .font(Theme.Typography.body)
        .foregroundStyle(Theme.Palette.line)
    }

    private var lastScanText: String {
        guard let date = model.lastScanDate else { return Strings.neverScanned }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return Strings.lastScan(f.localizedString(for: date, relativeTo: Date()))
    }
}

/// Disk usage in three parts: used, reclaimable (striped) and free.
struct DiskBar: View {
    let disk: DiskSpace
    let reclaimable: Int64

    static func usedOnly(_ disk: DiskSpace, _ reclaimable: Int64) -> Int64 {
        max(0, disk.used - reclaimable)
    }

    var body: some View {
        let total = Double(max(disk.total, 1))
        let used = Double(Self.usedOnly(disk, reclaimable)) / total
        let extra = Double(min(reclaimable, disk.used)) / total
        GeometryReader { geo in
            HStack(spacing: 0) {
                Theme.Palette.used
                    .frame(width: geo.size.width * used)
                    .overlay(alignment: .trailing) { Theme.Palette.line.frame(width: 2) }
                if extra > 0 {
                    Stripes()
                        .frame(width: geo.size.width * extra)
                        .overlay(alignment: .trailing) {
                            Path { p in
                                p.move(to: .zero)
                                p.addLine(to: CGPoint(x: 0, y: geo.size.height))
                            }
                            .stroke(Theme.Palette.line, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                            .frame(width: 2)
                        }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: 28)
        .background(Theme.Palette.paper)
        .clipShape(SketchShape.control)
        .overlay { SketchShape.control.strokeBorder(Theme.Palette.line, lineWidth: 2) }
        .accessibilityElement()
        .accessibilityLabel(
            "Disk: \(ByteFormat.string(Self.usedOnly(disk, reclaimable))) used, "
            + "\(ByteFormat.string(reclaimable)) reclaimable, \(ByteFormat.string(disk.availableRaw)) free"
        )
    }
}

private struct LegendItem<Swatch: View>: View {
    let label: String
    @ViewBuilder var swatch: Swatch

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            swatch
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.Palette.line, lineWidth: 2) }
            Text(label).monospacedDigit()
        }
    }
}

struct TargetList: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(RowGroup.allCases) { group in
                let rows = model.rows(in: group)
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        GroupHeader(model: model, group: group)
                        ForEach(rows) { row in
                            TargetRowView(model: model, row: row)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sketch(.card, lineWidth: 2, shadow: Theme.Palette.shadow, shadowOffset: CGSize(width: 3, height: 4))
    }
}

struct GroupHeader: View {
    var model: AppModel
    let group: RowGroup

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.Palette.line)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if group == .leftover {
                Button(Strings.selectAll) { model.selectAll(in: group) }
                    .buttonStyle(.plain)
                    .font(Theme.Typography.hand(17))
                    .underline(pattern: .solid)
                    .foregroundStyle(Theme.Palette.accentText)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var title: String {
        switch group {
        case .known: return Strings.groupKnown
        case .appCache: return Strings.groupAppCaches
        case .leftover: return Strings.groupLeftovers
        }
    }
}

struct RestartBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        StickyNote(onDismiss: onDismiss) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.restartTitle).font(Theme.Typography.rowTitle)
                Text(Strings.restartBody)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.noteText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FooterBar: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Group {
                if model.selection.isEmpty {
                    Text(Strings.nothingSelected)
                } else {
                    Text("\(Text("\(Strings.selected(model.selection.count)) · "))\(Text(ByteFormat.string(model.selectedBytes)).font(Theme.Typography.mono(15)).foregroundColor(Theme.Palette.ink))")
                }
            }
            .font(Theme.Typography.button)
            .foregroundStyle(Theme.Palette.secondaryText)
            Spacer()
            Button(Strings.cleanSelected) {
                Task { await model.beginClean() }
            }
            .buttonStyle(SketchButtonStyle(kind: .primary, height: 46))
            .keyboardShortcut(.defaultAction)
            .disabled(model.selection.isEmpty || model.isScanning)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, 18).padding(.bottom, 22)
        .background(Theme.Palette.chrome)
        .overlay(alignment: .top) { DashedDivider(lineWidth: 2) }
    }
}

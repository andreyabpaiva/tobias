import SwiftUI
import TobiasCore

struct TargetRowView: View {
    var model: AppModel
    let row: TargetRow
    @State private var showManual = false

    init(model: AppModel, row: TargetRow) {
        self.model = model
        self.row = row
    }

    private var isSelected: Bool { model.selection.contains(row.id) }
    private var isScanned: Bool { row.size != nil }
    /// Not found or empty: drawn faded with a dashed outline.
    private var isDimmed: Bool { isScanned && !row.isManual && !row.isBlocked && (!row.exists || row.bytes == 0) }
    private var showsBar: Bool { isScanned && !isDimmed && !row.isBlocked }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            leading
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(row.target.label)
                        .font(Theme.Typography.rowTitle)
                        .foregroundStyle(isDimmed ? Theme.Palette.tertiaryText : Theme.Palette.ink)
                    if row.isBlocked { SketchBadge(text: Strings.blocked, tone: .warning) }
                    if row.isManual { SketchBadge(text: Strings.manual) }
                    if row.target.risk == .redownloads { SketchBadge(text: Strings.redownloads, tone: .warning) }
                    OwnerBadge(status: row.target.discovery?.status)
                    Spacer(minLength: Theme.Spacing.s)
                    Text(sizeText)
                        .font(Theme.Typography.rowSize)
                        .monospacedDigit()
                        .foregroundStyle(showsBar ? Theme.Palette.ink : Theme.Palette.tertiaryText)
                }
                if showsBar {
                    SizeBar(fraction: fraction, highlighted: isSelected)
                }
                Text(detail)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .sketch(
            .row,
            fill: isDimmed ? Theme.Palette.ground : (isSelected ? Theme.Palette.selectedRow : Theme.Palette.surface),
            border: isDimmed ? Theme.Palette.barFill : Theme.Palette.line,
            dashed: isDimmed,
            shadow: isDimmed ? nil : (isSelected ? Theme.Palette.selectedShadow : Theme.Palette.shadowSoft)
        )
        .contentShape(Rectangle())
        .onTapGesture { if row.canSelect { model.toggle(row.id) } }
    }

    @ViewBuilder private var leading: some View {
        if row.isManual {
            Button { showManual = true } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .sketch(.tiny, fill: Theme.Palette.paper)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Palette.line)
            .padding(.horizontal, -5).padding(.top, -3)
            .help(Strings.manualHint)
            .accessibilityLabel(Strings.showCommand(row.target.label))
            .popover(isPresented: $showManual, arrowEdge: .bottom) { ManualPopover(model: model, target: row.target) }
        } else if row.isBlocked {
            Image(systemName: "lock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.Palette.warning)
                .frame(width: 18, height: 18)
                .padding(.top, 2)
                .help(Strings.blockedHint)
        } else {
            Toggle(row.target.label, isOn: Binding(get: { isSelected }, set: { _ in model.toggle(row.id) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!row.canSelect)
                .padding(.top, 3)
        }
    }

    private var fraction: Double {
        let max = model.maxRowBytes
        return max > 0 ? Double(row.bytes) / Double(max) : 0
    }

    private var sizeText: String {
        guard isScanned, row.exists, !row.isBlocked else { return "—" }
        return ByteFormat.string(row.bytes)
    }

    private var detail: String {
        if row.isBlocked { return Strings.blockedHint }
        if row.isManual { return Strings.manualHint }
        if !isScanned { return row.target.note }
        if !row.exists { return Strings.notFound }
        if row.bytes == 0 { return Strings.empty }
        return row.target.note
    }
}

/// Thin outlined bar, filled in proportion to the largest row. Green when the row is selected.
struct SizeBar: View {
    let fraction: Double
    var highlighted = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 3)
                .fill(highlighted ? Theme.Palette.accent : Theme.Palette.barFill)
                .frame(width: max(3, geo.size.width * fraction))
        }
        .frame(height: 10)
        .background(Theme.Palette.barTrack)
        .clipShape(SketchShape.bar)
        .overlay { SketchShape.bar.strokeBorder(Theme.Palette.line, lineWidth: 1.5) }
        .accessibilityHidden(true)
    }
}

struct OwnerBadge: View {
    let status: OwnerStatus?

    var body: some View {
        switch status {
        case .appRemoved:
            SketchBadge(text: Strings.appRemoved)
        case .ownerUnknown:
            SketchBadge(text: Strings.ownerUnknown)
        case .installed, nil:
            EmptyView()
        }
    }
}

struct ManualPopover: View {
    var model: AppModel
    let target: Target
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(target.label).font(Theme.Typography.hand(24))
            Text(target.note)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(target.manualCommand ?? "")
                .font(Theme.Typography.mono(13))
                .lineSpacing(3)
                .foregroundStyle(Color(nsColor: NSColor(hex: 0xF0EFEA)))
                .textSelection(.enabled)
                .padding(.horizontal, Theme.Spacing.m).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: NSColor(hex: 0x2B2B29)), in: SketchShape.control)
            HStack(spacing: 12) {
                Button {
                    model.copy(target.manualCommand ?? "")
                    copied = true
                } label: {
                    Label(copied ? Strings.copied : Strings.copy, systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SketchButtonStyle(fill: copied ? Theme.Palette.accentTint : nil))
                Text(Strings.manualShort).font(Theme.Typography.badge).foregroundStyle(Theme.Palette.tertiaryText)
            }
        }
        .foregroundStyle(Theme.Palette.ink)
        .padding(Theme.Spacing.l)
        .frame(width: 420)
        .background(Theme.Palette.paper)
    }
}

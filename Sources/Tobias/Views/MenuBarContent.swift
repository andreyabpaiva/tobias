import SwiftUI
import TobiasCore

struct MenuBarContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 14) {
                PixelCatView()
                    .frame(width: 40, height: 38)
                    .frame(width: 56, height: 56)
                    .sketch(.row, shadow: Theme.Palette.shadowSoft)
                VStack(alignment: .leading, spacing: 6) {
                    Text(Strings.appName).font(Theme.Typography.hand(24))
                    Text(lastScanText).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.secondaryText)
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, Theme.Spacing.m)

            HStack(spacing: Theme.Spacing.s) {
                stat(Strings.freeSpace, model.disk.map { ByteFormat.string($0.availableRaw) } ?? "–", color: Theme.Palette.ink)
                stat(Strings.reclaimable, ByteFormat.string(model.reclaimableBytes), color: Theme.Palette.accent)
            }
            .padding(.horizontal, 6).padding(.bottom, 10)

            MenuItem(title: model.isScanning ? Strings.scanning : Strings.scanNow, systemImage: "arrow.clockwise", highlighted: true) {
                Task { await model.scan() }
            }
            .disabled(model.isScanning)
            MenuItem(title: Strings.openTobias, systemImage: "macwindow") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
                dismiss()
            }
            DashedDivider().padding(.horizontal, 10).padding(.vertical, 6)
            MenuItem(title: Strings.quit, systemImage: "power", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(10)
        .frame(width: 340)
        .background(Theme.Palette.paper)
        .foregroundStyle(Theme.Palette.ink)
    }

    private func stat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(label).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.secondaryText)
            Text(value).font(Theme.Typography.mono(17, weight: .medium)).monospacedDigit().foregroundStyle(color)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sketch(.row)
    }

    private var lastScanText: String {
        guard let date = model.lastScanDate else { return Strings.neverScanned }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return Strings.lastScan(f.localizedString(for: date, relativeTo: Date()))
    }
}

private struct MenuItem: View {
    let title: String
    let systemImage: String
    var highlighted = false
    var shortcut: String?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).font(.system(size: 13, weight: .medium)).frame(width: 16)
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                if let shortcut {
                    Text(shortcut).font(Theme.Typography.monoCaption).foregroundStyle(Theme.Palette.tertiaryText)
                }
            }
            .font(Theme.Typography.button)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
            .background {
                if highlighted || hovering {
                    SketchShape.control.fill(Theme.Palette.chrome)
                    SketchShape.control.strokeBorder(Theme.Palette.line, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }
}

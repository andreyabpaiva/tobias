import SwiftUI
import TobiasCore

struct CleanSheet: View {
    var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch model.phase {
            case .confirming: confirming
            case .running: running
            case .done: done
            case .idle: EmptyView()
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 560, height: 640)
        .background(Theme.Palette.paper)
        .foregroundStyle(Theme.Palette.ink)
        .tint(Theme.Palette.accent)
    }

    // MARK: - Confirm

    private var confirming: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(Strings.confirmTitle).font(Theme.Typography.title)
                Text(Strings.confirmBody).font(Theme.Typography.hand(18)).foregroundStyle(Theme.Palette.secondaryText)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if model.previews.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                    ForEach(model.previews, id: \.id) { PreviewCard(model: model, preview: $0) }
                }
                .padding(.leading, 2).padding(.trailing, 6).padding(.top, 4).padding(.bottom, Theme.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 12) {
                Spacer()
                Button(Strings.cancel) { model.closeSheet() }
                    .buttonStyle(SketchButtonStyle(height: 46))
                    .keyboardShortcut(.cancelAction)
                Button(deleteLabel, role: .destructive) {
                    Task { await model.confirmClean() }
                }
                .buttonStyle(SketchButtonStyle(kind: .destructive, height: 46))
                .keyboardShortcut(.defaultAction)
                .disabled(runnable.isEmpty)
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }

    private var runnable: [CleanPreview] { model.previews.filter(\.canRun) }

    private var deleteLabel: String {
        let bytes = runnable.reduce(Int64(0)) { $0 + $1.totalBytes }
        return "\(Strings.deleteButton) \(ByteFormat.string(bytes))"
    }

    // MARK: - Running

    private var running: some View {
        VStack(spacing: 28) {
            Spacer()
            CleaningSpinner().frame(width: 168, height: 168)
            Text(Strings.running).font(Theme.Typography.hand(30))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Done

    private var done: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Strings.resultsTitle).font(Theme.Typography.title)
                Text(Strings.freed(ByteFormat.string(model.results.reduce(Int64(0)) { $0 + $1.freedBytes })))
                    .font(Theme.Typography.figure)
                    .foregroundStyle(Theme.Palette.accentText)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.results, id: \.id) { ResultRow(result: $0, label: label(for: $0.id)) }
                }
                .padding(.leading, 2).padding(.trailing, 6).padding(.top, 2).padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.needsRestart {
                RestartBanner { model.needsRestart = false }
                    .padding(.leading, 10).padding(.top, 10)
            }
            HStack {
                Spacer()
                Button(Strings.close) { model.closeSheet() }
                    .buttonStyle(SketchButtonStyle(kind: .primary, height: 46))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func label(for id: String) -> String {
        model.rows.first { $0.id == id }?.target.label ?? id
    }
}

struct ResultRow: View {
    let result: CleanResult
    let label: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .padding(.top, 2)
                .accessibilityLabel(statusName)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.Typography.rowTitle)
                Text(result.detail)
                    .font(Theme.Typography.hand(15))
                    .foregroundStyle(isFailure ? Theme.Palette.destructiveText : Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Spacing.s)
            if result.freedBytes > 0 {
                Text(ByteFormat.string(result.freedBytes))
                    .font(Theme.Typography.rowSize)
                    .monospacedDigit()
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(.horizontal, Theme.Spacing.m).padding(.vertical, 12)
        .sketch(.row, border: isFailure ? Theme.Palette.destructive : Theme.Palette.line, dashed: isFailure)
    }

    private var isFailure: Bool { result.status == .failed }

    private var icon: String {
        switch result.status {
        case .cleaned: return "checkmark.circle"
        case .nothingToDo: return "minus.circle"
        case .blocked: return "hand.raised"
        case .manual: return "terminal"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var color: Color {
        switch result.status {
        case .cleaned: return Theme.Palette.success
        case .failed: return Theme.Palette.destructive
        case .blocked: return Theme.Palette.warning
        default: return Theme.Palette.tertiaryText
        }
    }

    private var statusName: String {
        switch result.status {
        case .cleaned: return "Cleaned"
        case .nothingToDo: return Strings.empty
        case .blocked: return Strings.blocked
        case .manual: return Strings.manual
        case .failed: return "Failed"
        }
    }
}

/// Tobias in the middle of a dashed ring with a green arc that turns while cleaning.
struct CleaningSpinner: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .inset(by: 8)
                    .stroke(Theme.Palette.shadow, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 9]))
                Circle()
                    .inset(by: 8)
                    .trim(from: 0, to: 0.25)
                    .stroke(Theme.Palette.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 2.4).repeatForever(autoreverses: false), value: turning)
            PixelCatView().frame(width: 96, height: 90)
        }
        .onAppear { turning = true }
    }
}

struct PreviewCard: View {
    var model: AppModel
    let preview: CleanPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(preview.label).font(Theme.Typography.hand(21))
                Spacer()
                Text(ByteFormat.string(preview.totalBytes)).font(Theme.Typography.mono(15)).monospacedDigit()
            }
            if preview.risk == .redownloads {
                Label(Strings.redownloadWarning, systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.warningText)
            }
            if let command = preview.command {
                Text("$ \(command)").font(Theme.Typography.monoCaption).foregroundStyle(Theme.Palette.secondaryText)
            }
            ForEach(preview.items, id: \.path) { item in
                HStack(spacing: 12) {
                    Text(displayPath(item.path)).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(ByteFormat.string(item.bytes)).monospacedDigit()
                }
                .font(Theme.Typography.monoCaption)
                .foregroundStyle(Theme.Palette.secondaryText)
            }
            if let reason = preview.rejection {
                Label("\(Strings.rejected): \(reason)", systemImage: "xmark.octagon")
                    .font(Theme.Typography.caption).foregroundStyle(Theme.Palette.destructive)
            }
            if !preview.runningApps.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised").foregroundStyle(Theme.Palette.warning)
                    Text(Strings.quitFirst(preview.runningApps.joined(separator: ", ")))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.warningText)
                    Spacer(minLength: 0)
                    Button(Strings.quitApp) {
                        Task { for id in preview.runningApps { await model.quitApp(bundleID: id) } }
                    }
                    .buttonStyle(SketchButtonStyle(height: 36))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background {
                    SketchShape.note.fill(Theme.Palette.note)
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 4)
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, Theme.Spacing.m)
        .sketch(
            .row,
            border: preview.rejection == nil ? Theme.Palette.line : Theme.Palette.destructive,
            dashed: preview.rejection != nil,
            shadow: preview.rejection == nil ? Theme.Palette.shadowSoft : nil
        )
    }

    private func displayPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}

import SwiftUI
import TobiasCore

/// Runs a target's root command in a small terminal: ▶︎ Run, type the password when sudo asks, watch the output.
struct RootRunSheet: View {
    var model: AppModel
    var session: RootRunSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(session.target.label).font(Theme.Typography.title)
                Text(session.target.note)
                    .font(Theme.Typography.hand(18))
                    .foregroundStyle(Theme.Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Label(Strings.runsAsAdmin, systemImage: "lock.shield")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.warningText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TerminalPanel(session: session)
            footer
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 560, height: 600)
        .background(Theme.Palette.paper)
        .foregroundStyle(Theme.Palette.ink)
        .tint(Theme.Palette.accent)
        .interactiveDismissDisabled(session.phase.isActive)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            result
            Spacer()
            switch session.phase {
            case .ready:
                Button(Strings.close) { model.closeRootRun() }
                    .buttonStyle(SketchButtonStyle(height: 46))
                    .keyboardShortcut(.cancelAction)
                Button { model.copy(session.commandLine) } label: {
                    Label(Strings.copy, systemImage: "doc.on.doc")
                }
                .buttonStyle(SketchButtonStyle(height: 46))
                Button { session.start() } label: {
                    Label(Strings.run, systemImage: "play.fill")
                }
                .buttonStyle(SketchButtonStyle(kind: .primary, height: 46))
                .keyboardShortcut(.defaultAction)
            case .running, .needsPassword:
                Button { session.stop() } label: {
                    Label(Strings.stop, systemImage: "stop.fill")
                }
                .buttonStyle(SketchButtonStyle(height: 46))
            case .succeeded, .failed, .stopped:
                Button(Strings.close) { model.closeRootRun() }
                    .buttonStyle(SketchButtonStyle(kind: .primary, height: 46))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder private var result: some View {
        switch session.phase {
        case .succeeded:
            Label(Strings.rootDone(session.freedBytes.map(ByteFormat.string)), systemImage: "checkmark.circle")
                .font(Theme.Typography.button)
                .foregroundStyle(Theme.Palette.success)
        case .failed(let code):
            Label(Strings.rootFailed(code), systemImage: "exclamationmark.triangle")
                .font(Theme.Typography.button)
                .foregroundStyle(Theme.Palette.destructive)
        case .stopped:
            Label(Strings.rootStopped, systemImage: "stop.circle")
                .font(Theme.Typography.button)
                .foregroundStyle(Theme.Palette.tertiaryText)
        case .running:
            ProgressView().controlSize(.small)
        case .ready, .needsPassword:
            EmptyView()
        }
    }
}

private struct TerminalPanel: View {
    var session: RootRunSession
    @State private var password = ""
    @FocusState private var passwordFocused: Bool

    private let text = Color(nsColor: NSColor(hex: 0xF0EFEA))
    private let dim = Color(nsColor: NSColor(hex: 0x9C9A92))

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if session.phase == .ready {
                        Text("$ \(session.commandLine)").foregroundStyle(text)
                        Text(Strings.pressRun).foregroundStyle(dim)
                    } else {
                        Text(session.transcript).foregroundStyle(text)
                    }
                    if session.phase == .needsPassword {
                        HStack(spacing: 6) {
                            Text(Strings.passwordPrompt).foregroundStyle(text)
                            SecureField(Strings.passwordField, text: $password)
                                .labelsHidden()
                                .textFieldStyle(.plain)
                                .foregroundStyle(text)
                                .focused($passwordFocused)
                                .onSubmit(submit)
                                .accessibilityLabel(Strings.passwordField)
                        }
                        .onAppear { passwordFocused = true }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .font(Theme.Typography.mono(13))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.m).padding(.vertical, 14)
            }
            .onChange(of: session.transcript) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: session.phase) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: NSColor(hex: 0x2B2B29)), in: SketchShape.control)
        .environment(\.colorScheme, .dark)
    }

    private func submit() {
        guard !password.isEmpty else { return }
        session.submit(password: password)
        password = ""
    }
}

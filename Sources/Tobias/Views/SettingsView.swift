import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @AppStorage("scanIntervalHours") private var hours = 6
    @AppStorage("notifyLowSpace") private var notify = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            VStack(spacing: 0) {
                SettingRow {
                    Text(Strings.scanEvery)
                    Spacer()
                    Picker(Strings.scanEvery, selection: $hours) {
                        ForEach([1, 3, 6, 12, 24], id: \.self) { Text(Strings.hours($0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: hours) { _, _ in model.rescheduleScans() }
                }
                DashedDivider(color: Theme.Palette.shadowSoft)
                SettingRow {
                    Text(Strings.launchAtLogin)
                    Spacer()
                    Toggle(Strings.launchAtLogin, isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                }
                DashedDivider(color: Theme.Palette.shadowSoft)
                SettingRow {
                    Text(Strings.lowSpaceAlert)
                    Spacer()
                    Toggle(Strings.lowSpaceAlert, isOn: $notify).labelsHidden()
                }
            }
            .sketch(.row, shadow: Theme.Palette.shadowSoft)

            if let message = model.statusMessage {
                Text(message)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.destructive)
                    .padding(.horizontal, 6)
            }
            Button { model.revealDataFolder() } label: {
                Label(Strings.showData, systemImage: "folder")
            }
            .buttonStyle(SketchButtonStyle())
        }
        .toggleStyle(.switch)
        .padding(Theme.Spacing.l)
        .frame(width: 460)
        .background(Theme.Palette.ground)
        .foregroundStyle(Theme.Palette.ink)
        .tint(Theme.Palette.accent)
    }
}

private struct SettingRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Theme.Spacing.m) { content }
            .font(Theme.Typography.button)
            .padding(.horizontal, 18).padding(.vertical, Theme.Spacing.s)
            .frame(minHeight: 60)
    }
}

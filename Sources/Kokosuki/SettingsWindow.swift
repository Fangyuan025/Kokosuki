import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var onResetStats: () -> Void
    @State private var confirmingReset = false

    private let cocoa = Color(red: 0.36, green: 0.27, blue: 0.21)

    /// One symmetric row: label on the left, control right-aligned.
    private func settingRow<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .foregroundStyle(cocoa)
                .font(.system(size: 12.5))
                .lineLimit(2)
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: 34)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("settings.title"))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(cocoa)
                .padding(.bottom, 14)

            settingRow(L10n.t("settings.language")) {
                Picker("", selection: $settings.lang) {
                    ForEach(Lang.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            settingRow(L10n.t("settings.size")) {
                Picker("", selection: $settings.petScale) {
                    Text(L10n.t("settings.size.small")).tag(0.8)
                    Text(L10n.t("settings.size.medium")).tag(1.0)
                    Text(L10n.t("settings.size.large")).tag(1.3)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 190)
            }
            settingRow(L10n.t("settings.chatter")) {
                Toggle("", isOn: $settings.chatterEnabled).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
            }
            if settings.chatterEnabled {
                settingRow(L10n.t("settings.chatterFreq")) {
                    Picker("", selection: $settings.chatterFreq) {
                        Text(L10n.t("settings.freq.low")).tag(12.0)
                        Text(L10n.t("settings.freq.mid")).tag(6.0)
                        Text(L10n.t("settings.freq.high")).tag(3.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
            settingRow(L10n.t("settings.autoSleep")) {
                Toggle("", isOn: $settings.autoSleep).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
            }
            settingRow(L10n.t("settings.parkour")) {
                Toggle("", isOn: $settings.windowParkour).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
            }
            settingRow(L10n.t("settings.thinking")) {
                Toggle("", isOn: $settings.thinkingEnabled).labelsHidden()
                    .toggleStyle(.switch).controlSize(.small)
            }

            Divider().padding(.vertical, 10)

            HStack {
                if confirmingReset {
                    Button(role: .destructive) {
                        onResetStats()
                        confirmingReset = false
                    } label: {
                        Text(L10n.t("settings.resetStats") + " ✓")
                    }
                    .controlSize(.small)
                } else {
                    Button { confirmingReset = true } label: {
                        Text(L10n.t("settings.resetStats"))
                    }
                    .controlSize(.small)
                }
                Spacer()
            }

            Text(L10n.t("settings.about"))
                .font(.system(size: 10.5))
                .foregroundStyle(cocoa.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .padding(.top, 30)      // clear the overlaid titlebar close button
        .frame(width: 330)
        .background(Color(red: 1.0, green: 0.975, blue: 0.94))
    }
}

@MainActor
final class SettingsWindowController {
    let panel: NSPanel
    private var hosting: NSHostingView<SettingsView>?
    private let onResetStats: () -> Void

    init(onResetStats: @escaping () -> Void) {
        self.onResetStats = onResetStats
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 340),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered, defer: false)
        panel.appearance = NSAppearance(named: .aqua)  // light-designed UI
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor(calibratedRed: 1.0, green: 0.975, blue: 0.94, alpha: 1)
        rebuild()
    }

    func rebuild() {
        let view = SettingsView(settings: AppSettings.shared, onResetStats: onResetStats)
        if let hosting {
            hosting.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            panel.contentView = host
            hosting = host
        }
        panel.setContentSize(hosting!.fittingSize)
    }

    func show() {
        rebuild()
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}

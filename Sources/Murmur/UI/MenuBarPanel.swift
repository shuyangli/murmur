import SwiftUI

/// The dropdown shown when the menu bar icon is clicked: current status, the
/// last few dictations, and the way into the rest of the app.
struct MenuBarPanel: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private static let recentCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            setupWarnings
            recentSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                MenuBarIcon(state: controller.state)
                Text(statusTitle).font(.headline)
                Spacer()
            }

            Text(statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if controller.enginePreparation.isBusy {
                preparationProgress
            }
        }
    }

    @ViewBuilder
    private var preparationProgress: some View {
        if case .downloading(let fraction, let detail) = controller.enginePreparation {
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: fraction)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var statusTitle: String {
        switch controller.state {
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .notice(let message): return message
        case .failure: return "Something went wrong"
        case .idle: return "Murmur"
        }
    }

    private var statusDetail: String {
        if case .failure(let message) = controller.state { return message }
        if !controller.enginePreparation.isReady {
            return controller.enginePreparation.describedForMenu
        }
        return "Hold \(preferences.triggerKey.label) to dictate."
    }

    @ViewBuilder
    private var setupWarnings: some View {
        if !controller.hotkeyActive {
            WarningRow(
                text: "Input Monitoring is off, so the trigger key cannot be seen.",
                actionTitle: "Open Settings",
                action: { Permissions.open(.inputMonitoring) }
            )
        }
        if !Permissions.accessibilityGranted, preferences.outputMode == .pasteIntoFocusedApp {
            WarningRow(
                text: "Accessibility is off, so text will be copied instead of pasted.",
                actionTitle: "Open Settings",
                action: { Permissions.promptForAccessibility() }
            )
        }
        if Permissions.globeKeyConflicts {
            WarningRow(
                text: "macOS still runs “\(Permissions.globeKeyAction.label)” on the Globe key.",
                actionTitle: "Open Keyboard Settings",
                action: { Permissions.openKeyboardSettings() }
            )
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(controller.history.entries.prefix(Self.recentCount))
        if recent.isEmpty {
            Text("No dictations yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(recent) { entry in
                    Button {
                        TextInjector.copy(entry.text)
                    } label: {
                        Text(entry.text)
                            .lineLimit(2)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .help("Copy to clipboard")
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            PanelButton(title: "Dictation History…", shortcut: nil) {
                activateApp()
                openWindow(id: WindowID.history)
            }
            PanelButton(title: "Settings…", shortcut: "⌘,") {
                activateApp()
                openSettings()
            }
            PanelButton(title: "Quit Murmur", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// An accessory app has to raise itself explicitly before a window it
    /// opens will come to the front.
    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct PanelButton: View {
    let title: String
    let shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct WarningRow: View {
    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

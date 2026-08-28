import SwiftUI

struct SettingsWindow: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ModelSettingsTab()
                .tabItem { Label("Model", systemImage: "waveform") }
            PermissionsSettingsTab()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 500)
        .padding(.vertical, 8)
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Picker("Hold to dictate:", selection: Binding(
                    get: { preferences.triggerKey },
                    set: { newValue in
                        preferences.triggerKey = newValue
                        controller.restartHotkeyMonitor()
                    }
                )) {
                    ForEach(TriggerKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }

                if Permissions.globeKeyConflicts {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("macOS runs “\(Permissions.globeKeyAction.label)” when the Globe key is pressed, which will fire alongside dictation.")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                                .buttonStyle(.link).font(.caption)
                            Text("Set “Press 🌐 key to” to “Do Nothing”.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Trigger")
            }

            Section {
                Picker("When finished:", selection: Binding(
                    get: { preferences.outputMode },
                    set: { preferences.outputMode = $0 }
                )) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Toggle("Restore my previous clipboard afterwards", isOn: Binding(
                    get: { preferences.restoreClipboard },
                    set: { preferences.restoreClipboard = $0 }
                ))
                .disabled(preferences.outputMode != .pasteIntoFocusedApp)

                Toggle("Trim surrounding whitespace", isOn: Binding(
                    get: { preferences.trimTrailingWhitespace },
                    set: { preferences.trimTrailingWhitespace = $0 }
                ))

                Toggle("Play a sound when recording starts and stops", isOn: Binding(
                    get: { preferences.playFeedbackSounds },
                    set: { preferences.playFeedbackSounds = $0 }
                ))
            } header: {
                Text("Output")
            }

            Section {
                Stepper(
                    "Keep the last \(preferences.historyLimit) dictations",
                    value: Binding(
                        get: { preferences.historyLimit },
                        set: { newValue in
                            preferences.historyLimit = newValue
                            controller.history.applyLimit()
                        }
                    ),
                    in: Preferences.historyLimitRange,
                    step: 10
                )
                Text("History lives in a plain JSON file in Application Support and can be deleted at any time.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelSettingsTab: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences

    /// Languages Nemotron ships a vocabulary-pruned build for, plus auto.
    private static let languages: [(code: String, name: String)] = [
        ("auto", "Detect automatically"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("es-ES", "Spanish"),
        ("fr-FR", "French"),
        ("de-DE", "German"),
        ("it-IT", "Italian"),
        ("pt-BR", "Portuguese"),
        ("zh-CN", "Chinese"),
        ("ja-JP", "Japanese"),
    ]

    var body: some View {
        Form {
            Section {
                Picker("Engine:", selection: Binding(
                    get: { preferences.engineID },
                    set: { newValue in
                        preferences.engineID = newValue
                        Task { await controller.reloadEngine() }
                    }
                )) {
                    ForEach(EngineRegistry.all) { descriptor in
                        Text(descriptor.name).tag(descriptor.id)
                    }
                }

                let descriptor = EngineRegistry.descriptor(for: preferences.engineID)
                Text(descriptor.summary)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Download size:", value: descriptor.approximateDownload)
                    .font(.caption)

                Picker("Language:", selection: Binding(
                    get: { preferences.language },
                    set: { newValue in
                        preferences.language = newValue
                        Task { await controller.reloadEngine() }
                    }
                )) {
                    ForEach(Self.languages, id: \.code) { entry in
                        Text(entry.name).tag(entry.code)
                    }
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text("Everything runs on this Mac. Models download once, then nothing leaves the device.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Status:", value: controller.enginePreparation.describedForMenu)
                if case .downloading(let fraction, _) = controller.enginePreparation {
                    ProgressView(value: fraction)
                }
                Button("Reload Model") {
                    Task { await controller.reloadEngine() }
                }
                .disabled(controller.enginePreparation.isBusy)
            } header: {
                Text("Model State")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsSettingsTab: View {
    @EnvironmentObject private var controller: DictationController

    /// Permission state is read fresh on a timer because macOS gives no
    /// notification when the user flips a switch in System Settings.
    @State private var refreshTick = 0
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Input Monitoring",
                    detail: "Lets Murmur notice the trigger key while you are in another app.",
                    granted: Permissions.inputMonitoringGranted,
                    action: {
                        Permissions.promptForInputMonitoring()
                        Permissions.open(.inputMonitoring)
                    }
                )
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lets Murmur paste the transcript into the app you were typing in.",
                    granted: Permissions.accessibilityGranted,
                    action: {
                        Permissions.promptForAccessibility()
                        Permissions.open(.accessibility)
                    }
                )
                PermissionRow(
                    title: "Microphone",
                    detail: "Lets Murmur hear you. Audio is never written to disk or sent anywhere.",
                    granted: Permissions.microphoneGranted,
                    action: { Permissions.open(.microphone) }
                )
            } header: {
                Text("Required")
            } footer: {
                Text("After granting Input Monitoring, quit and reopen Murmur so the change takes effect.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button("Restart Key Monitoring") { controller.restartHotkeyMonitor() }
                LabeledContent(
                    "Trigger key:",
                    value: controller.hotkeyActive ? "Being watched" : "Not being watched"
                )
            } header: {
                Text("Troubleshooting")
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in refreshTick &+= 1 }
        .id(refreshTick)
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !granted {
                Button("Grant", action: action)
            }
        }
        .padding(.vertical, 2)
    }
}

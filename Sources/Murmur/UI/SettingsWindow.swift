import SwiftUI

struct SettingsWindow: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ModelSettingsTab()
                .tabItem { Label("Model", systemImage: "waveform") }
            TextSettingsTab()
                .tabItem { Label("Text", systemImage: "text.badge.checkmark") }
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
                Toggle("Open Murmur at login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.setEnabled($0) }
                ))
                if LoginItem.isBlockedByUser {
                    Text("macOS is holding this off until you allow Murmur under Login Items in System Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LabeledContent("Ignore presses shorter than:") {
                    Stepper(
                        "\(preferences.minimumRecordingSeconds, format: .number.precision(.fractionLength(2)))s",
                        value: Binding(
                            get: { preferences.minimumRecordingSeconds },
                            set: { preferences.minimumRecordingSeconds = $0 }
                        ),
                        in: 0.1...2.0,
                        step: 0.05
                    )
                }
                Text("Stops a stray tap on the trigger key from pasting a stray word.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Behaviour")
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

private struct TextSettingsTab: View {
    @EnvironmentObject private var preferences: Preferences

    private var languageModelAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        return TextPolisher.isAvailable
    }

    private var languageModelProblem: String? {
        guard #available(macOS 26.0, *) else {
            return "Requires macOS 26 or later."
        }
        return TextPolisher.unavailabilityReason
    }

    var body: some View {
        Form {
            Section {
                Toggle("Remove “um”, “uh”, and stutters", isOn: Binding(
                    get: { preferences.removeFillers },
                    set: { preferences.removeFillers = $0 }
                ))
                Text("A fixed word list, so it runs instantly and can never change what you said. “Ah” and “oh” are kept, since they usually mean something.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Also remove “you know”, “I mean”, and filler “like”", isOn: Binding(
                    get: { preferences.removeDiscourseMarkers },
                    set: { preferences.removeDiscourseMarkers = $0 }
                ))
                .disabled(!preferences.removeFillers)
                Text("Only where they read as padding. “I like it” and “looks like rain” are left alone.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Cleanup")
            }

            Section {
                Toggle("Rewrite with Apple Intelligence", isOn: Binding(
                    get: { preferences.polishWithLanguageModel },
                    set: { preferences.polishWithLanguageModel = $0 }
                ))
                .disabled(!languageModelAvailable)

                if let problem = languageModelProblem {
                    Text(problem)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Repairs false starts, abandoned sentences, and grammar as well as fillers. Runs entirely on this Mac, but adds a noticeable pause after you let go of the key. If the rewrite looks wrong, Murmur keeps your original words instead.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Rewriting")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelSettingsTab: View {
    @EnvironmentObject private var controller: DictationController
    @EnvironmentObject private var preferences: Preferences
    @StateObject private var inventory = ModelInventory()
    @State private var pendingDeletion: InstalledModel?

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

            if preferences.engineID == "nemotron" {
                Section {
                    Picker("Update the readout:", selection: Binding(
                        get: { preferences.nemotronChunkMs },
                        set: { newValue in
                            preferences.nemotronChunkMs = newValue
                            Task { await controller.reloadEngine() }
                        }
                    )) {
                        Text("Every 2.2 seconds").tag(2240)
                        Text("Every 1.1 seconds").tag(1120)
                        Text("Every 0.6 seconds").tag(560)
                    }
                    Text("Nemotron emits text once per audio chunk, so this sets how often the live readout catches up while you speak. Shorter chunks update more smoothly and cost some throughput. Each setting is a separate model download.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Live Text")
                }
            } else if !EngineRegistry.descriptor(for: preferences.engineID).providesLiveText {
                Section {
                    Text("This engine only produces text once you release the key, so the readout shows a level meter rather than your words as you speak.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Live Text")
                }
            }

            Section {
                if inventory.models.isEmpty {
                    Text(inventory.isScanning ? "Looking…" : "Nothing downloaded yet.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(inventory.models) { model in
                        InstalledModelRow(
                            model: model,
                            isInUse: isInUse(model),
                            onDelete: { pendingDeletion = model }
                        )
                    }
                    LabeledContent("Total on disk:", value: inventory.formattedTotal)
                        .font(.caption)
                }

                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(
                        nil,
                        inFileViewerRootedAtPath: ModelInventory.cacheDirectory.path
                    )
                }
                .font(.caption)
            } header: {
                Text("Downloaded Models")
            } footer: {
                Text("Deleting a model frees the space immediately. It downloads again the next time you use that engine, language, or update rate.")
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
        .task { inventory.refresh() }
        .onChange(of: controller.enginePreparation) { _, newValue in
            if newValue.isReady { inventory.refresh() }
        }
        .confirmationDialog(
            "Delete \(pendingDeletion?.displayName ?? "this model")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let model = pendingDeletion { delete(model) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            if let model = pendingDeletion {
                Text("This frees \(model.formattedSize). Murmur downloads it again the next time it is needed.")
            }
        }
    }

    private func isInUse(_ model: InstalledModel) -> Bool {
        model.isInUse(
            descriptor: EngineRegistry.descriptor(for: preferences.engineID),
            language: preferences.language,
            chunkMilliseconds: preferences.nemotronChunkMs
        )
    }

    private func delete(_ model: InstalledModel) {
        guard isInUse(model) else {
            // A build that is not loaded has no files mapped, so it can go
            // without disturbing the running engine.
            inventory.delete(model)
            return
        }
        // CoreML keeps a loaded model's files mapped, so the engine has to let
        // go before the directory can be removed.
        Task {
            await controller.releaseEngine()
            inventory.delete(model)
        }
    }
}

private struct InstalledModelRow: View {
    let model: InstalledModel
    let isInUse: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                if let variant = model.displayVariant {
                    Text(variant).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)

            if isInUse {
                Text("In use")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }

            Text(model.formattedSize)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete this download")
        }
        .padding(.vertical, 2)
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

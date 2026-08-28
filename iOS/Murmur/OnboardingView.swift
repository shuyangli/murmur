import AVFoundation
import SwiftUI
import UIKit

/// Three things have to happen before the keyboard can be tested, and two of
/// them can only happen here: the microphone prompt belongs to the container
/// app, and the Full Access warning needs explaining before iOS shows its own
/// blunt version of it.
struct OnboardingView: View {
    @State private var microphone = AVAudioApplication.shared.recordPermission
    @State private var scratch = ""
    @FocusState private var scratchFocused: Bool
    @State private var control: String?
    @State private var running = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Microphone", value: microphoneLabel)
                    if microphone == .undetermined {
                        Button("Grant microphone access", action: requestMicrophone)
                    } else if microphone == .denied {
                        Button("Open Settings", action: openSettings)
                    }
                } header: {
                    Text("1 · Microphone")
                } footer: {
                    Text("The keyboard cannot show this prompt itself, so the app asks once on its behalf.")
                }

                Section {
                    Button("Open Settings", action: openSettings)
                } header: {
                    Text("2 · Keyboard")
                } footer: {
                    Text(
                        """
                        General › Keyboard › Keyboards › Add New Keyboard › Murmur, \
                        then tap Murmur again and turn on Allow Full Access.

                        iOS warns that a keyboard with Full Access may transmit \
                        everything you type. Murmur cannot: the keyboard has no \
                        network entitlement at all. It needs Full Access only to \
                        open a microphone.
                        """
                    )
                }

                Section {
                    TextField("Tap here, then switch to Murmur", text: $scratch, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($scratchFocused)
                } header: {
                    Text("3 · Try it")
                } footer: {
                    Text("Hold the globe key to switch keyboards, then hold Murmur's button and speak.")
                }

                Section {
                    Button(running ? "Recording…" : "Run the same spike here") {
                        runControl()
                    }
                    .disabled(running)

                    if let control {
                        Text(control)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("4 · Control run")
                } footer: {
                    Text(
                        """
                        The same code, in the app instead of the keyboard. If this \
                        passes and the keyboard fails, the extension is the cause. If \
                        both fail, the spike is wrong.
                        """
                    )
                }
            }
            .navigationTitle("Murmur")
            .onChange(of: scratchFocused) { _, _ in
                microphone = AVAudioApplication.shared.recordPermission
            }
        }
    }

    private var microphoneLabel: String {
        switch microphone {
        case .granted: "Granted"
        case .denied: "Denied"
        case .undetermined: "Not asked"
        @unknown default: "Unknown"
        }
    }

    /// Two seconds is long enough for a tap to deliver buffers and short
    /// enough that the button does not feel stuck.
    private static let controlRunDuration = Duration.seconds(2)

    private func runControl() {
        running = true
        control = nil
        let spike = AudioSpike()
        spike.start()
        Task {
            try? await Task.sleep(for: Self.controlRunDuration)
            control = spike.stop().summary(host: "container app", fullAccess: nil)
            running = false
        }
    }

    private func requestMicrophone() {
        AVAudioApplication.requestRecordPermission { _ in
            Task { @MainActor in
                microphone = AVAudioApplication.shared.recordPermission
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

/// The three system permissions Murmur needs, and the system setting that
/// otherwise steals the Globe key out from under it.
@MainActor
enum Permissions {

    // MARK: - Accessibility (needed to synthesise ⌘V)

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system's "allow accessibility" prompt if it has not been answered.
    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - Input Monitoring (needed to see the trigger key globally)

    static var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func promptForInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    // MARK: - Microphone

    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Globe key behaviour

    /// Values macOS stores for "Press 🌐 key to" in Keyboard settings.
    enum GlobeKeyAction: Int {
        case doNothing = 0
        case changeInputSource = 1
        case showEmoji = 2
        case startDictation = 3

        var label: String {
            switch self {
            case .doNothing: return "Do Nothing"
            case .changeInputSource: return "Change Input Source"
            case .showEmoji: return "Show Emoji & Symbols"
            case .startDictation: return "Start Dictation"
            }
        }
    }

    /// What macOS will do on its own when the Globe key is pressed.
    ///
    /// Anything other than `doNothing` fires alongside our dictation, so the
    /// user gets an emoji picker or an input-source switch every time they
    /// speak. There is no API to change this, only to detect and explain it.
    static var globeKeyAction: GlobeKeyAction {
        let raw = UserDefaults(suiteName: "com.apple.HIToolbox")?
            .integer(forKey: "AppleFnUsageType") ?? 0
        return GlobeKeyAction(rawValue: raw) ?? .doNothing
    }

    static var globeKeyConflicts: Bool {
        Preferences.shared.triggerKey == .fn && globeKeyAction != .doNothing
    }

    // MARK: - Deep links into System Settings

    enum SettingsPane: String {
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
        case microphone = "Privacy_Microphone"
        case speechRecognition = "Privacy_SpeechRecognition"

        var url: URL {
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")!
        }
    }

    static func open(_ pane: SettingsPane) {
        NSWorkspace.shared.open(pane.url)
    }

    static func openKeyboardSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}

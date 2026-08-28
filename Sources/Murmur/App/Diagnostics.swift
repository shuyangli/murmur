import AVFoundation
import AppKit
import CoreGraphics
import Foundation

/// Prints why dictation is or is not working.
///
/// Run with: `Murmur.app/Contents/MacOS/Murmur --diagnose`
@MainActor
enum Diagnostics {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--diagnose")
    }

    static func run() -> Never {
        setvbuf(stdout, nil, _IONBF, 0)

        let preferences = Preferences.shared
        print("Murmur diagnostics")
        print("")
        print("Trigger key:      \(preferences.triggerKey.label)")
        print("Engine:           \(EngineRegistry.descriptor(for: preferences.engineID).name)")
        print("Language:         \(preferences.language)")
        print("Output:           \(preferences.outputMode.label)")
        print("History limit:    \(preferences.historyLimit)")
        print("")

        // When this binary is launched from a shell, TCC attributes permission
        // checks to the terminal rather than to Murmur, so a grant the terminal
        // holds shows up here as Murmur's. The Permissions tab inside the
        // running app is the authoritative reading.
        print("Note: run from a terminal, the three rows below may reflect the")
        print("      terminal's own grants. Settings › Permissions is definitive.")
        print("")

        report("Input Monitoring", Permissions.inputMonitoringGranted,
               "needed to notice the trigger key in other apps")
        report("Accessibility", Permissions.accessibilityGranted,
               "needed to paste into the focused app")
        report("Microphone", Permissions.microphoneGranted,
               "needed to hear you")
        print("")

        // Actually attempting the tap is the only reliable check; the
        // permission flag and the tap can disagree after a policy change.
        let tapCreated = canCreateEventTap()
        report("Event tap", tapCreated, "the mechanism that watches the trigger key")

        if preferences.triggerKey == .fn {
            let action = Permissions.globeKeyAction
            let clean = action == .doNothing
            report("Globe key free", clean,
                   clean ? "macOS does nothing else with it"
                         : "macOS also runs “\(action.label)” — set “Press 🌐 key to” to “Do Nothing”")
        }

        print("")
        print("Open at login:    \(loginItemDescription)")

        let historyURL = AppPaths.supportDirectory.appendingPathComponent("history.json")
        let entryCount = (try? Data(contentsOf: historyURL))
            .flatMap { try? JSONDecoder.murmur.decode([HistoryEntry].self, from: $0) }?.count ?? 0
        print("History file:     \(historyURL.path)")
        print("Saved entries:    \(entryCount)")

        exit(0)
    }

    private static var loginItemDescription: String {
        if LoginItem.isEnabled { return "on" }
        if LoginItem.isBlockedByUser { return "blocked — allow Murmur under Login Items in System Settings" }
        return "off"
    }

    private static func report(_ name: String, _ ok: Bool, _ detail: String) {
        let mark = ok ? "ok  " : "MISSING"
        print("[\(mark)] \(name.padding(toLength: 18, withPad: " ", startingAt: 0)) \(detail)")
    }

    private static func canCreateEventTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) else { return false }
        CGEvent.tapEnable(tap: tap, enable: false)
        return true
    }
}

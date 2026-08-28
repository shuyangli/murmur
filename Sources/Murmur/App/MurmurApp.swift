import AppKit
import Combine
import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var controller = DictationController.shared
    @ObservedObject private var preferences = Preferences.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(controller)
                .environmentObject(preferences)
        } label: {
            MenuBarIcon(state: controller.state)
        }
        .menuBarExtraStyle(.window)

        Window("Dictation History", id: WindowID.history) {
            HistoryWindow()
                .environmentObject(controller)
                .environmentObject(preferences)
        }
        .defaultSize(width: 640, height: 540)
        .commandsRemoved()

        Settings {
            SettingsWindow()
                .environmentObject(controller)
                .environmentObject(preferences)
        }
    }
}

enum WindowID {
    static let history = "history"
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = RecordingOverlay()
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Diagnostics.isRequested {
            Diagnostics.run()
        }
        if SelfTest.isRequested {
            Task { await SelfTest.run() }
            return
        }

        // Menu-bar only. LSUIElement in Info.plist keeps the Dock icon away
        // from the moment of launch; this call covers non-bundled runs.
        NSApp.setActivationPolicy(.accessory)

        let controller = DictationController.shared
        controller.start()

        // Drive the floating recording indicator off the controller rather
        // than from SwiftUI, so it can be a non-activating panel that never
        // steals focus from the app being dictated into.
        controller.$state
            .combineLatest(controller.$level)
            .sink { [overlay] state, level in
                overlay.update(state: state, level: level)
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        DictationController.shared.stop()
    }
}

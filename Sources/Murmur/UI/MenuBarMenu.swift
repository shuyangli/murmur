import AppKit
import SwiftUI

/// The status item's menu.
///
/// This is a real `NSMenu`, built from the view vocabulary `MenuBarExtra`
/// supports in its default `.menu` style: `Text`, `Button`, `Divider`, and
/// `Menu`. Richer SwiftUI — stacks, progress bars, custom padding — only
/// renders under `.window` style, which draws a floating panel rather than a
/// menu and gives up native highlighting, keyboard navigation, and dismissal.
///
/// Deliberately holds no status or progress reporting. Nobody watches the menu
/// bar while they wait, so anything the user needs to be told goes to the
/// on-screen HUD at the moment they press the key, and anything they might go
/// looking for lives in Settings.
struct MenuBarMenu: View {
    /// Observed directly rather than through the environment: SwiftUI does not
    /// reliably rebuild `.menu`-style content in response to environment
    /// object changes.
    @ObservedObject private var controller = DictationController.shared

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private static let recentCount = 8
    /// Menu items get unwieldy long before a full dictation ends.
    private static let recentItemLength = 52

    var body: some View {
        // The one problem with no other route to the user: with Input
        // Monitoring off the trigger key is never seen, so pressing it cannot
        // raise the HUD that would otherwise explain the situation.
        if !controller.hotkeyActive {
            Button("⚠︎ Turn On Input Monitoring…") {
                Permissions.promptForInputMonitoring()
                Permissions.open(.inputMonitoring)
            }
            Divider()
        }

        Menu("Recent Dictations") {
            recentItems
        }

        Divider()

        Button("Dictation History…") {
            activateApp()
            openWindow(id: WindowID.history)
        }

        Button("Settings…") {
            activateApp()
            openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit Murmur") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    @ViewBuilder
    private var recentItems: some View {
        let recent = Array(controller.history.entries.prefix(Self.recentCount))
        if recent.isEmpty {
            Text("Nothing yet")
        } else {
            ForEach(recent) { entry in
                Button(menuTitle(for: entry.text)) {
                    TextInjector.copy(entry.text)
                }
            }
            Divider()
            Button("Open History…") {
                activateApp()
                openWindow(id: WindowID.history)
            }
        }
    }

    private func menuTitle(for text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > Self.recentItemLength else { return flattened }
        return flattened.prefix(Self.recentItemLength).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// An accessory app has to raise itself explicitly before a window it
    /// opens will come to the front.
    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

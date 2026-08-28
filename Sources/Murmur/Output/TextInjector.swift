import AppKit
import CoreGraphics
import Foundation

/// Delivers a finished transcript to whatever app the user was typing in.
///
/// Pasting is used rather than synthesising the text keystroke by keystroke:
/// it is near-instant regardless of length, and it survives apps that debounce
/// or reorder rapid synthetic key events.
@MainActor
enum TextInjector {
    /// Virtual key code for "v" on any layout, since CGEvent takes hardware codes.
    private static let vKeyCode: CGKeyCode = 9

    /// How long to leave the transcript on the pasteboard before restoring the
    /// previous contents. The receiving app reads the pasteboard asynchronously
    /// after ⌘V lands, so restoring too eagerly pastes the wrong thing.
    private static let clipboardRestoreDelay = Duration.milliseconds(400)

    /// Time for the frontmost app to settle after our overlay hides.
    private static let focusSettleDelay = Duration.milliseconds(20)

    static func deliver(_ text: String, mode: OutputMode, restoreClipboard: Bool) async {
        guard !text.isEmpty else { return }

        switch mode {
        case .copyToClipboardOnly:
            copy(text)
        case .pasteIntoFocusedApp:
            guard Permissions.accessibilityGranted else {
                Log.output.error("Accessibility not granted; copying instead of pasting.")
                copy(text)
                return
            }
            await paste(text, restoreClipboard: restoreClipboard)
        }
    }

    static func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func paste(_ text: String, restoreClipboard: Bool) async {
        let pasteboard = NSPasteboard.general
        let snapshot = restoreClipboard ? capture(pasteboard) : nil

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try? await Task.sleep(for: focusSettleDelay)
        sendCommandV()

        guard let snapshot else { return }
        try? await Task.sleep(for: clipboardRestoreDelay)
        restore(snapshot, to: pasteboard)
    }

    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            Log.output.error("Could not create an event source for the paste.")
            return
        }
        // Stop the user's physically-held keys from leaking into our synthetic
        // events; the trigger key in particular may still be settling.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Pasteboard snapshotting

    private struct PasteboardSnapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    private static func capture(_ pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
        return PasteboardSnapshot(items: items)
    }

    private static func restore(_ snapshot: PasteboardSnapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else { return }
        // Items captured from a cleared pasteboard are dead objects, so rebuild.
        let rebuilt = snapshot.items.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(rebuilt)
    }
}

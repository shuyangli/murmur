import AppKit
import CoreGraphics
import Foundation

/// Watches the whole session for the trigger key being pressed and released.
///
/// Uses a listen-only `CGEventTap` rather than `RegisterEventHotKey` because
/// the Fn/Globe key is not a key the Carbon hotkey API can express — it only
/// ever appears as a modifier bit on `flagsChanged` events.
@MainActor
final class HotkeyMonitor {
    enum Event {
        case pressed
        /// The key was released normally; dictation should be committed.
        case released
        /// The user chorded the trigger with another key, so this was a
        /// shortcut and not dictation.
        case cancelled
    }

    var onEvent: ((Event) -> Void)?

    private(set) var isRunning = false
    private(set) var isHolding = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var triggerKey: TriggerKey
    /// Set when another key is pressed mid-hold, so the release is discarded.
    private var chordDetected = false

    init(triggerKey: TriggerKey) {
        self.triggerKey = triggerKey
    }

    deinit {
        // Tear down without hopping actors; these CF calls are thread-safe.
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
    }

    func setTriggerKey(_ key: TriggerKey) {
        guard key != triggerKey else { return }
        if isHolding { finishHold(cancelled: true) }
        triggerKey = key
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning else { return true }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                // The tap callback runs on the main run loop, so touching
                // MainActor state here is safe even though the C signature
                // cannot express it.
                MainActor.assumeIsolated {
                    monitor.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: context
        ) else {
            Log.hotkey.error("Could not create event tap; Input Monitoring is probably not granted.")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        isRunning = true
        Log.hotkey.info("Event tap running for \(self.triggerKey.rawValue, privacy: .public)")
        return true
    }

    func stop() {
        guard isRunning else { return }
        if isHolding { finishHold(cancelled: true) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
        isRunning = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disables a tap that blocks for too long. Re-arm it.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.hotkey.warning("Event tap was disabled by the system; re-enabled.")

        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == triggerKey.keyCode else {
                // A different modifier moved. If it joined an active hold,
                // the user is building a shortcut, not dictating.
                if isHolding, !event.flags.intersection(otherModifiers).isEmpty {
                    chordDetected = true
                }
                return
            }
            let held = triggerKey.isCleanlyHeld(in: event.flags)
            if held, !isHolding {
                beginHold()
            } else if !held, isHolding {
                finishHold(cancelled: chordDetected)
            }

        case .keyDown:
            if isHolding { chordDetected = true }

        default:
            break
        }
    }

    private var otherModifiers: CGEventFlags {
        CGEventFlags(rawValue: triggerKey.disallowedFlags)
    }

    private func beginHold() {
        isHolding = true
        chordDetected = false
        onEvent?(.pressed)
    }

    private func finishHold(cancelled: Bool) {
        isHolding = false
        let wasChord = chordDetected
        chordDetected = false
        onEvent?(cancelled || wasChord ? .cancelled : .released)
    }
}

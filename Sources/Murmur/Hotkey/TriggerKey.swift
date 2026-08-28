import Foundation
import CoreGraphics

/// A modifier key that can be held down to dictate.
///
/// Only keys that produce no character on their own are offered, so that a
/// press which we choose not to treat as dictation still does nothing
/// surprising in the focused app.
enum TriggerKey: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand
    case rightControl
    case rightShift

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: return "Fn / 🌐 Globe"
        case .rightOption: return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        case .rightControl: return "Right Control (⌃)"
        case .rightShift: return "Right Shift (⇧)"
        }
    }

    /// Virtual key code reported in the `keyCode` field of a `flagsChanged` event.
    var keyCode: Int64 {
        switch self {
        case .fn: return 63
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }

    /// Bit in `CGEventFlags` that is set while this specific physical key is down.
    ///
    /// The device-dependent bits (`NX_DEVICER*KEYMASK`) are what distinguish
    /// the right-hand modifiers from their left-hand twins; the device
    /// independent masks alone cannot.
    var flagMask: UInt64 {
        switch self {
        case .fn: return CGEventFlags.maskSecondaryFn.rawValue
        case .rightOption: return 0x0000_0040
        case .rightCommand: return 0x0000_0010
        case .rightControl: return 0x0000_2000
        case .rightShift: return 0x0000_0004
        }
    }

    /// Flags that must *not* be present, so that chords such as ⌘⌥ are ignored.
    var disallowedFlags: UInt64 {
        let all: UInt64 = CGEventFlags.maskCommand.rawValue
            | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskControl.rawValue
            | CGEventFlags.maskShift.rawValue
            | CGEventFlags.maskSecondaryFn.rawValue
        return all & ~deviceIndependentFlag
    }

    /// The device-independent flag this key also raises (⌥ for right option, etc).
    private var deviceIndependentFlag: UInt64 {
        switch self {
        case .fn: return CGEventFlags.maskSecondaryFn.rawValue
        case .rightOption: return CGEventFlags.maskAlternate.rawValue
        case .rightCommand: return CGEventFlags.maskCommand.rawValue
        case .rightControl: return CGEventFlags.maskControl.rawValue
        case .rightShift: return CGEventFlags.maskShift.rawValue
        }
    }

    /// True when this key is physically down in the given flag set and no other
    /// modifier is muddying the signal.
    func isCleanlyHeld(in flags: CGEventFlags) -> Bool {
        let raw = flags.rawValue
        return raw & flagMask != 0 && raw & disallowedFlags == 0
    }
}

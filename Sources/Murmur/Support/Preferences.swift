import Foundation
import Combine

/// Where the trigger key sends its result once transcription finishes.
enum OutputMode: String, CaseIterable, Identifiable {
    case pasteIntoFocusedApp
    case copyToClipboardOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pasteIntoFocusedApp: return "Paste into the focused app"
        case .copyToClipboardOnly: return "Copy to clipboard only"
        }
    }
}

/// User-visible settings, persisted in `UserDefaults`.
///
/// This is a plain `ObservableObject` rather than `@Observable` so that
/// SwiftUI bindings and the non-UI actors can both observe changes through
/// Combine without a MainActor hop on every read.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let triggerKey = "triggerKey"
        static let engineID = "engineID"
        static let language = "language"
        static let outputMode = "outputMode"
        static let historyLimit = "historyLimit"
        static let playFeedbackSounds = "playFeedbackSounds"
        static let restoreClipboard = "restoreClipboard"
        static let minimumRecordingSeconds = "minimumRecordingSeconds"
        static let trimTrailingWhitespace = "trimTrailingWhitespace"
        static let removeFillers = "removeFillers"
        static let removeDiscourseMarkers = "removeDiscourseMarkers"
        static let polishWithLanguageModel = "polishWithLanguageModel"
        static let nemotronChunkMs = "nemotronChunkMs"
    }

    /// Below this, a key press is treated as a stray tap rather than dictation.
    static let defaultMinimumRecordingSeconds = 0.35
    static let defaultHistoryLimit = 100
    /// NVIDIA's recommended tier: highest throughput, and WER-neutral
    /// against the 1120 ms chunk the model was actually trained at.
    static let defaultNemotronChunkMs = 2240
    /// Tiers Nemotron ships CoreML bundles for. Each is a separate download.
    static let nemotronChunkChoices = [2240, 1120, 560]
    static let historyLimitRange = 10...1000

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.triggerKey: TriggerKey.fn.rawValue,
            Key.engineID: "nemotron",
            Key.language: "en-US",
            Key.outputMode: OutputMode.pasteIntoFocusedApp.rawValue,
            Key.historyLimit: Self.defaultHistoryLimit,
            Key.playFeedbackSounds: true,
            Key.restoreClipboard: true,
            Key.minimumRecordingSeconds: Self.defaultMinimumRecordingSeconds,
            Key.trimTrailingWhitespace: true,
            Key.removeFillers: true,
            Key.removeDiscourseMarkers: false,
            Key.polishWithLanguageModel: false,
            Key.nemotronChunkMs: Self.defaultNemotronChunkMs,
        ])
    }

    private func set<T>(_ value: T, forKey key: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
    }

    var triggerKey: TriggerKey {
        get { TriggerKey(rawValue: defaults.string(forKey: Key.triggerKey) ?? "") ?? .fn }
        set { set(newValue.rawValue, forKey: Key.triggerKey) }
    }

    var engineID: String {
        get { defaults.string(forKey: Key.engineID) ?? "nemotron" }
        set { set(newValue, forKey: Key.engineID) }
    }

    /// BCP-47 hint passed to the engine, or `"auto"` to let it detect.
    var language: String {
        get { defaults.string(forKey: Key.language) ?? "en-US" }
        set { set(newValue, forKey: Key.language) }
    }

    var outputMode: OutputMode {
        get { OutputMode(rawValue: defaults.string(forKey: Key.outputMode) ?? "") ?? .pasteIntoFocusedApp }
        set { set(newValue.rawValue, forKey: Key.outputMode) }
    }

    var historyLimit: Int {
        get {
            let stored = defaults.integer(forKey: Key.historyLimit)
            guard stored > 0 else { return Self.defaultHistoryLimit }
            return min(max(stored, Self.historyLimitRange.lowerBound), Self.historyLimitRange.upperBound)
        }
        set { set(newValue, forKey: Key.historyLimit) }
    }

    var playFeedbackSounds: Bool {
        get { defaults.bool(forKey: Key.playFeedbackSounds) }
        set { set(newValue, forKey: Key.playFeedbackSounds) }
    }

    /// Put the user's previous clipboard back after the paste completes.
    var restoreClipboard: Bool {
        get { defaults.bool(forKey: Key.restoreClipboard) }
        set { set(newValue, forKey: Key.restoreClipboard) }
    }

    var minimumRecordingSeconds: Double {
        get {
            let stored = defaults.double(forKey: Key.minimumRecordingSeconds)
            return stored > 0 ? stored : Self.defaultMinimumRecordingSeconds
        }
        set { set(newValue, forKey: Key.minimumRecordingSeconds) }
    }

    var trimTrailingWhitespace: Bool {
        get { defaults.bool(forKey: Key.trimTrailingWhitespace) }
        set { set(newValue, forKey: Key.trimTrailingWhitespace) }
    }

    /// Strip "um", "uh" and friends. Costs nothing measurable, so on by default.
    var removeFillers: Bool {
        get { defaults.bool(forKey: Key.removeFillers) }
        set { set(newValue, forKey: Key.removeFillers) }
    }

    /// Also strip "you know", "I mean", and parenthetical "like".
    var removeDiscourseMarkers: Bool {
        get { defaults.bool(forKey: Key.removeDiscourseMarkers) }
        set { set(newValue, forKey: Key.removeDiscourseMarkers) }
    }

    /// Rewrite the transcript with Apple's on-device model. Off by default:
    /// it adds latency exactly where the user is waiting.
    var polishWithLanguageModel: Bool {
        get { defaults.bool(forKey: Key.polishWithLanguageModel) }
        set { set(newValue, forKey: Key.polishWithLanguageModel) }
    }

    /// Audio chunk Nemotron decodes at, in milliseconds. Also the interval at
    /// which the live subtitle updates, since a partial is emitted per chunk.
    var nemotronChunkMs: Int {
        get {
            let stored = defaults.integer(forKey: Key.nemotronChunkMs)
            return Self.nemotronChunkChoices.contains(stored) ? stored : Self.defaultNemotronChunkMs
        }
        set { set(newValue, forKey: Key.nemotronChunkMs) }
    }
}

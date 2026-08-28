import Foundation

/// How far along an engine is in getting itself ready to transcribe.
enum EnginePreparation: Equatable {
    case idle
    case downloading(fraction: Double, detail: String)
    case loading
    case ready
    case failed(String)

    var isReady: Bool { self == .ready }

    var isBusy: Bool {
        switch self {
        case .downloading, .loading: return true
        case .idle, .ready, .failed: return false
        }
    }

    var describedForMenu: String {
        switch self {
        case .idle: return "Not loaded"
        case .downloading(let fraction, let detail):
            return "Downloading \(Int(fraction * 100))% — \(detail)"
        case .loading: return "Loading model…"
        case .ready: return "Ready"
        case .failed(let message): return "Failed: \(message)"
        }
    }
}

/// Static description of an engine, so the settings UI can list the choices
/// without paying to instantiate or download any of them.
struct EngineDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    /// Rough on-disk cost, shown before the user commits to a download.
    let approximateDownload: String
    /// Whether the engine can show text while the user is still speaking.
    let providesLiveText: Bool
    let make: @Sendable () -> any TranscriptionEngine

    static func == (lhs: EngineDescriptor, rhs: EngineDescriptor) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A swappable speech-to-text backend.
///
/// The interface is utterance-shaped and streaming-first: audio is pushed in
/// as it is captured and the transcript is pulled once at the end. Engines
/// that can only work in batch simply accumulate in `feed` and do all their
/// work in `finishUtterance`.
protocol TranscriptionEngine: AnyObject, Sendable {
    /// Downloads and loads whatever the engine needs. Safe to call repeatedly;
    /// a second call on a ready engine returns immediately.
    func prepare(progress: @escaping @Sendable (EnginePreparation) -> Void) async throws

    /// Starts a new utterance, discarding any state from the previous one.
    func beginUtterance(language: String) async throws

    /// Appends mono 16 kHz samples.
    func feed(_ samples: [Float]) async throws

    /// Flushes the utterance and returns the final transcript.
    func finishUtterance() async throws -> String

    /// Abandons the utterance without producing a transcript.
    func cancelUtterance() async

    /// Releases models and their memory.
    func unload() async

    /// Installs a handler that receives the transcript so far, while the user
    /// is still speaking. Each call carries the complete text to date, not a
    /// delta, so the display can simply be replaced.
    func setPartialHandler(_ handler: (@Sendable (String) -> Void)?) async
}

extension TranscriptionEngine {
    /// Batch engines have nothing to report until the utterance ends.
    func setPartialHandler(_ handler: (@Sendable (String) -> Void)?) async {}
}

enum TranscriptionEngineError: LocalizedError {
    case notReady
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "The transcription model is not loaded yet."
        case .unsupported(let detail):
            return detail
        }
    }
}

/// The engines this build offers.
enum EngineRegistry {
    static let all: [EngineDescriptor] = [
        EngineDescriptor(
            id: NemotronEngine.id,
            name: "NVIDIA Nemotron 3.5 ASR",
            summary: "Streaming 0.6B multilingual model on the Neural Engine. Punctuates and capitalises as it goes.",
            approximateDownload: "~700 MB",
            providesLiveText: true,
            make: { NemotronEngine() }
        ),
        EngineDescriptor(
            id: ParakeetEngine.id,
            name: "NVIDIA Parakeet TDT v3",
            summary: "Batch 0.6B model. Slightly faster to load, transcribes only after you release the key.",
            approximateDownload: "~650 MB",
            providesLiveText: false,
            make: { ParakeetEngine() }
        ),
        EngineDescriptor(
            id: AppleSpeechEngine.id,
            name: "Apple Speech (built in)",
            summary: "Uses the on-device recogniser already installed by macOS. Nothing to download.",
            approximateDownload: "none",
            providesLiveText: true,
            make: { AppleSpeechEngine() }
        ),
    ]

    static func descriptor(for id: String) -> EngineDescriptor {
        all.first { $0.id == id } ?? all[0]
    }
}

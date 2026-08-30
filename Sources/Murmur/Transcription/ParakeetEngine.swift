import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT v3 on CoreML.
///
/// Parakeet's manager is batch-oriented, so samples are accumulated during the
/// hold and decoded in one pass on release. At roughly 100x real time that
/// still lands well under a second for normal dictation lengths.
actor ParakeetEngine: TranscriptionEngine {
    static let id = "parakeet"

    /// Guard against a runaway hold pinning unbounded memory: 10 minutes of
    /// 16 kHz mono float is about 38 MB.
    private static let maximumSamples = Int(AudioRecorder.targetSampleRate) * 600

    private var manager: AsrManager?
    private var buffer: [Float] = []
    private var preparation: EnginePreparation = .idle
    private var preparationTask: Task<Void, Error>?

    func prepare(progress: @escaping @Sendable (EnginePreparation) -> Void) async throws {
        if preparation.isReady { progress(.ready); return }

        if let existing = preparationTask {
            try await existing.value
            progress(preparation)
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            try await self.load(progress: progress)
        }
        preparationTask = task
        defer { preparationTask = nil }

        do {
            try await task.value
        } catch {
            preparation = .failed(error.localizedDescription)
            progress(preparation)
            throw error
        }
    }

    private func load(progress: @escaping @Sendable (EnginePreparation) -> Void) async throws {
        preparation = .downloading(fraction: 0, detail: "Contacting model host")
        progress(preparation)

        let startedAt = Date()
        let models = try await AsrModels.downloadAndLoad(
            version: .v3,
            progressHandler: { update in
                progress(.downloading(fraction: update.fractionCompleted, detail: update.phase.readableDescription))
            }
        )

        preparation = .loading
        progress(preparation)

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)

        self.manager = manager
        preparation = .ready
        progress(preparation)
        Log.asr.info("Parakeet ready in \(Date().timeIntervalSince(startedAt), format: .fixed(precision: 2))s")
    }

    func beginUtterance(language: String) async throws {
        guard manager != nil else { throw TranscriptionEngineError.notReady }
        buffer.removeAll(keepingCapacity: true)
    }

    func feed(_ samples: [Float]) async throws {
        guard buffer.count < Self.maximumSamples else { return }
        buffer.append(contentsOf: samples)
    }

    func finishUtterance() async throws -> String {
        guard let manager else { throw TranscriptionEngineError.notReady }
        let samples = buffer
        buffer.removeAll(keepingCapacity: true)
        guard !samples.isEmpty else { return "" }

        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text
    }

    func cancelUtterance() async {
        buffer.removeAll(keepingCapacity: true)
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
        buffer.removeAll()
        preparation = .idle
    }
}

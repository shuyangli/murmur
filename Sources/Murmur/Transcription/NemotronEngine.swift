import FluidAudio
import Foundation

/// NVIDIA Nemotron 3.5 ASR streaming multilingual, running on CoreML.
///
/// Because the model is genuinely streaming, audio is decoded while the user
/// is still talking. By the time they release the trigger key only the final
/// partial chunk is outstanding, which is what makes the result feel instant.
actor NemotronEngine: TranscriptionEngine {
    static let id = "nemotron"

    /// 2.24 s chunks: NVIDIA's recommended tier, highest throughput and
    /// WER-neutral against the 1.12 s tier the model was trained at.
    private static let chunkMilliseconds = 2240

    private var manager: StreamingNemotronMultilingualAsrManager?
    private var preparation: EnginePreparation = .idle
    private var preparationTask: Task<Void, Error>?
    private var activeLanguage: String?

    func prepare(progress: @escaping @Sendable (EnginePreparation) -> Void) async throws {
        if preparation.isReady { progress(.ready); return }

        // Coalesce concurrent prepares onto one download.
        if let existing = preparationTask {
            try await existing.value
            progress(preparation)
            return
        }

        let language = Preferences.shared.language
        let task = Task { [weak self] in
            guard let self else { return }
            try await self.load(language: language, progress: progress)
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

    private func load(
        language: String,
        progress: @escaping @Sendable (EnginePreparation) -> Void
    ) async throws {
        preparation = .downloading(fraction: 0, detail: "Contacting model host")
        progress(preparation)

        let directory = try await StreamingNemotronMultilingualAsrManager.downloadVariant(
            languageCode: language,
            chunkMs: Self.chunkMilliseconds,
            progressHandler: { update in
                progress(.downloading(fraction: update.fractionCompleted, detail: update.phase.readableDescription))
            }
        )

        preparation = .loading
        progress(preparation)

        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadModels(from: directory)
        await manager.setLanguage(language)

        self.manager = manager
        self.activeLanguage = language
        preparation = .ready
        progress(preparation)
        Log.asr.info("Nemotron ready (\(language, privacy: .public))")
    }

    func beginUtterance(language: String) async throws {
        guard let manager else { throw TranscriptionEngineError.notReady }
        await manager.reset()
        if language != activeLanguage {
            await manager.setLanguage(language)
            activeLanguage = language
        }
    }

    func feed(_ samples: [Float]) async throws {
        guard let manager else { throw TranscriptionEngineError.notReady }
        _ = try await manager.process(samples: samples)
    }

    func finishUtterance() async throws -> String {
        guard let manager else { throw TranscriptionEngineError.notReady }
        return try await manager.finish()
    }

    func cancelUtterance() async {
        await manager?.reset()
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
        preparation = .idle
    }
}

extension DownloadPhase {
    var readableDescription: String {
        switch self {
        case .listing:
            return "Listing model files"
        case .downloading(let completed, let total):
            return "File \(completed) of \(total)"
        case .compiling(let modelName):
            return "Compiling \(modelName)"
        }
    }
}

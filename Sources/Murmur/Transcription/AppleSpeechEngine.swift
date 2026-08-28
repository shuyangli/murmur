import AVFoundation
import Foundation
import Speech

/// macOS's built-in recogniser, pinned to on-device mode.
///
/// This exists so the app is useful in the first minute, before a multi-hundred
/// megabyte neural model has finished downloading. Accuracy and punctuation are
/// weaker than Nemotron's, so it is not the default.
actor AppleSpeechEngine: TranscriptionEngine {
    static let id = "apple"

    /// SFSpeechRecognizer stops listening on its own after roughly a minute.
    private static let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioRecorder.targetSampleRate,
        channels: 1,
        interleaved: false
    )

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private var preparation: EnginePreparation = .idle

    func prepare(progress: @escaping @Sendable (EnginePreparation) -> Void) async throws {
        if preparation.isReady { progress(.ready); return }
        preparation = .loading
        progress(preparation)

        let status = await Self.requestAuthorization()
        guard status == .authorized else {
            let message = "Speech Recognition permission was not granted."
            preparation = .failed(message)
            progress(preparation)
            throw TranscriptionEngineError.unsupported(message)
        }

        let locale = Locale(identifier: Preferences.shared.language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer() else {
            let message = "No recogniser is available for \(locale.identifier)."
            preparation = .failed(message)
            progress(preparation)
            throw TranscriptionEngineError.unsupported(message)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            let message = "macOS has no on-device recogniser installed for \(locale.identifier)."
            preparation = .failed(message)
            progress(preparation)
            throw TranscriptionEngineError.unsupported(message)
        }

        self.recognizer = recognizer
        preparation = .ready
        progress(preparation)
        Log.asr.info("Apple Speech ready (\(locale.identifier, privacy: .public))")
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    func beginUtterance(language: String) async throws {
        guard let recognizer else { throw TranscriptionEngineError.notReady }
        await cancelUtterance()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        latestTranscript = ""
        self.request = request
        // Partial results are tracked so that a recogniser which ends the task
        // early still leaves us with the best transcript it produced.
        self.task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            Task { await self.updateTranscript(text) }
        }
    }

    private func updateTranscript(_ text: String) {
        latestTranscript = text
    }

    func feed(_ samples: [Float]) async throws {
        guard let request, let format = Self.format else { return }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = buffer.floatChannelData else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel[0].update(from: source.baseAddress!, count: samples.count)
        }
        request.append(buffer)
    }

    func finishUtterance() async throws -> String {
        guard let request else { throw TranscriptionEngineError.notReady }
        request.endAudio()

        // Give the recogniser a brief window to emit its final hypothesis.
        // It reports completion through a callback with no async equivalent,
        // so settling is detected by the transcript going quiet.
        var previous = latestTranscript
        var stableRounds = 0
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(50))
            let current = latestTranscript
            if current == previous, !current.isEmpty {
                stableRounds += 1
                if stableRounds >= 2 { break }
            } else {
                stableRounds = 0
                previous = current
            }
        }

        let transcript = latestTranscript
        await cancelUtterance()
        return transcript
    }

    func cancelUtterance() async {
        task?.cancel()
        task = nil
        request = nil
    }

    func unload() async {
        await cancelUtterance()
        recognizer = nil
        preparation = .idle
    }
}

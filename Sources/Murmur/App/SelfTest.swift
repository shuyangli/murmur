import AVFoundation
import FluidAudio
import Foundation

/// Exercises the real transcription path from a wav file, so the engine and
/// audio plumbing can be verified without granting Accessibility or Input
/// Monitoring first.
///
/// Run with: `Murmur.app/Contents/MacOS/Murmur --selftest <file.wav> [engine]`
enum SelfTest {
    /// Mirrors the ~93 ms cadence the live microphone tap delivers, so the
    /// streaming engines see the same chunking they will see in real use.
    private static let chunkSamples = 1_500

    static var isRequested: Bool {
        CommandLine.arguments.contains("--selftest")
    }

    /// Mirrors the report to a file as well as stdout.
    ///
    /// Needed because engines that touch TCC-protected APIs only behave
    /// correctly when the app is launched through LaunchServices (`open`),
    /// which gives no way to capture standard output.
    private static let transcriptPath = ProcessInfo.processInfo.environment["MURMUR_SELFTEST_OUT"]
    private nonisolated(unsafe) static var collected = ""

    private static func emit(_ line: String) {
        print(line)
        guard let transcriptPath else { return }
        collected += line + "\n"
        try? collected.write(toFile: transcriptPath, atomically: true, encoding: .utf8)
    }

    static func run() async -> Never {
        // stdout is block-buffered when piped, which throws away every
        // diagnostic if the run ends in an abort rather than an exit.
        setvbuf(stdout, nil, _IONBF, 0)

        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--selftest"),
              arguments.count > flagIndex + 1
        else {
            FileHandle.standardError.write(Data("usage: Murmur --selftest <file.wav> [engine-id]\n".utf8))
            exit(2)
        }

        let audioURL = URL(fileURLWithPath: arguments[flagIndex + 1])
        let engineID = arguments.count > flagIndex + 2 ? arguments[flagIndex + 2] : Preferences.shared.engineID
        let descriptor = EngineRegistry.descriptor(for: engineID)
        let language = Preferences.shared.language

        emit("engine:   \(descriptor.name) [\(descriptor.id)]")
        emit("language: \(language)")
        emit("audio:    \(audioURL.lastPathComponent)")

        do {
            let samples = try AudioConverter(sampleRate: AudioRecorder.targetSampleRate)
                .resampleAudioFile(audioURL)
            let duration = Double(samples.count) / AudioRecorder.targetSampleRate
            emit("duration: \(String(format: "%.2f", duration))s (\(samples.count) samples)")

            let engine = descriptor.make()

            let loadStart = Date()
            try await engine.prepare { progress in
                if case .downloading(let fraction, let detail) = progress {
                    emit("  download \(Int(fraction * 100))% — \(detail)")
                }
            }
            emit("load:     \(String(format: "%.2f", Date().timeIntervalSince(loadStart)))s")

            try await engine.beginUtterance(language: language)

            // Feed in microphone-sized chunks, timing only the flush so the
            // number reported matches the latency the user actually feels on
            // key release.
            let feedStart = Date()
            var offset = 0
            while offset < samples.count {
                let end = min(offset + chunkSamples, samples.count)
                try await engine.feed(Array(samples[offset..<end]))
                offset = end
            }
            let feedElapsed = Date().timeIntervalSince(feedStart)

            let flushStart = Date()
            let text = try await engine.finishUtterance()
            let flushElapsed = Date().timeIntervalSince(flushStart)

            emit("stream:   \(String(format: "%.2f", feedElapsed))s while speaking")
            emit("flush:    \(String(format: "%.2f", flushElapsed))s after key release")
            emit("rtfx:     \(String(format: "%.1f", duration / max(feedElapsed + flushElapsed, 0.0001)))x")
            emit("---")
            emit(text)
            emit("---")

            await engine.unload()
            exit(text.isEmpty ? 1 : 0)
        } catch {
            emit("selftest failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}

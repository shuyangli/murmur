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

    static func run() async -> Never {
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

        print("engine:   \(descriptor.name) [\(descriptor.id)]")
        print("language: \(language)")
        print("audio:    \(audioURL.lastPathComponent)")

        do {
            let samples = try AudioConverter(sampleRate: AudioRecorder.targetSampleRate)
                .resampleAudioFile(audioURL)
            let duration = Double(samples.count) / AudioRecorder.targetSampleRate
            print("duration: \(String(format: "%.2f", duration))s (\(samples.count) samples)")

            let engine = descriptor.make()

            let loadStart = Date()
            try await engine.prepare { progress in
                if case .downloading(let fraction, let detail) = progress {
                    print("  download \(Int(fraction * 100))% — \(detail)")
                }
            }
            print("load:     \(String(format: "%.2f", Date().timeIntervalSince(loadStart)))s")

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

            print("stream:   \(String(format: "%.2f", feedElapsed))s while speaking")
            print("flush:    \(String(format: "%.2f", flushElapsed))s after key release")
            print("rtfx:     \(String(format: "%.1f", duration / max(feedElapsed + flushElapsed, 0.0001)))x")
            print("---")
            print(text)
            print("---")

            await engine.unload()
            exit(text.isEmpty ? 1 : 0)
        } catch {
            FileHandle.standardError.write(Data("selftest failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

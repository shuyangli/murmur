import AVFoundation
import FluidAudio
import Foundation

enum AudioRecorderError: LocalizedError {
    case noInputDevice
    case microphoneDenied
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone is available."
        case .microphoneDenied:
            return "Murmur needs microphone access. Grant it in System Settings › Privacy & Security › Microphone."
        case .engineFailed(let detail):
            return "The audio engine could not start: \(detail)"
        }
    }
}

/// Captures microphone audio and emits 16 kHz mono float samples.
///
/// Samples are delivered continuously while recording rather than buffered to
/// the end, so a streaming transcription engine can keep up with the speaker
/// and only has a final flush left to do on key release.
final class AudioRecorder: @unchecked Sendable {
    /// The sample rate every engine in this app expects.
    static let targetSampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let converter = AudioConverter(sampleRate: targetSampleRate)
    private let lock = NSLock()

    private var isRecording = false
    private var onSamples: (@Sendable ([Float]) -> Void)?
    /// Running peak level in 0...1, for the recording indicator.
    private var currentLevel: Float = 0

    /// Number of input frames per tap callback. ~93 ms at 44.1 kHz, which keeps
    /// the engine fed without waking the audio thread excessively.
    private static let tapBufferSize: AVAudioFrameCount = 4096

    init() {
        // Building the render graph up front makes the eventual start() fast,
        // which matters because recording begins on a key press.
        engine.prepare()
    }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static var permissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return currentLevel
    }

    func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws {
        lock.lock()
        let alreadyRecording = isRecording
        if !alreadyRecording {
            self.onSamples = onSamples
            isRecording = true
            currentLevel = 0
        }
        lock.unlock()
        guard !alreadyRecording else { return }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            reset()
            throw AudioRecorderError.microphoneDenied
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            reset()
            throw AudioRecorderError.noInputDevice
        }

        input.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format) { [weak self] buffer, _ in
            self?.handle(buffer: buffer)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            reset()
            throw AudioRecorderError.engineFailed(error.localizedDescription)
        }
    }

    func stop() {
        lock.lock()
        let wasRecording = isRecording
        isRecording = false
        onSamples = nil
        currentLevel = 0
        lock.unlock()
        guard wasRecording else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Keep the graph warm for the next press.
        engine.prepare()
    }

    private func reset() {
        lock.lock()
        isRecording = false
        onSamples = nil
        lock.unlock()
    }

    /// Runs on the real-time audio thread; keep the work here bounded.
    private func handle(buffer: AVAudioPCMBuffer) {
        lock.lock()
        let callback = isRecording ? onSamples : nil
        lock.unlock()
        guard let callback else { return }

        let samples: [Float]
        do {
            samples = try converter.resampleBuffer(buffer)
        } catch {
            Log.audio.error("Resample failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !samples.isEmpty else { return }

        var peak: Float = 0
        for sample in samples {
            peak = max(peak, abs(sample))
        }
        lock.lock()
        // Decay slowly so the meter reads smoothly rather than flickering.
        currentLevel = max(peak, currentLevel * 0.82)
        lock.unlock()

        callback(samples)
    }
}

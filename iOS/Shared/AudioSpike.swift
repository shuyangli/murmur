import AVFoundation
import Foundation
import os

/// What one press-and-hold produced. Every field exists to separate outcomes
/// the brief treats as one: a session that never opens, a session that opens
/// but yields no engine, and an engine that runs but hears silence all fail
/// differently and point at different fixes.
struct SpikeReport {
    var buffers = 0
    var frames: Int64 = 0
    var peak: Float = 0
    var elapsed: TimeInterval = 0
    var startLatency: TimeInterval = 0
    var format = "—"
    var engineFormat = "—"
    var route = "—"
    var highQuality = "—"

    var microphone = "—"
    var inputAvailable = false
    var inputChannels = 0

    /// One line per session recipe tried, in order.
    var ladder: [String] = []
    /// Name of the recipe whose engine started, if any.
    var recipe: String?

    /// Only populated when every recipe fails: does a different capture API
    /// get audio where AVAudioEngine could not?
    var captureProbe: String?

    var passed: Bool { recipe != nil && buffers > 0 }

    /// Rendered identically in the app and the keyboard — the whole point of
    /// the control run is comparing two of these line for line.
    func summary(host: String, fullAccess: Bool?) -> String {
        var lines = [passed ? "PASS — buffers arrived" : "FAIL", "", "host         \(host)"]
        if let fullAccess {
            lines.append("full access  \(fullAccess ? "on" : "OFF")")
        }
        lines.append("mic perm     \(microphone)")
        lines.append("")
        lines.append("session recipes tried:")
        lines.append(contentsOf: ladder)
        lines.append("")
        lines.append(contentsOf: [
            "recipe       \(recipe ?? "none started")",
            "input        \(inputAvailable ? "available" : "unavailable"), \(inputChannels) ch",
            String(format: "buffers      %d in %.2f s", buffers, elapsed),
            "frames       \(frames)",
            String(format: "peak         %.4f%@", peak, peak > 0 ? "" : "  (silence)"),
            String(format: "start        %.0f ms", startLatency * 1000),
            "session fmt  \(format)",
            "engine fmt   \(engineFormat)",
            "route        \(route)",
            "hi-qual BT   \(highQuality)",
        ])
        if let captureProbe {
            lines.append("capture API  \(captureProbe)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Step 0 of docs/ios.md: can a keyboard extension record? Everything else in
/// the iOS design is downstream of the answer.
final class AudioSpike {
    private static let log = Logger(subsystem: "com.shuyangli.murmur", category: "spike")

    /// 4096 frames is ~85 ms at 48 kHz — long enough that a short press yields
    /// a countable number of buffers, short enough to notice a stall.
    private static let tapBufferSize: AVAudioFrameCount = 4096

    /// 561145187 == '!rec'. The forum thread the brief cites is entirely about
    /// this one code, so it gets named rather than printed as a number.
    private static let cannotStartRecording = 561145187

    private var engine: AVAudioEngine?
    /// Built before any session configuration, on purpose. See the recipe
    /// that uses it.
    private let preBuiltEngine = AVAudioEngine()
    private let counters = OSAllocatedUnfairLock(initialState: Counters())
    private var report = SpikeReport()
    private var startedAt: Date?
    private var probe: CaptureProbe?

    private struct Counters {
        var buffers = 0
        var frames: Int64 = 0
        var peak: Float = 0
    }

    func start() {
        report = SpikeReport()
        counters.withLock { $0 = Counters() }
        let began = Date()

        report.microphone = Self.describePermission()

        // The brief asks whether these options compose, and an activated
        // session does not answer it: the I/O unit only refuses at
        // engine.start(). Walk down from the configuration the design wants
        // to the barest one that could work, and keep the first that runs.
        for recipe in SessionRecipe.ladder {
            switch attempt(recipe) {
            case .success(let engine):
                self.engine = engine
                report.ladder.append("  \(recipe.name) — started")
                report.recipe = recipe.name
                startedAt = Date()
                report.startLatency = Date().timeIntervalSince(began)
                describeActiveSession()
                return
            case .failure(let reason):
                report.ladder.append("  \(recipe.name) — \(reason)")
                Self.log.error("\(recipe.name, privacy: .public): \(reason, privacy: .public)")
            }
        }

        // Nothing started. Leave the last session active so the probe tests
        // the same situation the engine just failed in.
        startProbe()
    }

    private enum Attempt {
        case success(AVAudioEngine)
        case failure(String)
    }

    private func attempt(_ recipe: SessionRecipe) -> Attempt {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        do {
            try session.setCategory(recipe.category, mode: recipe.mode, options: recipe.options)
            try session.setPrefersNoInterruptionsFromSystemAlerts(true)
            try session.setActive(true)
        } catch {
            return .failure("session " + Self.describe(error))
        }
        describeActiveSession()

        // A fresh engine each time: one that failed to start holds onto the
        // configuration that failed. The exception is the recipe that exists
        // to test the opposite ordering.
        let engine = recipe.usePreBuiltEngine ? preBuiltEngine : AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        report.engineFormat = String(
            format: "%.0f Hz, %d ch",
            format.sampleRate,
            format.channelCount
        )
        guard format.sampleRate > 0 else {
            return .failure("input node has no format (sample rate 0)")
        }

        input.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: format) { [counters] buffer, _ in
            let peak = Self.peak(of: buffer)
            counters.withLock {
                $0.buffers += 1
                $0.frames += Int64(buffer.frameLength)
                $0.peak = max($0.peak, peak)
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return .failure("engine " + Self.describe(error))
        }
        return .success(engine)
    }

    private func describeActiveSession() {
        let session = AVAudioSession.sharedInstance()
        report.route = Self.describeRoute(session)
        report.inputAvailable = session.isInputAvailable
        report.inputChannels = session.inputNumberOfChannels
        // Read while the session is live: the capability reports isEnabled
        // only against an active route, and stop() tears that route down.
        report.highQuality = Self.describeHighQuality(session)
        report.format = String(
            format: "%.0f Hz, %d ch",
            session.sampleRate,
            session.inputNumberOfChannels
        )
    }

    func stop() -> SpikeReport {
        if let startedAt {
            report.elapsed = Date().timeIntervalSince(startedAt)
        }
        startedAt = nil

        if let engine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil

        if let probe {
            report.captureProbe = probe.finish()
            self.probe = nil
        }
        deactivate()

        let counts = counters.withLock { $0 }
        report.buffers = counts.buffers
        report.frames = counts.frames
        report.peak = counts.peak
        Self.log.notice("recipe=\(self.report.recipe ?? "none", privacy: .public) buffers=\(counts.buffers)")
        return report
    }

    /// AVAudioEngine drives a RemoteIO audio unit; AVCaptureSession takes a
    /// different path to the same microphone. If the engine is refused and the
    /// capture session is not, the extension is not blocked from recording —
    /// only from this one API, and the design survives with a different
    /// buffer source.
    private func startProbe() {
        let probe = CaptureProbe()
        probe.start()
        self.probe = probe
    }

    private func deactivate() {
        // Leaving the session active keeps other apps' audio mixed against a
        // recorder that is no longer recording.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        var peak: Float = 0
        for frame in 0..<Int(buffer.frameLength) {
            peak = max(peak, abs(channel[frame]))
        }
        return peak
    }

    private static func describePermission() -> String {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: "granted"
        case .denied: "DENIED"
        case .undetermined: "UNDETERMINED"
        @unknown default: "unknown"
        }
    }

    private static func describeRoute(_ session: AVAudioSession) -> String {
        let inputs = session.currentRoute.inputs
        guard !inputs.isEmpty else { return "no input port" }
        return inputs.map { "\($0.portType.rawValue) (\($0.portName))" }.joined(separator: ", ")
    }

    private static func describeHighQuality(_ session: AVAudioSession) -> String {
        guard let input = session.currentRoute.inputs.first else { return "no input port" }
        guard let bluetooth = input.bluetoothMicrophoneExtension else { return "not a Bluetooth mic" }
        let capability = bluetooth.highQualityRecording
        return "supported \(capability.isSupported), enabled \(capability.isEnabled)"
    }

    /// Core Audio packs failures into an OSStatus as four characters, so the
    /// number alone is unreadable. Unpack it, and name the two codes this
    /// spike exists to tell apart.
    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "\(nsError.domain) \(nsError.code)"
        if let code = fourCharCode(nsError.code) {
            text += " ('\(code)')"
        }
        switch nsError.code {
        case cannotStartRecording: text += " — cannot start recording"
        case Int(AVAudioSession.ErrorCode.unspecified.rawValue): text += " — unspecified"
        default: break
        }
        return text
    }

    private static func fourCharCode(_ code: Int) -> String? {
        guard code > 0, code <= Int(UInt32.max) else { return nil }
        let value = UInt32(code)
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return nil }
        return String(bytes: bytes, encoding: .ascii)
    }
}

/// The session configurations to try, richest first. Each rung drops one
/// thing the design wants, so the first that starts names the cost of making
/// audio work at all inside a keyboard extension.
struct SessionRecipe {
    let name: String
    let category: AVAudioSession.Category
    let mode: AVAudioSession.Mode
    let options: AVAudioSession.CategoryOptions
    /// WhisperBoard holds its engine as a stored property, so the engine is
    /// constructed before any session configuration. Whether that ordering
    /// matters is otherwise untestable.
    var usePreBuiltEngine = false

    static let ladder: [SessionRecipe] = [
        SessionRecipe(
            name: "brief (mix + hi-qual BT + HFP)",
            category: .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .bluetoothHighQualityRecording, .allowBluetoothHFP]
        ),
        SessionRecipe(
            name: "no hi-qual BT",
            category: .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .allowBluetoothHFP]
        ),
        SessionRecipe(
            name: "mix only",
            category: .playAndRecord,
            mode: .default,
            options: [.mixWithOthers]
        ),
        SessionRecipe(
            name: "bare playAndRecord",
            category: .playAndRecord,
            mode: .default,
            options: []
        ),
        // .record silences other audio by design — the brief rules it out for
        // shipping, but if only this starts, the cause is the category.
        SessionRecipe(name: "record", category: .record, mode: .default, options: []),
        SessionRecipe(name: "record + measurement", category: .record, mode: .measurement, options: []),
        // Exactly what WhisperBoard does — the brief cites it as capturing
        // in-extension today, so matching it is the strongest available test.
        SessionRecipe(
            name: "whisperboard (defaultToSpeaker)",
            category: .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker]
        ),
        SessionRecipe(
            name: "whisperboard + engine built at init",
            category: .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker],
            usePreBuiltEngine: true
        ),
    ]
}

/// Counts sample buffers from an AVCaptureSession. Deliberately minimal: it
/// only has to answer whether audio arrives at all.
private final class CaptureProbe: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.shuyangli.murmur.keyboard.probe")
    private let received = OSAllocatedUnfairLock(initialState: 0)
    private var setupError: String?

    func start() {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            setupError = "no audio capture device"
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                setupError = "cannot add audio input"
                return
            }
            session.addInput(input)
        } catch {
            setupError = (error as NSError).description
            return
        }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            setupError = "cannot add audio output"
            return
        }
        session.addOutput(output)

        // startRunning() blocks; keeping it off the main thread keeps the
        // keyboard responsive while the probe spins up.
        queue.async { [session] in session.startRunning() }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        received.withLock { $0 += 1 }
    }

    func finish() -> String {
        let running = session.isRunning
        session.stopRunning()
        if let setupError { return setupError }
        let count = received.withLock { $0 }
        return "\(count) sample buffers, session \(running ? "running" : "not running")"
    }
}

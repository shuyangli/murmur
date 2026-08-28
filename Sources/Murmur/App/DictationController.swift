import AppKit
import Combine
import Foundation
import MurmurCore

enum DictationState: Equatable {
    case idle
    case recording
    case transcribing
    case notice(String)
    case failure(String)

    var isRecording: Bool { self == .recording }
}

/// Owns the press-to-talk pipeline: key down starts capture, audio streams into
/// the engine while the user speaks, and key up flushes and delivers the text.
@MainActor
final class DictationController: ObservableObject {
    @Published private(set) var state: DictationState = .idle
    @Published private(set) var enginePreparation: EnginePreparation = .idle
    @Published private(set) var hotkeyActive = false
    @Published private(set) var level: Float = 0

    static let shared = DictationController()

    let history: HistoryStore
    private let preferences: Preferences
    private let recorder = AudioRecorder()
    private var monitor: HotkeyMonitor

    private var engine: (any TranscriptionEngine)?
    private var loadedEngineID: String?
    /// Built on first use; most users never turn the polish pass on.
    private var polisherStorage: AnyObject?

    /// Feeds captured audio into the engine in order, without blocking the
    /// audio thread on the engine actor.
    private var sampleContinuation: AsyncStream<[Float]>.Continuation?
    private var pipelineTask: Task<Void, Never>?

    private var recordingStartedAt: Date?
    private var targetBundleID: String?
    private var levelTimer: Timer?
    private var noticeResetTask: Task<Void, Never>?

    /// How long a transient message stays on screen before clearing.
    private static let noticeDuration = Duration.seconds(2.5)
    private static let levelPollInterval: TimeInterval = 1.0 / 30.0

    init(preferences: Preferences = .shared) {
        self.preferences = preferences
        self.history = HistoryStore(limitProvider: { preferences.historyLimit })
        self.monitor = HotkeyMonitor(triggerKey: preferences.triggerKey)
        monitor.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    // MARK: - Lifecycle

    func start() {
        recorder.warmUp()
        hotkeyActive = monitor.start()
        if !hotkeyActive {
            state = .failure("Input Monitoring permission is needed to see the trigger key.")
        }
        Task { await prepareEngine() }
    }

    func stop() {
        monitor.stop()
        hotkeyActive = false
    }

    func restartHotkeyMonitor() {
        monitor.stop()
        monitor.setTriggerKey(preferences.triggerKey)
        hotkeyActive = monitor.start()
    }

    /// Tears down the current engine and loads whichever one preferences name.
    func reloadEngine() async {
        let previous = engine
        engine = nil
        loadedEngineID = nil
        enginePreparation = .idle
        await previous?.unload()
        await prepareEngine()
    }

    func prepareEngine() async {
        let descriptor = EngineRegistry.descriptor(for: preferences.engineID)
        if loadedEngineID == descriptor.id, enginePreparation.isReady { return }

        let engine = self.engine ?? descriptor.make()
        self.engine = engine
        loadedEngineID = descriptor.id

        do {
            try await engine.prepare { [weak self] progress in
                Task { @MainActor in self?.enginePreparation = progress }
            }
        } catch {
            enginePreparation = .failed(error.localizedDescription)
            Log.asr.error("Engine prepare failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Hotkey handling

    private func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case .pressed: beginRecording()
        case .released: endRecording(commit: true)
        case .cancelled: endRecording(commit: false)
        }
    }

    private func beginRecording() {
        guard state != .recording else { return }

        // The engine holds one utterance at a time, so starting a new one
        // while the previous flush is still in flight would reset the decoder
        // out from under it and lose the transcript.
        guard state != .transcribing else {
            Log.asr.info("Ignored a key press that arrived during the previous flush.")
            return
        }

        guard let engine, enginePreparation.isReady else {
            // Pressing the key is the only moment the user cares how far along
            // the download is, so the progress is reported here rather than
            // anywhere they would have to go looking for it.
            switch enginePreparation {
            case .downloading(let fraction, _):
                showNotice("Downloading the speech model — \(Int(fraction * 100))%")
            case .loading:
                showNotice("Loading the speech model…")
            case .failed(let message):
                showFailure(message)
            case .idle, .ready:
                showNotice("Getting the speech model ready…")
                Task { await prepareEngine() }
            }
            return
        }

        guard Permissions.microphoneGranted else {
            showNotice("Microphone access is required.")
            Task { [recorder] in
                guard await AudioRecorder.requestPermission() else { return }
                // Now that an input device is reachable, build the graph so the
                // next press starts recording without the setup cost.
                recorder.warmUp()
            }
            return
        }

        // Record the paste target now: our own overlay must not become the
        // frontmost app between here and delivery, but read it early anyway.
        targetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let language = preferences.language
        let (stream, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        sampleContinuation = continuation

        pipelineTask = Task {
            do {
                try await engine.beginUtterance(language: language)
                for await chunk in stream {
                    try await engine.feed(chunk)
                }
            } catch {
                Log.asr.error("Feed failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            // Capture the continuation directly: it is Sendable, whereas
            // reaching back through self would cross the main actor on every
            // buffer delivered from the audio thread.
            try recorder.start { samples in
                continuation.yield(samples)
            }
        } catch {
            continuation.finish()
            sampleContinuation = nil
            pipelineTask?.cancel()
            pipelineTask = nil
            showFailure(error.localizedDescription)
            return
        }

        recordingStartedAt = Date()
        state = .recording
        startLevelPolling()
        playSound(.start)
    }

    private func endRecording(commit: Bool) {
        guard state == .recording else { return }

        recorder.stop()
        stopLevelPolling()
        sampleContinuation?.finish()
        sampleContinuation = nil

        let duration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil

        let tooShort = duration < preferences.minimumRecordingSeconds
        guard commit, !tooShort else {
            discardUtterance()
            if tooShort && commit { state = .idle }
            return
        }

        state = .transcribing
        let engine = self.engine
        let target = targetBundleID
        let engineID = loadedEngineID ?? preferences.engineID
        let pipeline = pipelineTask
        pipelineTask = nil

        Task {
            await pipeline?.value
            let startedAt = Date()
            do {
                guard let engine else { throw TranscriptionEngineError.notReady }
                let raw = try await engine.finishUtterance()
                let text = await cleanUp(raw)
                let elapsed = Date().timeIntervalSince(startedAt)

                guard !text.isEmpty else {
                    showNotice("Nothing was heard.")
                    playSound(.empty)
                    return
                }

                await TextInjector.deliver(
                    text,
                    mode: preferences.outputMode,
                    restoreClipboard: preferences.restoreClipboard
                )

                history.add(HistoryEntry(
                    text: text,
                    audioDuration: duration,
                    transcriptionDuration: elapsed,
                    engineID: engineID,
                    targetApplication: target
                ))

                state = .idle
                playSound(.success)
                Log.asr.info("Transcribed \(duration, format: .fixed(precision: 1))s in \(elapsed, format: .fixed(precision: 2))s")
            } catch {
                showFailure(error.localizedDescription)
                playSound(.failure)
            }
        }
    }

    @available(macOS 26.0, *)
    private var polisher: TextPolisher? {
        get { polisherStorage as? TextPolisher }
        set { polisherStorage = newValue }
    }

    /// Runs the transcript through the cleanup passes the user has enabled.
    ///
    /// The deterministic filter always runs first so the language model, if it
    /// is on at all, gets tidier input and has less to do.
    private func cleanUp(_ raw: String) async -> String {
        var text = preferences.trimTrailingWhitespace
            ? raw.trimmingCharacters(in: .whitespacesAndNewlines)
            : raw

        text = FillerFilter.clean(
            text,
            options: FillerFilter.Options(
                removeFillers: preferences.removeFillers,
                removeDiscourseMarkers: preferences.removeDiscourseMarkers
            )
        )

        guard preferences.polishWithLanguageModel, !text.isEmpty else { return text }
        guard #available(macOS 26.0, *) else { return text }

        let polisher = self.polisher ?? TextPolisher()
        self.polisher = polisher
        return await polisher.polish(text)
    }

    private func discardUtterance() {
        let engine = self.engine
        let pipeline = pipelineTask
        pipelineTask = nil
        Task {
            await pipeline?.value
            await engine?.cancelUtterance()
        }
        state = .idle
    }

    // MARK: - Manual control, for the menu bar

    func cancelActiveRecording() {
        guard state == .recording else { return }
        endRecording(commit: false)
    }

    // MARK: - Level metering

    private func startLevelPolling() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: Self.levelPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.level = self.recorder.level
            }
        }
    }

    private func stopLevelPolling() {
        levelTimer?.invalidate()
        levelTimer = nil
        level = 0
    }

    // MARK: - Feedback

    private func showNotice(_ message: String) {
        state = .notice(message)
        scheduleStateReset()
    }

    private func showFailure(_ message: String) {
        state = .failure(message)
        Log.app.error("\(message, privacy: .public)")
        scheduleStateReset()
    }

    private func scheduleStateReset() {
        noticeResetTask?.cancel()
        noticeResetTask = Task {
            try? await Task.sleep(for: Self.noticeDuration)
            guard !Task.isCancelled else { return }
            if case .recording = state { return }
            if case .transcribing = state { return }
            state = .idle
        }
    }

    private enum Feedback: String {
        case start = "Tink"
        case success = "Pop"
        case empty = "Morse"
        case failure = "Basso"
    }

    private func playSound(_ feedback: Feedback) {
        guard preferences.playFeedbackSounds else { return }
        NSSound(named: feedback.rawValue)?.play()
    }
}

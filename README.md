# Murmur

Press-to-talk dictation for macOS. Hold a key, speak, let go, and the text lands
in whatever you were typing in. Everything runs on your Mac — the models are
downloaded once and nothing you say ever leaves the machine.

## Build and install

```bash
./build.sh --install --run
```

That compiles in release mode, assembles `Murmur.app`, signs it with your Apple
Development identity, copies it to `/Applications`, and launches it. Without
flags it just builds into `dist/`.

Signing with a real identity matters: macOS ties the Accessibility and Input
Monitoring grants to the app's code signature, so an ad-hoc signature would make
you re-approve both after every rebuild.

## First run

Murmur lives in the menu bar. On first launch it needs three permissions, all
listed with **Grant** buttons under **Settings › Permissions**:

| Permission | Why |
| --- | --- |
| Input Monitoring | See the trigger key while you are in another app |
| Accessibility | Paste the transcript into the focused app |
| Microphone | Hear you |

After granting Input Monitoring, quit and reopen Murmur — macOS only re-reads
that grant at launch.

The first dictation also downloads the speech model (~700 MB). Press the trigger
key and the on-screen readout tells you how far along it is. Until it finishes
you can switch to the **Apple Speech** engine in Settings, which uses the
recogniser macOS already ships.

To have Murmur start with your Mac, turn on **Open Murmur at login** under
**Settings › General › Behaviour**.

### If you use the Globe key

Set **System Settings › Keyboard › Press 🌐 key to** to **Do Nothing**.
Otherwise macOS also switches your input source or opens the emoji picker every
time you dictate. Murmur warns you in the menu when it detects this. If you would
rather leave the Globe key alone, pick a different trigger in Settings — right
Option, Command, Control, and Shift all work.

## How it works

```
Fn down ──▶ AVAudioEngine tap ──▶ 16 kHz mono ──▶ engine.feed()   (while you speak)
Fn up   ──▶ engine.finishUtterance() ──▶ paste ──▶ history
```

The default engine, NVIDIA Nemotron 3.5 ASR, is a genuinely streaming model, so
audio is decoded *while you are still talking*. By the time you release the key
only the last partial chunk is left to flush. On an M1 Pro that flush measures
about **70 ms**, which is what makes the result feel immediate rather than
merely fast.

Text is delivered by putting it on the pasteboard and synthesising ⌘V, then
restoring your previous clipboard a moment later. Pasting beats typing the
characters one by one: it is instant regardless of length and survives apps that
debounce rapid synthetic key events.

## Swapping the model

Engines implement one small protocol in
[`TranscriptionEngine.swift`](Sources/Murmur/Transcription/TranscriptionEngine.swift):

```swift
protocol TranscriptionEngine: AnyObject, Sendable {
    func prepare(progress: @escaping @Sendable (EnginePreparation) -> Void) async throws
    func beginUtterance(language: String) async throws
    func feed(_ samples: [Float]) async throws        // 16 kHz mono
    func finishUtterance() async throws -> String
    func cancelUtterance() async
    func unload() async
}
```

It is utterance-shaped and streaming-first. A model that can only work in batch
just accumulates in `feed` and does the work in `finishUtterance` — that is
exactly what the Parakeet engine does.

To add one: write the actor, then add an `EngineDescriptor` to `EngineRegistry.all`.
It appears in the Settings picker automatically.

Three ship today:

| Engine | Notes | Measured on an M1 Pro |
| --- | --- | --- |
| **Nemotron 3.5 ASR** (default) | Streaming, 0.6B, 40 languages, punctuates as it goes | 0.07 s flush after key release |
| **Parakeet TDT v3** | Batch, 0.6B, 25 languages | 0.14 s after key release |
| **Apple Speech** | Built into macOS, nothing to download | Varies; weakest punctuation |

Both NVIDIA models run on the Neural Engine through
[FluidAudio](https://github.com/FluidInference/FluidAudio).

## History

Every dictation is kept in `~/Library/Application Support/Murmur/history.json`,
newest first, capped at a number you set in Settings (default 100). It is plain
JSON and entirely disposable — delete the file any time; the app treats a
missing or corrupt file as an empty history rather than an error.

Open the window from the menu bar to search, copy, or delete entries.

## Checking on it

```bash
./dist/Murmur.app/Contents/MacOS/Murmur --diagnose
```

Prints permissions, the trigger key, the Globe-key conflict check, and where
history lives. Run from a terminal the permission rows may reflect the
*terminal's* grants rather than Murmur's, because that is how macOS attributes
TCC checks to a child process — Settings › Permissions inside the app is
authoritative.

To exercise the transcription path against a recording:

```bash
say -o /tmp/speech.wav --data-format=LEF32@16000 "testing one two three"
./dist/Murmur.app/Contents/MacOS/Murmur --selftest /tmp/speech.wav nemotron
```

This reports load time, streaming time, flush latency, and the transcript. It
needs no permissions, which makes it the quickest way to tell a model problem
apart from a permissions problem.

## Layout

```
Sources/Murmur/
├── App/            DictationController — the press-to-talk state machine
├── Hotkey/         CGEventTap watching for the trigger key
├── Audio/          AVAudioEngine capture, resampled to 16 kHz mono
├── Transcription/  The engine protocol and its three implementations
├── Output/         Pasteboard + synthesised ⌘V
├── History/        JSON-backed log
├── Support/        Preferences, permissions, login item, logging
└── UI/             Menu bar, history window, settings, recording overlay
```

## Where the app talks to you

The status item is a plain `NSMenu` — recent dictations, history, settings,
quit. It carries no status or progress, because nobody watches the menu bar
while they wait for something.

Everything time-sensitive goes to the floating readout above the Dock instead:
the level meter while you speak, "Transcribing", and any reason a press did not
work ("Downloading the speech model — 62%", "Microphone access is required").
That panel is non-activating, so it never takes keyboard focus from the app you
are dictating into.

The one exception lives in the menu: if Input Monitoring is off, the trigger key
is never seen at all, so there is no press that could raise the readout. That
case gets a menu item.

## Known limits

- The Fn/Globe key cannot be *suppressed*, only observed, so its system action
  has to be turned off in System Settings rather than by the app.
- Holding the trigger during a previous flush is ignored rather than queued;
  the window is about 70 ms.
- The app target builds in Swift 5 language mode. The real-time audio callback
  and the C event-tap callback both cross isolation boundaries in ways Swift 6
  strict concurrency cannot express without more ceremony than they warrant.

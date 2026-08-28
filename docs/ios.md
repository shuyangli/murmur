# Murmur for iOS — build brief

Press-and-hold dictation on iPhone: hold a key, speak, release, text lands in the
field you were already typing in. Nothing built yet. This is the brief.

Target: **iOS 26+**. Everything below depends on APIs that shipped in it.

## Why this shape

The two things wrong with existing dictation keyboards are constraints showing
through, and iOS 26 lifted both.

| Problem | Cause | Fix |
| --- | --- | --- |
| Container app must stay alive in background | Keyboard extensions cap at ~50 MB; Whisper-class models don't fit, so the extension hands audio off | `SpeechTranscriber` runs its model in a **system process** — "operates outside of your application's memory space" (WWDC25 §277). The extension transcribes for itself. |
| Music on AirPods degrades while speaking | Any active input route forces Bluetooth A2DP → HFP | `AVAudioSession.CategoryOptions.bluetoothHighQualityRecording` |

Output is simpler than macOS: the keyboard owns the text connection, so
`textDocumentProxy.insertText` replaces the pasteboard + synthesised ⌘V +
clipboard restore. No iOS port of `TextInjector.swift` is needed.

## Step 0 — spike this before writing anything else

**The whole design assumes a keyboard extension can open a recording session.
That is unverified.** Developers hit `561145187` (`!rec`, "cannot start
recording"). [An Apple engineer's answer](https://developer.apple.com/forums/thread/775077)
is that the extension needs both settings below; the thread has no confirmed
resolution, and `hasDictationKey` is documented only as suppressing the system
dictation button — that it gates the audio session is undocumented.

Build an empty keyboard extension with:

1. `RequestsOpenAccess = true` in the extension's `NSExtensionAttributes`
2. `hasDictationKey = true` on the `UIInputViewController` subclass
3. `NSMicrophoneUsageDescription` present
4. Full Access enabled in Settings, microphone already granted via the container app

Start `AVAudioEngine` on touch-down, print the tap's buffer count.

- **Physical device only** — the simulator has no audio input.
- **Pass:** buffers arrive → proceed with everything below.
- **Fail (`!rec`):** stop, file a Feedback Assistant report, take the fallback.

Report the result before building further. Roughly 30 minutes.

## Step 0 result — failed, 28 Aug 2026

Measured on an iPhone 16 Pro, iOS 26.6.1, Xcode 26.6, from the harness in
`iOS/`. **A keyboard extension cannot record.** The design above does not
survive it.

The failure is not the one this brief predicted, and the difference matters.

| | Expected | Measured |
| --- | --- | --- |
| Where it fails | `setActive` | `AVAudioEngine.start()` |
| Error | `561145187` (`!rec`) | `2003329396` (`'what'`, `AVAudioSessionErrorCodeUnspecified`) |
| Fix by `RequestsOpenAccess` + `hasDictationKey` | suspected | both set; session activates; still fails |

With Full Access on and the microphone granted, the extension's session
activates, resolves `MicrophoneBuiltIn`, and reports 48000 Hz mono — the same
route and format as the container app. Then the I/O unit refuses to start.

Eight session configurations were tried on each press, from the full option set
above down to bare `.record` with `.measurement`. All eight failed identically.
An `AVCaptureSession` against the same microphone also never ran, so this is not
one API's path — it is a blanket denial of audio input.

`mediaserverd` names the mechanism, captured from this device in Console:

```
-CMSUtilities- CMSUtility_IsAllowedToStartRecording: Client sid:0x40e3d53,
MurmurKeyboard(82492), 'prim' with PID 82492 was NOT allowed to start recording
because it is an extension and doesn't have entitlements to record audio.
```

The gate is on being an extension, not on the session, the category, or the
capture API — which is why the session activates and every configuration then
fails at `kAUStartIO`.

No shipping counterexample survives inspection either. WhisperBoard, cited in
the sources below, turns out to record in its container app.

**The control is what makes this conclusive.** The same `AudioSpike` code,
compiled into the container app, passes on the first rung: 21 buffers in 2.15 s,
peak 0.68. Same device, same minute. The spike is correct; the extension is
refused.

Do not repeat this measurement without a control run. Three rounds were spent
narrowing toward an extension-specific cause before checking that the code
worked anywhere at all.

**This may be a bug rather than policy, and the distinction is unresolved.**
[Configuring open access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
lists "No access to microphone and speaker" only among the restrictions on a
keyboard *without* open access, then says an open access keyboard "has all the
capabilities in the preceding list" and never restates the restriction. In
[the forum thread](https://developer.apple.com/forums/thread/775077) an Apple
engineer's first suggestion is to configure open access and indicate dictation
support — this build does both, verified at runtime, and is still refused. The
archived App Extension Programming Guide flatly denies microphone access to all
extensions, but dates that claim to iOS 8.0. FB16791704 tracks the discrepancy.

## Targets

```
MurmurKit (framework, iOS)   ← Sources/MurmurCore, compiles unchanged
Murmur (app)                 ← onboarding, mic grant, model download, history
MurmurKeyboard (extension)   ← the whole dictation path
```

App and extension share an App Group for settings and history only — **not** for
audio. No Darwin notifications, no background container app.

## Audio session

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(
    .playAndRecord,
    mode: .default,
    options: [.mixWithOthers, .bluetoothHighQualityRecording, .allowBluetoothHFP]
)
try session.setPrefersNoInterruptionsFromSystemAlerts(true)
try session.setActive(true)
```

Every option is load-bearing, and there are three traps:

- **`.default` mode is mandatory.** High-quality recording is only available in
  it. `.measurement` and `.voiceChat` — the reflexive picks for dictation —
  silently forfeit it.
- **Not supported in the EU.** Query, don't assume:
  ```swift
  session.currentRoute.inputs.first?
      .bluetoothMicrophoneExtension?.highQualityRecording.isSupported
  ```
  Log the result and surface it in Settings. `.allowBluetoothHFP` is the
  documented fallback route.
- **`.mixWithOthers` is what keeps music playing** rather than interrupted or
  ducked. Don't use `.record` — it silences other audio by design and doesn't
  accept the option.

High-quality recording may add input latency; measure it (see acceptance tests).

## Transcription

`SpeechAnalyzer` + `SpeechTranscriber`, fed an `AsyncSequence` of buffers.
**Volatile results** drive the live readout — same idea as Nemotron's per-chunk
transcripts on macOS, but with no chunk-rate tradeoff to configure.

Tier by availability, the way `EngineRegistry` tiers the Mac's three engines:

| Module | When |
| --- | --- |
| `SpeechTranscriber` | Default. Check `isAvailable` — it has hardware requirements. |
| `DictationTranscriber` | Fallback for older devices. Same models as system dictation, no extra hardware requirement. |

Assets download once via `AssetInventory.assetInstallationRequest(supporting:)` —
container app's job, at onboarding. No model ships in the binary. Deallocate
locales on the way out. Do **not** port Nemotron or Parakeet; FluidAudio's CoreML
models are exactly what doesn't fit.

## Reuse from the Mac app

`MurmurCore` is AppKit-free and compiles for iOS as-is:

- `FillerFilter` — run it, same as macOS
- `SubtitleText` — trims to recent words; ideal for a two-line keyboard readout
- `RewriteValidator` — only if the rewrite pass ships
- `ModelNaming` — partly; asset naming is Apple's now

**Ship `TextPolisher`'s `FoundationModels` rewrite off, or not at all in v1.** It
costs 0.7–1.5 s on a Mac and would run inside a memory-capped extension.

Nothing in `Hotkey/`, `Output/`, `Support/Permissions.swift`, or
`Support/LoginItem.swift` ports — all macOS-only concepts.

## Keyboard UI

Normal QWERTY layout with a press-and-hold key sized like a spacebar.

- Touch down → capture; touch up → finalize, filter, `insertText`
- Short upward slide latches recording on, with an obvious way out (holding for
  two minutes on a phone is unpleasant)
- Drag off and release cancels, matching every other iOS control
- Haptics on start/stop — you're watching the text field, not the button
- Live transcript renders in the keyboard's own view

## Acceptance tests

1. **Play music on AirPods, dictate mid-song.** Music must keep playing and must
   not audibly degrade. This is the whole point — if it fails, the design failed.
2. **Force-quit the container app, then dictate.** Must work. If it needs the app
   alive, the design failed.
3. Measure flush latency from release to `insertText`; compare against the Mac's
   ~70 ms. Add a `--selftest` equivalent so "immediate" is a number.
4. Confirm no network entitlement on the extension.

## Full Access

Required, and iOS shows a blunt warning that the keyboard may transmit everything
you type. For Murmur that's backwards — nothing leaves the phone. Explain it in
onboarding before sending the user to Settings, and make the claim structural:
**no network entitlement in the extension at all.**

## Fallback if Step 0 fails

- **Action Button / Control Centre control** → app records in foreground with the
  same session → transcript to clipboard → you paste. Worse (a paste, and it
  leaves your app) but no Full Access warning and no background app.
- **Container-app-in-background** is what everyone else ships and what we're
  trying to avoid. Last resort — and, on the evidence, the only thing that
  works: WhisperBoard is this design, despite being cited above as the
  opposite.
- **`PushToTalk.framework` is the wrong tool** despite the name: needs a channel,
  a remote participant, and APNs `pushtotalk` pushes; can't be joined unless
  foregrounded; from iOS 26 Apple requires genuine PTT apps to use it. Dictation
  claiming to be a walkie-talkie is an App Review problem.

## Open questions

- ~~Does `RequestsOpenAccess` + `hasDictationKey` actually clear `!rec`?~~
  Answered: they do clear `!rec`, and it does not help. The refusal moves to
  `AVAudioEngine.start()`. See Step 0 result.
- Can the mic prompt be presented from the extension, or must the container app
  take it first? Assume the container app.
- ~~Do `.playAndRecord` + `.default` + `.mixWithOthers` +
  `.bluetoothHighQualityRecording` compose?~~ Answered: yes. In the container
  app the full set activates and starts on the first attempt, 294 ms from
  `setCategory` to a running engine. Still untested against AirPods.
- How much latency does high-quality recording add? Enough to want a setting?
- Is `SpeechTranscriber`'s memory really free from the extension's side, or does
  IPC buffering still count against the cap under load?

## Sources

- [WWDC25 §277 — Bring advanced speech-to-text to your app with SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [`bluetoothHighQualityRecording`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/bluetoothhighqualityrecording)
- [Forum: error 561145187 recording from a keyboard extension](https://developer.apple.com/forums/thread/775077)
- [WhisperBoard](https://github.com/fmachta/WhisperBoard) — cited here as
  proof that in-extension capture works. **It does not do that.** Its keyboard
  extension contains no `AVAudioEngine`, no `installTap` and no `setCategory`;
  `AudioCapture` lives in a shared source directory compiled into both targets
  but is instantiated only by the app's `TranscriptionService`. The dictation
  button posts a Darwin notification, sets `shouldStartRecording`, and shows
  "Recording in app..." while polling for a result. It is the
  container-app-in-background design, not a counterexample to it

# Murmur for iOS

Design notes for the iPhone counterpart. Nothing here is built yet; this is the
architecture and the one experiment that has to succeed before the rest is worth
writing.

## The short answer

Yes, the Mac experience ports — hold a button, speak, let go, the text lands in
the field you were already typing in. And it ports *now* in a way it could not
have a year ago, because iOS 26 removed both of the constraints that make every
existing dictation keyboard behave badly.

The two complaints about those apps are not developer laziness. They are the two
constraints, showing through:

| What you notice | What causes it |
| --- | --- |
| You have to keep the app running in the background | The keyboard extension has a ~50 MB memory ceiling. Whisper does not fit. So the extension ships the audio to the container app, and the container app has to be alive to receive it. |
| Music on AirPods turns to mush while you talk | Opening *any* input route forces Bluetooth from A2DP (stereo, full bandwidth) to HFP (mono, phone-call bandwidth). It affects playback too, and preferring the built-in mic does not avoid it. |

Both now have first-party answers.

**`SpeechTranscriber`** (iOS 26, the `SpeechAnalyzer` family that replaces
`SFSpeechRecognizer`) runs its model in a system process. Apple is explicit that
it "operates outside of your application's memory space, so you don't have to
worry about exceeding the size limit", and that it does not increase your app's
download size, storage, or runtime memory. The model is a shared system asset,
downloaded through `AssetInventory`. The ceiling that forced the container-app
detour simply stops applying: the extension can transcribe for itself.

**`AVAudioSession.CategoryOptions.bluetoothHighQualityRecording`** (iOS 26)
keeps the Bluetooth link at full bandwidth while recording, on hardware that
supports it. That is the AirPods fix, from Apple, rather than a workaround.

Put those together and the container app has no job during dictation. It is
where you grant the microphone once, download a language model, and read your
history. While you are actually dictating it is not running.

## How it works

```
touch down ──▶ AVAudioSession (mixWithOthers) ──▶ AVAudioEngine tap
                                                        │
                                                  SpeechTranscriber   (while you speak)
                                                        │
                                                 volatile results ──▶ the keyboard's readout
touch up  ──▶ finalize ──▶ FillerFilter ──▶ textDocumentProxy.insertText()
```

Everything above the dashed line lives in the keyboard extension. No app group
handoff, no Darwin notification, no background container app, no clipboard.

Text delivery is the one place iOS is *better* than the Mac. On macOS Murmur has
to put the transcript on the pasteboard, synthesise ⌘V, and restore your previous
clipboard a moment later, because there is no sanctioned way to type into another
app. A keyboard extension already owns the text input connection:

```swift
textDocumentProxy.insertText(transcript)
```

That is the whole output layer. `Sources/Murmur/Output/TextInjector.swift` — the
pasteboard dance, the clipboard restore, the Accessibility permission it needs —
has no iOS equivalent to port. It just goes away.

## The audio session

This is the part worth getting exactly right, since it is the thing you noticed.

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(
    .playAndRecord,
    mode: .default,
    options: [.mixWithOthers, .bluetoothHighQualityRecording, .allowBluetoothHFP]
)
try session.setActive(true)
```

Each option is load-bearing:

- **`.mixWithOthers`** is why your music keeps playing instead of being
  interrupted or ducked. Without it, `.playAndRecord` stops whatever else is
  going. `.record` is the wrong category here — it silences other audio by
  design, and does not take this option.
- **`.bluetoothHighQualityRecording`** is the AirPods fix — full bandwidth
  in both directions rather than the HFP collapse.
- **`.allowBluetoothHFP`** is the documented fallback for routes that cannot do
  high-quality recording. You want the degraded path available, just not as the
  default.

Three caveats, all from Apple's own documentation, all worth knowing before you
build on this:

- High-quality recording is only available in the **`.default` mode**. Modes like
  `.measurement` and `.voiceChat` — the reflexive choice for a dictation app —
  silently forfeit it.
- It is **not supported in the European Union**. The code has to work when the
  capability is absent, which means it needs the query below rather than an
  assumption.
- It **may increase input latency**, which matters for a press-and-hold app
  where the first syllable arrives milliseconds after the touch.

So check rather than assume, and tell the truth in Settings about which route
you actually got:

```swift
if let input = session.currentRoute.inputs.first,
   let mic = input.bluetoothMicrophoneExtension,
   mic.highQualityRecording.isSupported {
    // Full-bandwidth route. Otherwise you are on HFP and music will sound thin.
}
```

Apple also suggests `setPrefersNoInterruptionsFromSystemAlerts(true)` while
recording, so an incoming call's ringtone does not kill the utterance.

## The risk: microphone access inside a keyboard extension

Everything above depends on one thing that is not fully settled, and it should be
tested before anything else is written.

The folklore is that keyboard extensions cannot use the microphone at all. That
is not quite right. [WhisperBoard](https://github.com/fmachta/WhisperBoard)
captures audio inside the extension today — its `AudioCapture.swift` runs
`AVAudioEngine` in a ~20 MB extension — and delegates only *transcription* to the
container app, for the memory reason above. That is exactly the constraint
`SpeechTranscriber` lifts.

But developers do hit `AVAudioSession` failing to start in an extension with

```
Code=561145187 "(null)" UserInfo={failed call=err = PerformCommand(*ioNode, kAUStartIO, NULL, 0)}
```

`561145187` is the four-character code `!rec` — "cannot start recording". On the
[developer forum thread](https://developer.apple.com/forums/thread/775077) an
Apple engineer's answer is that the extension must both

1. request open access — `RequestsOpenAccess = true` in the extension's
   `NSExtensionAttributes`, and
2. indicate dictation support — `hasDictationKey = true` on the
   `UIInputViewController` subclass,

and that if `!rec` persists after that, it is a bug worth filing rather than a
policy. The thread has no confirmed resolution, so treat this as unverified.

`hasDictationKey` is documented only as the flag that suppresses the system's own
dictation button so there are not two of them. That it also appears to gate the
recording audio session is undocumented, and is the single most important thing
to confirm.

**Spike this first.** An empty keyboard extension, those two Info.plist and
controller settings, `AVAudioEngine` started on touch-down, a print of the buffer
count. Half an hour on a real device — the simulator will not do, it has no
audio input. If it records, the rest of this document is ordinary work. If it
returns `!rec`, stop and take the fallback below instead.

## Transcription

`SpeechTranscriber` is a near-exact match for the shape Murmur already uses.
`TranscriptionEngine` is utterance-shaped and streaming-first —
`beginUtterance` / `feed` / `finishUtterance` — and `SpeechAnalyzer` is an
`AsyncSequence` fed a stream of buffers that yields results as you speak. The
**volatile results** it emits are the same idea as Nemotron's per-chunk
transcripts: a rough guess delivered almost immediately, refined over the next
seconds. That is what drives the live readout, and unlike Nemotron's 2.2 s
chunks it needs no tradeoff against throughput.

Two modules, and you want both, tiered the way `EngineRegistry` already tiers
the Mac's three:

| Module | When |
| --- | --- |
| `SpeechTranscriber` | Default. General-purpose, higher quality, but has hardware requirements — check `isAvailable` rather than assuming. |
| `DictationTranscriber` | Fallback for older devices. Same models as system dictation, no extra hardware requirement. |

Neither ships in your binary. The language asset is downloaded once through
`AssetInventory.assetInstallationRequest(supporting:)` — that is the container
app's main job, and the analogue of the Mac app's 700 MB Nemotron download, minus
the disk-management chore, since the system owns the files and shares them with
every other app that asks.

There is no port of Nemotron or Parakeet here. FluidAudio's CoreML models are
the thing that does not fit, and the whole point of this design is not to fight
that.

## What ports from the Mac app

`MurmurCore` was already kept free of AppKit so it could be unit tested without
launching an app. That pays off now — it compiles for iOS unchanged:

| File | Still true on iOS |
| --- | --- |
| `FillerFilter.swift` | Yes. A word list and punctuation repair; no model, no platform. |
| `SubtitleText.swift` | Yes, and more useful — the keyboard's readout is a couple of lines tall. |
| `RewriteValidator.swift` | Yes, if the rewrite pass ships. |
| `ModelNaming.swift` | Partly. Asset naming is Apple's now, not FluidAudio's. |

`TextPolisher`'s `FoundationModels` rewrite is available on iOS too, but it
should stay off by default and probably off entirely in v1: it costs 0.7–1.5 s
on a Mac, and it would be running inside a memory-capped extension.

What does not port is the entire input half. `HotkeyMonitor`, `TriggerKey`, the
`CGEventTap`, `Permissions`, `LoginItem` — all macOS-only concepts. iOS has no
global hotkey, which is the real reason this has to be a keyboard in the first
place: the button has to live somewhere the system already lets you touch while
another app is frontmost, and the keyboard is that place.

## The gesture

A press-and-hold button, sized and placed like a spacebar, in a keyboard that is
otherwise a normal QWERTY layout:

- Touch down starts capture. Touch up ends it and inserts.
- A short upward slide latches recording on, for long dictation, with an obvious
  way out. Holding a key for two minutes is unpleasant on a phone in a way it is
  not on a desk.
- Haptics on start and stop, since you are looking at the text field rather than
  the button.
- Dragging off the button and releasing cancels, matching every other iOS
  control.
- The live transcript renders in the keyboard's own view, where a Mac would use
  the floating readout above the Dock. `SubtitleText` already trims to the most
  recent words, which is what you want in a two-line strip.

## The cost you cannot design away

Open access — "Full Access" in Settings — is required, and iOS shows a blunt
warning when you enable it saying the keyboard may transmit everything you type.
For Murmur that warning is exactly backwards: nothing leaves the phone, and the
whole reason for the architecture is that nothing has to. But it is the system's
wording, not yours.

The only honest response is to explain it in onboarding before sending the user
to Settings, and to be able to back the claim up — no network entitlement in the
extension at all, so the promise is structural rather than a pinky swear.

## If the spike fails

If a keyboard extension genuinely cannot open a recording session, the
press-and-hold-and-it-lands-in-the-field experience is not available on iOS, and
the honest fallback is a step down:

- **Action Button or a Control Centre control** launches the app, which records
  in the foreground with the same audio session, transcribes, and puts the result
  on the clipboard. You then paste. Fewer moving parts, no Full Access warning,
  no background app — but it is a paste, and it takes you out of your app.
- **The container-app-in-background design** is what everyone else ships and what
  you already dislike. It is the fallback of last resort, not a plan.
- **`PushToTalk.framework`** looks tempting from the name and is the wrong tool.
  It is built for channel-based voice comms — it needs a channel, a remote
  participant, and APNs pushes of type `pushtotalk`, cannot be joined unless the
  app is foregrounded, and from iOS 26 Apple *requires* real push-to-talk apps to
  use it. A dictation app claiming to be a walkie-talkie is an App Review
  problem, not an architecture.

## Order of work

1. **The spike.** Microphone inside a keyboard extension, on device. Everything
   else is contingent on it.
2. **The audio session**, with the route capability logged. Verify on AirPods
   that music genuinely survives — that is the acceptance test for the complaint
   that started this.
3. **`SpeechTranscriber` streaming**, volatile results into a readout.
4. **`insertText`**, `MurmurCore` cleanup on the way through.
5. **The container app**: onboarding, microphone grant, `AssetInventory`
   download, history.
6. Latency measurement, matching the Mac's `--selftest`, so "immediate" is a
   number rather than a feeling.

## Open questions

- Does `hasDictationKey` + `RequestsOpenAccess` actually clear `!rec`? Unverified;
  see the spike.
- Does the microphone grant prompt from inside the extension, or must the
  container app take it first? Plan for the container app taking it, since an
  extension is a poor place to present a permission alert.
- Do `.playAndRecord` + `.default` + `.mixWithOthers` +
  `.bluetoothHighQualityRecording` actually compose? Each is documented alone;
  the combination is not.
- How much latency does high-quality recording add, and is it enough to want a
  setting?
- Is `SpeechTranscriber`'s memory really free from the extension's perspective,
  or does the IPC buffering still count against the cap under load?

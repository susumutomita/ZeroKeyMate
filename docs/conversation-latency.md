# Local conversation after an iOS update

Mate uses `SystemLanguageModel.default`, supplied by the operating system. It
does not bundle a separately downloadable LLM or select a cloud model. An iOS
version alone does not establish the downloaded model's readiness or latency.
Check model availability on the connected iPhone before claiming a model upgrade.

The conversation path now:

1. Finishes a recognition turn after 1.2 seconds of unchanged text (formerly 2).
   The 15-second empty-input and 60-second maximum-turn bounds remain.
2. Skips structured translation/summary inference when the input has no task
   cues. Candidates still go through the existing local planner and authorization.
3. Prewarms the local conversation session when the person starts the companion
   or explicitly interrupts to speak. Prewarming starts no camera or microphone.
4. Streams cumulative text into the conversation screen and queues complete
   sentences for speech before the full response is available.
5. Resumes the microphone only after both generation and queued speech finish,
   within the person's explicitly started conversation session.

This remains turn-based speech recognition, local text generation, and Apple
speech synthesis. It is not a simultaneous speech-to-speech or hands-free
barge-in implementation. The existing **Interrupt and speak** control cancels
the pending generation and queued speech before starting another turn.

## Device acceptance

- Install build 9 or later using `make start-device`, with a live device probe.
  An unavailable paired-device entry may contain an old OS version.
- Confirm Apple Intelligence is enabled and the model is ready after the OS
  update. There is no automatic cloud fallback.
- Start Mate explicitly. Test a short Japanese conversation, then English.
- Observe the first sentence beginning while the remainder is generated. Check
  that repeated snapshots do not repeat spoken words or split `0.10` in half.
- Interrupt a long reply; verify that neither old speech nor late text returns.
  Repeat with Settings, backgrounding, rest, and stand detachment. Capture and
  listening must remain stopped until another explicit start.
- Check that a translation/summary request and an explicit beer order still
  reach their existing flows. No new payment authority is granted by this change.
- Measure end of user speech, final transcript, first model text, first audible
  sentence, and end of playback separately across several fixed test prompts.
  Compare the same phone, language, thermal state, build mode and warm/cold
  conditions. Do not label Simulator tests or the shorter endpoint constant as
  proof of a measured end-to-end speedup.

Automated checks cover sentence buffering, task candidate routing, turn timing,
progressive UI state and late callbacks after stop/background/settings. Physical
microphone, speaker, newer OS/model readiness and DockKit remain separate checks.

## Build 15: current Apple models and live speech

`SystemLanguageModel.default` continues to select Apple's **on-device** model.
There is no app-controlled model-version switch. Apple documents a rebuilt model
with iOS 27; building with Xcode 27 does not install that model on an iOS 26 phone.
The device probe on September 22, 2026 still reported iOS 26.7 (23H24).

- SpeechAnalyzer + SpeechTranscriber now supply progressive/fast results when the
  selected language's model is installed. Initial preparation downloads only
  Apple's speech model assets; no microphone data is sent. While unavailable,
  the existing `requiresOnDeviceRecognition` path remains usable for that turn.
- Revised volatile text replaces its old audio range. A finalized **range** does
  not end a conversational turn. After endpointing, Mate stops microphone input
  and waits for corrected final text before routing a request. Finalization
  failure, overflow or a three-second timeout submits nothing. The tap only
  copies into a bounded raw queue; a serial worker converts and flushes into a
  second bounded analyzer queue. It never waits for conversion in the tap.
- The new input path combines acoustic activity (PCM RMS >= 0.008) with text
  stability: 900 ms without detected activity and 300 ms without a text change.
  Without an acoustic activity signal, the previous 1.2-second text bound is
  retained. Quiet and noisy rooms still require device tuning; this is a
  conservative energy heuristic, not speaker identification or semantic VAD.
  Empty-input (15 s) and total-turn (60 s) bounds remain.
- Completed user/assistant roles remain native Transcript entries. Up to eight
  recent turns can survive session rotation. On iOS 26.4+ with the newer SDK,
  actual token counts and context capacity govern trimming, reserving space for
  the response. The older SDK path retains a conservative byte bound.
- Listening resumption prewarms the next conversation session. The prompt asks
  for a short, useful first sentence; TTS still queues complete sentences, not
  speculative fragments. iOS 27's new guardrail error receives the same
  no-retry recovery as iOS 26.

This is still alternating listening/generation/speech, with explicit interruption,
not full-duplex voice or an independently upgraded LLM. The compatibility
SFSpeechRecognizer path retains its previous stable-text endpoint; final-text
correction protection above applies to the new SpeechTranscriber path. Camera permission,
background/Rest behavior and purchase authorization are unchanged.

`LiveSpeechTests` exercise finalized corrections, cancellation during preparation,
start and finalization, timeout, owned audio buffers and queue overflow, without
capturing audio. `ConversationPerformanceTests` uses fixed synthetic Japanese
text on the phone, recording first text, first speakable sentence and completion
separately; it checks recall at the seventh turn. It does not measure
microphone-to-speaker latency. No private conversation content is logged.

Sources: [Apple's Foundation Models updates](https://developer.apple.com/documentation/Updates/FoundationModels),
[SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/),
[SpeechTranscriber fast results](https://developer.apple.com/documentation/speech/speechtranscriber/reportingoption/fastresults),
[SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel).

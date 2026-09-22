# Conversation acceptance on the phone

On September 21, 2026, build 12 was tested on an iPhone 16 Pro running iOS 26.7
using fixed synthetic prompts. Japanese short-term recall (blue mug and a long
meeting) and the deterministic refusal to claim an unsupported Amazon purchase
passed. A separate English → Japanese switch encountered the system model's
`guardrailViolation` at the benign input “今日は会議が長くて疲れた。” after an
English greeting. This is one observed failure, not evidence that every
language switch fails or that the model's safety decision can be bypassed.

Previously every conversation error called `rest()`, closing the face and
stopping the companion. Build 13 handles this specific blocked-response error
as a request for a new user turn. It stops unfinished speech, removes partial
text and asks the user to say it another way in their current language. Mate
stays awake. There is no retry, rewritten prompt, guardrail change, cloud call,
purchase or fabricated model answer. Completed native transcript turns remain;
the failed turn is discarded. Other errors retain their existing handling.

Microphone resumption uses only the existing explicitly started listening
session. A keyboard conversation cannot start the microphone, and a late error
cannot undo Rest, backgrounding or opening Settings. Tests inject a blocked
stream to check these boundaries and that generation happens once per input.
These controlled tests are UI-state evidence, not proof that the model always
accepts benign inputs or that live speech recognition/stand tracking passed.

The default Apple guardrails remain enabled. Bilingual real-model behavior and
spoken turn latency still need ongoing physical acceptance; the recovery does
not claim to eliminate the underlying model rejection.

## September 22: build 15

The physical iPhone 16 Pro still reports **iOS 26.7 (23H24)**. The app was built
with Xcode 27.0, but this does not install iOS 27's rebuilt Foundation Models
model. It continues to use `SystemLanguageModel.default` with the default
system guardrails. SpeechTranscriber reports available, with both `ja_JP` and
`en_US` assets installed.

Fixed-text physical acceptance passed:

- Japanese short-term recall and refusal to claim an unsupported Amazon purchase.
- English → Japanese → English response language switching.
- Seven-turn recall of an object name, while responding to unrelated reading and
  rest messages without bringing that name into those replies.
- Conversion of synthetic PCM buffers, retention across buffer reuse, and bounded
  queue overflow. These checks capture no microphone input.

The first prompt revisions overused an earlier telescope topic. Making the
assistant's role and latest-message response explicit corrected the two tested
unrelated-topic cases. This is a small observed improvement, not evidence of
reliable general reasoning or elimination of every repetitive answer.

For the final seven Japanese turns, after calling `prepare()` before each turn:

| Measurement | First turn | Subsequent six turns |
| --- | --- | --- |
| Request → first text | 1.01 s | 0.49–0.78 s (median 0.72 s) |
| Request → first complete speakable sentence | 1.11 s | 0.49–0.82 s |
| Request → complete response | 1.26 s | 0.52–0.85 s |

Conditions: Debug build, thermal state nominal, fixed synthetic text, no camera,
microphone, actual speech playback, card read or payment. The model had also run
earlier fixtures; these are not controlled cold-start results or a before/after
speedup benchmark. Actual speech-end → audible-reply latency, Bluetooth/HFP,
quiet/noisy-room endpoint behavior, full-duplex interruption and the iOS 27 model
still require separate physical acceptance.

The deterministic iOS 27 simulator regression passed 19 tests; three physical
model checks were explicitly skipped there. The physical model fixtures ran on
the phone rather than inferring success from simulator model availability.
See [the live-speech implementation and compatibility boundaries](conversation-latency.md).

## September 22: iOS 27 update

A fresh CoreDevice query confirms the physical iPhone 16 Pro has been updated
to **iOS 27.0 (24A437)**. The app continues to select
`SystemLanguageModel.default`; it does not pin the previous OS model or route
conversation to a cloud model. This establishes the OS version, not the new
model's local availability or response quality.

The updated app passed a signed Xcode 27.0 build and bundle checks. Transfer
and physical acceptance could not complete because CoreDevice stopped
establishing its RSD connection to the paired phone. Therefore the timings
above remain **iOS 26.7 build 15 measurements**. No iOS 27 first-token, spoken
response or quality result is claimed. Resume the fixed synthetic conversation
and PCM checks after restoring the device connection, then measure actual
speech-end to audible-reply latency separately.

## Build 18: software completion while physical update is deferred

At the user's request, physical installation is deferred. The conversation
implementation now includes typed visible history and the continuity fixes
described in [the conversation quality report](conversation-quality.md). That
report includes an actual Mac local-model run, clearly separated from phone
acceptance. No newer iPhone speech or model-quality result is claimed here.

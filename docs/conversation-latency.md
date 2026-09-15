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

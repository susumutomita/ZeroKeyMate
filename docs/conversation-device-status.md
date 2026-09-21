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

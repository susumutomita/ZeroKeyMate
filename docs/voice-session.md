# Voice session lifecycle

Use **Spend time together** to explicitly start camera and voice, or **Speak now** in Controls for voice without starting the camera. During a reply the latter becomes **Interrupt and speak**. It cancels the pending reply, discards its approval offers and starts a new recognition turn. It cannot interrupt a financial operation. **Rest** stops camera, recognition and playback. The face itself stays free of buttons and text.

| Event | State transition / guard |
| --- | --- |
| Explicit start | Creates a listening-session revision; permissions are requested before capture. |
| Recognition final | Completes the turn exactly once, stops recognition and submits nonempty text. |
| Stable text for 2 seconds | Same completion path; this is transcript stability, not amplitude VAD. |
| No text for 15 seconds | Ends the silent turn and renews only an active, foreground, permitted session. |
| Maximum 60 seconds | Completes the bounded turn; a late final cannot submit it again. |
| Model reply | Playback begins after recognition stops; no automatic barge-in is provided. |
| Playback complete | Only the current utterance may request a new recognition turn. |
| Read-aloud off | The conversation task's completion requests the next turn without playback. |
| Interrupt and speak | Invalidates the old conversation and voice revisions before requesting the microphone. |
| Rest, background, detach, audio interruption/reset | Invalidates revisions and stops; foreground/re-docking alone never restarts. |
| Permission denial or recognition error | Stops the session and explains the failure; keyboard remains available. |

`VoiceTurn` uses monotonic uptime supplied by `VoiceService`. `CompanionListeningSession` decides whether a completion may resume recognition. `CompanionModel` owns conversation generation and approval offers, while `VoiceService` owns the current recognition generation and playback utterance. These are separate lifetimes.

Automated tests cover turn boundaries, duplicate/late finals, cancelled model replies, current-utterance/session guards and explicit microphone permission denial. Actual microphone quality, continuous multilingual speech, hardware interruption and Belkin acceptance remain in #15. No cloud recognition fallback is added.

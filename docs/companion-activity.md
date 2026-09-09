# Companion activity

`CompanionActivity` is the shared presentation state for the eyes, Controls and the face's VoiceOver value. It is derived from the conversation, approval and execution lifetimes. It is not a payment authority or evidence of success.

| Observation | Presentation |
| --- | --- |
| Rest or interrupted interaction | Resting takes priority over late processing/results. |
| Microphone listening / speech playback / model work | Listening / speaking / thinking are separate states. |
| A proposal or disclosure awaits approval | Waiting for approval. |
| Native prover running | Generating a proof on this iPhone. |
| Approved request sent to the service | Sending; this does not assert that a transaction has settled. |
| Receipt or transaction being independently checked | Checking confirmation. |
| Persisted request remains without a confirmed result | Unknown; a previous success cannot replace this state. |
| Verified result is persisted | A short confirmed outcome, only for the still-current interaction. |
| Failure before a pending request was persisted | A short rejection, excluding cancellation. |

Detailed execution text remains in Controls and the existing approval/activity views. The home face stays free of visible text. English and Japanese labels and Reduce Motion retain the same state semantics.

DockKit outcome gestures run inside `MateModel`'s existing reconciliation task. A confirmed result requests a pitch movement; a rejection requests yaw. A request is accepted only during an explicitly active camera session, with a connected stand, movement enabled and Reduce Motion disabled. Approval pauses both tracking and reactions. Rest/detach/settings invalidate the reaction ticket, including after a subsequent restart. Concurrent outcomes are dropped rather than queued, with at least four seconds between accepted requests.

The controller disables system tracking, requests zero velocity, and requires fresh stationary telemetry before moving. It clips a three-position plan to the reported supported axis range, at most 0.03 radians from the observed center, at most 0.1 radians/second, with 0.8 seconds per target. Unsupported axes, stale telemetry, insufficient room or insufficient speed skip the gesture. Each returned progress object must finish within 1.2 seconds; calls remain at least 0.8 seconds apart. Other supported axes are held near the observed position. Stop/cancellation requests zero velocity and restores the prior limits; a cleanup failure stops capture and prevents tracking from resuming. Tracking resumes only if the current consent, connection and movement settings still allow it.

**Settings → Senses → Stand movement** disables both tracking and outcome gestures. Reduce Motion has the same motor restriction. A camera start explicitly applies OFF for its own session when movement is disabled, because DockKit may otherwise enable system tracking automatically. Merely opening Mate does not take tracking ownership from another camera app.

This is implemented and SDK-compiled control, not physical acceptance. The actual accessory's movement, speed, stop latency (including SDK call latency), detachment and return to tracking must be checked under #15. A completed `Progress` or Simulator test does not prove a physical stop. Use a real confirmed request and a real policy rejection for outcome acceptance; do not manufacture settlement success to drive the stand. Native proof generation and live settlement remain separate acceptance work.

Public references: [DockAccessory](https://developer.apple.com/documentation/dockkit/dockaccessory), [orientation](https://developer.apple.com/documentation/dockkit/dockaccessory/setorientation(_:duration:relative:)-6h2ah), [limits](https://developer.apple.com/documentation/dockkit/dockaccessory/limits-swift.property).

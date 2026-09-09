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

Physical outcome gestures remain to be implemented in #11. DockKit writes must remain inside `MateModel`'s reconciliation task; this change does not add a second controller or alter tracking. Apple requires system tracking to be disabled for manual orientation and limits orientation/animation calls to two per second. The next coordinator must also bound position, speed and duration, discard stale outcomes and prioritize stop/detach before resuming tracking.

Public references: [DockAccessory](https://developer.apple.com/documentation/dockkit/dockaccessory), [orientation](https://developer.apple.com/documentation/dockkit/dockaccessory/setorientation(_:duration:relative:)-6h2ah), [limits](https://developer.apple.com/documentation/dockkit/dockaccessory/limits-swift.property).

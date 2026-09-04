# Architecture and first vertical slice

## Product

ZeroKey Mate is an iPhone companion on a DockKit stand. The planned product speaks with its owner and delegates bounded tasks to external services, without sending those services the owner's entire private policy or conversation. Tagline: **Your companion. Your rules.**

The first slice is deliberately smaller: a native SwiftUI face, explicit front-camera start/stop, connection observation and DockKit system tracking. It has no LLM, microphone, networking, wallets, ZK prover, or blockchain interactions. Camera tracking is not scene understanding or identity verification.

## Current implementation

`CaptureIntent` models explicit consent and foreground lifecycle without importing Apple UI/hardware frameworks. It is exercised by portable Swift tests. `MateModel` reconciles intent with actual camera and accessory state in one async worker. `CameraService` owns its AVCaptureSession inside an actor, off the main actor. `DockService` observes real connection events and only issues system-tracking settings requested by the coordinator. The face reports actual capture lifecycle, not a proof/authorization state.

Frames are not saved or uploaded; this build has no microphone input, data-output delegate, network client, or persistence. Starting the camera enables a local video stream for DockKit's system tracking. A temporary inactive scene during the permission sheet is not treated as background. Entering background stops capture and clears the previous start request; returning foreground needs an explicit new start. A true DockKit detach also clears capture intent. Hardware and simulator checks are separate.

## Planned extension seams (not implemented)

- Conversation and perception: on-device by default; any external payload requires an explicit, reviewable disclosure. Speech-to-text privacy is evaluated separately from LLM location.
- Owner authorization: a signing adapter and a matching trusted verification adapter. Versioned mandates identify the owner/account, delegated key, chain and execution contract, expiry, replay identifier and salted policy commitment. Do not let the request choose an arbitrary verifier. Signature methods stay outside the policy circuit.
- Proof generation: an iPhone ProveKit adapter generates a real proof for the committed policy and exact proposed action. Its compatibility, latency and memory budget must be measured on the target phone before it is a product promise.
- Execution: a separate enforcement contract verifies authorization and proof (or an explicitly trusted verifier attestation), consumes current spend state atomically, checks replay/expiry/revocation and executes only the bound action. Do not ship an unrestricted delegated wallet key. No real funds during development.
- Naming: ENS subnames resolve a stable Mate account and public profile. Private policy and personal memory are never records. Name ownership, record editing and spending authorization are separate. Resolve then bind the concrete destination before authorizing.
- Discovery: use The Graph only if live query results materially influence which service is selected. The actual sponsor track and testnet contract addresses must be rechecked before integration.

Privy, ENS and The Graph are intended integrations, not completed ones. Testnet availability, current SDK APIs and prize eligibility must be checked against current official documentation at implementation time. No identity-card integration is included. Only the general signing/verification boundary should support later additions.

## Immediate acceptance

Use `device-checklist.md` to record device/OS/stand firmware and results. The app must not claim a person is tracked merely because tracking mode was enabled. Face animation must remain distinguishable from camera, proof and payment status.

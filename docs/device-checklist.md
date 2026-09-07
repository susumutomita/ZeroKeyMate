# Physical and live acceptance

These checks are not satisfied by CI, an SDK build or a simulator. Record iPhone model, iOS version, stand/firmware, source revision and the observed outcome. Current outcomes are in validation.md.

- [ ] Fresh launch with/without stand leaves camera and microphone off without permission prompts.
- [ ] Camera Start alone prompts for camera; success shows the real iOS camera indicator and actual ON state.
- [ ] Stop works during permission and startup, and shows stopping until the session has stopped. Rapid repeated operations never resurrect old consent.
- [ ] Denial reports unavailable and can recover only after Settings and an explicit new Start.
- [ ] DockKit stand connects and tracks in portrait and landscape; a tracking setting is never presented as a detected tracked person.
- [ ] Stand tracking button disables tracking independently of the camera.
- [ ] Detach stops capture and an active continuous voice session; re-dock leaves both off.
- [ ] Background/lock and camera interruption clear camera consent. Returning foreground cannot restart it.
- [ ] Talk prompts for microphone/speech only on explicit start. Stop during either permission prompt prevents late startup.
- [ ] Japanese recognition uses on-device processing; unavailable recognition never falls back to cloud audio.
- [ ] Continuous conversation remains off until explicitly enabled and started. Stop, Rest, interruption, media-service reset, detach and background end it.
- [ ] Apple Intelligence conversation and coarse observations are truthful on an eligible physical phone.
- [ ] Reduced motion, VoiceOver, text size, portrait/landscape controls and all sheets remain usable.
- [ ] Network inspection confirms no camera frames, audio or private policy/notes leave the device.

Live external acceptance, requiring separately configured accounts and test funds:

- [ ] Privy login, distinct wallet roles and explicit owner authentication/signature complete.
- [ ] Correct Sepolia vault/token/attestor and two-confirmation receipts are verified.
- [ ] ENSv2 registers an owner-held name and independently resolves it through the public root; collision, expiry and parent mismatch fail closed.
- [ ] The Graph's live records materially select the actual specialist; changed ENS/recipient/price is rejected.
- [ ] A proof generated on the target iPhone reaches the verifier, exact contract execution and the actual specialist result. Record latency and peak memory on that phone.
- [ ] Network failure before submission, after broadcast and after payment is recoverable without duplicate spending.
- [ ] Cancellation of an unreceived request prevents delayed execution; payment-pending cancellation is refused.
- [ ] Revocation, altered payload/recipient/amount/chain, stale spend and replay are rejected.
- [ ] Full data disclosure and journal retention are reviewed before release. Sponsor eligibility is verified from current official terms.

No physical or live item is automatically checked off by a software test.

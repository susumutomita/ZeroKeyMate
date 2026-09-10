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

## Local proof measurements

The Local ZK result separates **Prove + verify**, **Preparation** and **Total proof request**. The total starts when the proof actor handles the request and includes key validation/loading, witness preparation, proving and original verification. Actor queue wait, modified-proof checking and UI rendering are excluded. Durations use a monotonic clock.

**Key setup** says whether this ProofService instance already held validated key data. A first key load is not proof of a cold process, cold OS cache or cold device. Record process restart and actual test conditions separately. The native acceptance test records one first-key-load request and three repeated requests using the same actor.

Thermal state is sampled before preparation and after original verification. It does not measure the maximum temperature or prove the absence of throttling between those samples. Peak memory is not estimated by the app: measure it separately with Xcode on the physical iPhone and record the measurement interval. Simulator attachments cannot establish physical-device performance or offline operation.

### UI proof memory measurement

`ProductUITests/testNativeLocalProofMemoryFootprint` uses XCTest's application memory metric around the **Generate and verify proof** operation. It records `physical_peak` separately from the absolute/difference memory values. Three measured iterations follow XCTest's discarded warm-up iteration. The app is relaunched before each iteration; this resets the process, not OS caches.

App launch and its initial key preparation occur before the measured interval. The interval includes the tap, request preparation, proving, original and modified verification, and the ready UI. Its scope differs from the proof actor's timing fields. Do not label it whole-launch peak memory or an offline/cold-device benchmark. Keep the units supplied by XCTest and inspect all three measurements, not just their average.

After building the native runtime and generating the Xcode project, run the following with the actual selected device and signing team already configured:

```sh
VERITY_SWIFT_SDK_MODE=native MATE_NATIVE_PROOFS=1 MATE_SWIFT_RUNTIME_FLAG=MATE_NATIVE_PROOFS \
xcodebuild -project apps/ios/ZeroKeyMate.xcodeproj -scheme ZeroKeyMate \
  -destination "platform=iOS,id=$MATE_DEVICE_UDID" \
  -only-testing:ProductUITests/ProductUITests/testNativeLocalProofMemoryFootprint \
  -resultBundlePath .build/proof-memory-device.xcresult \
  DEVELOPMENT_TEAM="$MATE_DEVELOPMENT_TEAM" -allowProvisioningUpdates test
xcrun xcresulttool get test-results summary --path .build/proof-memory-device.xcresult
xcrun xcresulttool get test-results metrics --path .build/proof-memory-device.xcresult \
  > .build/proof-memory-device.json
```

Use a new result path each time. Confirm the summary identifies physical iOS, zero failures/skips, and that the metrics contain three positive `physical_peak` values for the companion process. Complete any Xcode/device authentication locally. If authentication is canceled, no device memory acceptance is established; a Simulator result cannot replace it.

The test uses Apple's [performance measurement API](https://developer.apple.com/documentation/xctest/performance-tests). Both manual-start and manual-stop invocation options are set so the test controls a single measurement interval per iteration. It generates real native proofs and never grants payment authority or starts camera/microphone capture.

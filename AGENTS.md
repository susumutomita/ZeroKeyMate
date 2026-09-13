# Development boundaries

Build ZeroKey Mate as an independent project from these requirements and cited public documentation.

- Do not inspect, copy, translate, adapt, or derive code from unrelated private repositories or earlier private-code excerpts. Do not feed those excerpts or their summaries into implementation tools.
- External libraries must have reviewed licenses and recorded public sources. Do not claim a formal clean-room audit merely because this repository is new.
- Keep each PR runnable and scoped. Preserve the existing Apache-2.0 LICENSE.
- Run `make test`. On macOS also run `make build-ios`. State which checks were actually run. A build or simulator is not a physical DockKit test.
- Unavailable integrations must remain explicitly unavailable. Never add a fake proof verifier, pretend ENS resolution succeeded, or simulate a payment without labeling it as simulation.
- Camera capture requires an explicit start. Stop must work during startup. Backgrounding, camera interruptions, and detaching a connected stand must stop capture. Returning foreground or re-docking must not silently restart it.
- Report camera OFF only after the capture service finishes stopping. Keep capture intent separate from hardware state.
- Never add audio recording, frame logging, analytics, network upload, or payment signing as a side effect of docking. Request and document consent separately.
- Signing methods and verification methods are adapters around an approved, versioned mandate. The user authorized physical My Number card support on 2026-09-12 using the public MIT-licensed knocks-public/2024-CircuitBreaker source. Attribute reused code. A readable birth date is not an authenticated credential: do not unlock age-restricted orders until the government credential and order-bound ZK proof are actually verified.
- Never log or persist card PINs, raw card responses, names, addresses, birth dates, certificates or card signatures. Card contact and PIN entry require the user's explicit interaction; never retry an incorrect PIN automatically. Existing private keys, seed phrases and secret API keys must not be read or used without the user's specific authorization. Use disposable, local-chain-only keys for automated tests.
- Financial authorization must bind the actual chain, target, value/calldata, expiry and replay identifier. ENS resolution is not authorization. A local UI check is not an enforcement boundary.
- ProveKit proves policy compliance; it does not encrypt cloud audio/video or establish real-world identity. State the verifier's trust assumptions explicitly.

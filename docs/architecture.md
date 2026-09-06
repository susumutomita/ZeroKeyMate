# Architecture

## Product and consent

The SwiftUI companion uses Foundation Models for on-device conversation, Speech with required on-device recognition for Japanese input, and AVSpeechSynthesizer for playback. External translation/summary is a separate reviewable disclosure. The model cannot grant authority or execute payments.

Camera capture has explicit intent independent of AVCaptureSession state. Start requests permission; Stop remains effective while permission/startup is pending. OFF is published only after the capture actor stops. Backgrounding, capture interruption and detach clear capture consent. Returning foreground or docking never restarts capture. Vision performs coarse local classification and face-position detection, not identification. No frames or audio recordings are saved or uploaded.

Continuous speech is off by default. Enabling it does not start the microphone: a subsequent explicit Talk starts a session. Stop, Rest, backgrounding, audio interruption and stand detach end the session. The separate read-aloud preference controls reply playback.

## Authorization and exact action

MateCore, the Noir circuit, the Node API and MateVault share the versioned ZKM-ACT1 encoding. The SHA-256 action commitment binds chain ID, vault, mandate ID, concrete recipient, nonce, expiry, disclosure hash, previous spend, token amount and service. The contract has one immutable token and only a fixed transfer operation; no arbitrary target or calldata execution is exposed.

An EIP-712 owner grant authorizes an agent, salted policy commitment, validity and owner nonce in the chain/vault/version domain. Privy and device authentication form the current signing adapter. SignatureChecker validates the authorization at the contract boundary. ENS resolution and local policy checks do not confer spending authority. Identity-card protocols are outside scope.

The real ProveKit proof establishes that the committed private budget and allowed service mask permit this exact action and spend snapshot. The API runs the Rust verifier against a trusted circuit key, extracts the proof's public inputs, and compares every field before attesting. The vault atomically verifies owner-granted authority, agent signature and proof attestation, checks spend/replay/expiry/revocation and transfers test USDC.

## Trust assumptions

This is an off-chain ProveKit verifier plus an on-chain attestor signature, not an on-chain ZK verifier. A compromised attestor can approve violations of the private policy. It cannot forge the required owner or agent signatures, but collusion with the agent can spend available vault funds beyond that private policy. Owner revocation and withdrawal remain contract-enforced.

The prover/verifier binaries, circuit, preparation keys and their distribution are trusted. A hash manifest checks consistency, not authenticity if an attacker can replace both. Proofs do not encrypt cloud audio/video or establish real-world identity. There is no cloud audio/video channel in this app.

ENS registry owners/administrators and the configured Sepolia RPC are additional naming/chain trust assumptions. The Graph supplies current candidates; the allow list constrains endpoints and expected records. Registry reputation is not proof of service quality. ENSv2 writes allocate a one-year owner-held name with an immutable public address resolver; the owner can choose a different resolver using registry permissions.

## Execution and recovery

The API serializes executions and persists the approved request before provider preparation. The specialist verifies request binding and agent authority, obtains an actual model result and persists it encrypted, then returns only readiness. The relayer signs and journals transaction bytes before broadcast. Pending transactions are resent identically, and new nonces wait for existing outcomes.

After two confirmations and a canonical-block check, the specialist independently checks the exact Executed event before releasing the result. The iPhone independently checks the vault address, event/action/proof hashes, block, and available submitted action fields before recording completion. Transaction success alone is not accepted.

The iPhone retains the exact signed submission for lost first requests. Recovery reuses its action ID, signature and proof. Cancellation is only allowed before payment can have begun, and writes a durable tombstone that rejects delayed submissions. Payment-pending records cannot be discarded.

Settlement is not escrow or an atomic exchange for model output. A provider can become unavailable after payment; recovery requires its journal and API. No automatic refund or guaranteed quality is claimed.

## Data and operation

Private policies, notes and wallet roles remain in the iPhone Keychain. Conversation is in memory. The pending signed submission and receipts are retained locally for recovery. Approved disclosures and results are encrypted at rest in the API/provider journals with distinct keys; operators possessing those keys can read them. The journal is not private-policy encryption provided by ZK.

HTTP uses per-installation/per-provider bearer capabilities, JSON/body/concurrency limits and no browser origins. Redirects are rejected. No raw request, frame, microphone sample, signature, credential or upstream exception is logged. The model gets the explicitly approved text and fixed service instruction, with no tools.

The API can run with a truthful unavailable status when chain configuration is missing. The specialist will not quote a missing model as ready. Source-only iOS builds explicitly disable proving. Simulator, SDK builds, cryptographic tests, local chain simulation, and real hardware/live service acceptance are recorded separately.

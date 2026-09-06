# Security and privacy model

This source delivery is for testnet evaluation and has not received an independent audit. Never fund it with real assets or supply a production private key. Test execution is not claimed for this revision.

## What is enforced

`MateVault` holds only the explicitly deposited ERC-20 balance. Its immutable token and attestor are checked at API startup. A grant binds the owner, agent, salted policy commitment, expiry and nonce under EIP-712. Both owner and agent validation use OpenZeppelin SignatureChecker, permitting a future ERC-1271 owner without changing the policy circuit. The current client signs through Privy.

Every action binds the chain, vault, grant identifier, recipient, request hash, amount, service, cumulative-spend snapshot, expiry and one-use nonce. The Noir circuit checks the policy commitment, action hash, allowed service, positive amount and overflow-safe remaining budget. The independent verifier verifies the actual proof before extracting/matching all public inputs. A local precheck is not treated as a proof.

The vault additionally checks signature authority, current expiry/revocation, nonce reuse, spend state and deposited balance. Old-state concurrency fails on-chain. The attestor key cannot withdraw customer balances by itself. The agent wallet has no general instruction-following tool exposed to the conversation model; deterministic client code alone requests its bounded execution signatures.

## Trust that remains

The attestor is a trusted off-chain proof-verification service. It can sign a false assertion when compromised. EVM does not run the ProveKit verifier in this revision. Provider selection, code distribution, the phone OS, the application and configured RPC are also trust boundaries. Local biometric approval does not prove the owner understood a compromised application's screen.

The single-installation API bearer is a private connection capability, not multi-tenant authorization. Do not distribute one installation's client configuration to untrusted parties. TLS is required on a physical phone; loopback HTTP is accepted only by the Simulator and local backend-to-model connection. Redirects are rejected. A deployment must supply its own TLS reverse proxy and rate limits at the edge. Do not expose Ollama to the public internet.

Provider work is prepared before payment, but this is not atomic fair exchange: a provider can withhold a prepared result after it receives funds. Persistent receipts make the same paid request recoverable but do not cryptographically guarantee delivery. Model output is untrusted data and is never interpreted as code, tools or a new payment instruction.

The shared ENS parent controls its namespace. A per-name resolver relinquishes factory roles to the user, and the agent receives only the avatar-text edit role, but this does not erase the parent's underlying authority. Names and reputation are not proof of safety. The product uses an intentionally restricted, already-normalized ASCII name subset; no approximate Unicode normalization or arbitrary CCIP-read URL fetching is performed.

## Data handling

No raw audio/video is saved or uploaded. Speech must support on-device recognition; otherwise the app offers text input, not cloud fallback. Scene understanding is approximate local classification and face position, not identity recognition. Foundation Models unavailability is a real unavailable state.

Policy/notes and the encryption key use device-only Keychain. Large signed retry envelopes are AES-GCM sealed in a protected, backup-excluded application directory. Journals contain only reviewed external disclosures, result text and transaction/proof metadata, encrypted with a separate random per-installation key. File names do not expose payloads. AEAD binds journal records to both their ID and state. Loss of those encryption keys loses retry/retrieval data; maintain the deployment directory and keys together securely.

Camera/microphone lifecycle is explicit. Stopping before outbound submission invalidates pending preparation through a generation check. Stopping after submission cannot undo an already authorized request or a broadcast payment; the receipt remains recoverable. No service restarts sensors on behalf of a client.

## Recovery and failure

A raw wallet transaction is persisted before broadcast. Recovery rebroadcasts the same signed bytes/nonce and confirms the resulting hash; it does not create a second payment. Uncertain outcomes remain visible. Reverted confirmed operations are not marked successful. The server's transaction lane likewise writes signed bytes before broadcast and does not allocate a new nonce while an older one is unresolved. Do not use the relayer key for unrelated simultaneous transactions.

External requests persist the exact proof, signature, payload and action. A missing server journal can be retried only with the same approved request. Expired/unspent requests can be retired only after a finalized chain block establishes expiry and unused nonce; already paid requests remain recoverable. Loss of the provider journal after payment may lose the result; keep encrypted deployment state intact.

The verifier subprocess is time-limited, and on Linux it receives memory/CPU limits before decoding untrusted proof bytes. Source/artifact integrity checks protect against accidental mismatch, not against a malicious distributor replacing the application and its expected hashes together.

## Operational exclusions

No production release, anonymous-payment claim, on-chain proof-verification claim, biometric identity attestation, card integration, private-code reuse, hidden cloud conversation fallback, or fabricated service/payment success is included. Review configured URLs and public metadata before publishing. Do not commit `.env`, generated client Configuration.json, encrypted production journals or private signing material.

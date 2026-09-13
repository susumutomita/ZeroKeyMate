# Live checkout status — 2026-09-13

The [Mate Atelier storefront](https://zerokeymate-arc-shop.oyster880.workers.dev/)
is deployed on Cloudflare Workers with its dedicated D1 database and settlement
Durable Object. Its live catalog reports `checkoutAvailable: true` after checking
the actual Arc contracts, database and funded merchant. This is infrastructure
readiness, **not a completed physical-card purchase**.

## Confirmed public deployment

Network: Arc Testnet, chain `5042002`. USDC token:
`0x3600000000000000000000000000000000000000`.

| Component | Public address / evidence |
| --- | --- |
| Age proof verifier | [0x6ae9f3093e8bd23e0d5d2145861ecb095d40abaa](https://testnet.arcscan.app/address/0x6ae9f3093e8bd23e0d5d2145861ecb095d40abaa) |
| Government-root age gate | [0x1b3d75753d6e963ca681a4c7c151ae14b4d852b7](https://testnet.arcscan.app/address/0x1b3d75753d6e963ca681a4c7c151ae14b4d852b7) |
| Merchant / gas sponsor | `0x9a46479e2c1cfda09cb91b12283ccce03322e6b9` |
| Verifier deployment | [Transaction](https://testnet.arcscan.app/tx/0x3111d88dc6bb7c30ed46d0d9fbe4e38d4863e45ec15fc45cfbe005ef22febe26) |
| Gate deployment | [Transaction](https://testnet.arcscan.app/tx/0xa0bade003eaa83eff4f07a9ab6a7eca0cf63c5a8e049f3c0fdb2b0bd22dcdd06) |
| Merchant initial funding: 0.10 test USDC | [Transaction](https://testnet.arcscan.app/tx/0x966c51682fcc6c3c124b90e1b7ef9cd8bc9394b8c29508c62a524987f386fb74) |

Both fixed RPC providers confirmed matching successful deployment receipts and
complete runtime bytecode against the independently pinned package. The gate
runtime hash is `0x89a6c7a560a1e09aab42c04ca99fddcea75125b2a4d19a699e46a5510d960141`.
The two deployments used 0.034476939 test USDC in gas; initial funding used
0.000441. These transactions are deployment/funding evidence, not a beer purchase.
Only new dedicated test keys and free faucet test USDC were used.

## Product acceptance still outstanding

| Expected experience | Verified boundary |
| --- | --- |
| Ask Mate to buy one beer | On-device model tool and deterministic order controls implemented; hosted purchase from a physical phone unverified |
| Authenticate a My Number card | Signing-certificate and order-signature checks implemented; actual card/PIN interaction unverified; revocation not checked |
| Produce the age proof locally | Native Simulator and host proving pass with synthetic credentials; physical iPhone timing, peak memory and card compatibility unmeasured |
| Verify before payment | Worker calls the deployed age gate with order-bound inputs via two-provider `eth_call`; actual physical-card proof acceptance unverified |
| Pay and retain an Arc receipt | Exact x402 USDC settlement and receipt checks implemented; no buyer purchase transaction recorded yet |
| Automatically follow the outcome | PR #46 merged at `0ee3350adb1739dca597c127630803fe2a66d0cc`; read-only bounded observation, original order preserved |

Age verification is a contract call, not a separate on-chain age transaction.
The x402 token transfer does not itself invoke the age gate: the Worker enforces
the verification-before-fulfillment boundary. Both-provider agreement is an RPC
trust assumption. See [the shop protocol](../services/shop/README.md).

The native app was built, installed and launched on the physical iPhone on
2026-09-13. Its signed entitlements include NFC Tag Reading (`TAG`), and the
installed bundle contains the live shop origin, merchant, age gate and pinned
runtime hash shown above. This resolves the earlier Apple Account/provisioning
blocker; actual card authentication, proving and purchase acceptance still
require the user's interaction on that phone.

## Proving and prize claims

The ProveKit private-spending-policy runtime and signed-card age prover are
separate paths. The age prover uses the pinned experimental ProveKit Groth16
branch and its EVM exporter with a reviewed masking patch; it is not evidence
of standard ProveKit age-proof performance. Its setup is about 629 MiB plus a
12.5 MiB verifier. Do not claim fast physical-phone proving until measured.
The experimental backend and single-party test setup are not for mainnet.
World ID, AgentKit and Selfie Check are not integrated into this checkout.

The purchase screen now shows elapsed local-processing time while proving and
the measured successful duration afterward, retained with that order on the
phone. The monotonic timer covers `AgeProofService.prove`: resource preparation
if not already cached, witness preparation, native proving/local verification
and output validation. It excludes card/PIN interaction, earlier store-readiness
checks and network verification/payment. A separate native-call duration is
kept locally; neither timing value is submitted to the shop. Failure or
cancellation cannot create a successful timing record. This instrumentation is
not itself a physical measurement, a peak-memory measurement or a speed claim.

Purchase onboarding now stays in the purchase screen: Privy email sign-in and
buyer-wallet preparation do not require the separate specialist vault or an
extra execution wallet. Before creating an order or asking for a card, Mate
reads the buyer's six-decimal USDC token balance at the same finalized height
through both fixed Arc RPC providers and requires matching block hashes and
balances. Less than 0.10 test USDC shows the buyer address and Circle faucet
instructions; the user completes the faucet request and returns to recheck.
The merchant sponsors settlement gas. This preflight is not a balance
reservation; settlement still checks the actual authorization and receipt.

The earlier three proposed targets were Arc/Circle Agent Stack, Privy financial
flow and The Graph AI use case. Their completion remains outstanding:

- [Arc Agentic Economy](https://ethglobal.com/events/ethonline2026/prizes/arc):
  meaningful Circle Agent Stack integration into this purchase flow and actual
  buyer settlement evidence remain missing. Arc deployment alone is insufficient.
- [Privy financial flow](https://ethglobal.com/events/ethonline2026/prizes/privy):
  the iOS wallet SDK and public application/client IDs are configured, but a
  successful physical-phone wallet purchase must still be demonstrated.
- [The Graph AI use case](https://ethglobal.com/events/ethonline2026/prizes/the-graph):
  the fixed-store beer flow does not use live Graph data to make a decision.
  The earlier specialist-discovery integration does not establish this claim.

Neither local ZK nor use of ProveKit alone establishes eligibility for a
[World prize](https://ethglobal.com/events/ethonline2026/prizes/world).

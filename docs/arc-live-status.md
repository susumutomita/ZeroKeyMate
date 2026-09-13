# Live checkout status — 2026-09-13

The [Mate Atelier storefront](https://zerokeymate-arc-shop.oyster880.workers.dev/)
is deployed on Cloudflare Workers with its dedicated D1 database and settlement
Durable Object. Twelve consecutive public catalog checks on 2026-09-13 reported
`checkoutAvailable: true` after checking the actual Arc contracts, database and
funded merchant. The user also reported intermittent unavailability; its root
cause is not yet reproduced or resolved by that successful sample. The catalog
now returns a fixed `availabilityCode` for diagnosis, without raw errors or
order data. It does not relax any readiness or verification check.

**The main physical-card test-purchase path completed on 2026-09-13 in build 6.**
The user reported successful My Number card use and supplied the completed-order
screen showing **12.0 seconds** of on-device age-proof processing. The shop's
order is complete. Both fixed Arc RPCs independently confirmed a successful
0.10 test-USDC transfer from the buyer to the merchant and AuthorizationUsed:
[purchase transaction](https://testnet.arcscan.app/tx/0xfe77313324c3438cfc935dd87c14efe56bc6f3a1a4a4150a9ee661c045856eb3),
block **61889554**, matching hash
`0x2f7a3899edc19224e465e8f748a97ec68981ef4c03b55c5b76c9f1b263877caf`.
Settlement gas was **0.001831305 test USDC**, below the 0.00375 per-payment cap.
No card data was retrieved for this evidence check. This is a test purchase,
with no real money or physical delivery.

## Confirmed public deployment

Network: Arc Testnet, chain `5042002`. USDC token:
`0x3600000000000000000000000000000000000000`.

| Component | Public address / evidence |
| --- | --- |
| Age proof verifier | [0xb66c1e5d4afb1f1be6025ef85df0220e48fa7f20](https://testnet.arcscan.app/address/0xb66c1e5d4afb1f1be6025ef85df0220e48fa7f20) |
| Government-root age gate | [0x0f6c1de47a91a08b0c5854e7bb2173eea687cde9](https://testnet.arcscan.app/address/0x0f6c1de47a91a08b0c5854e7bb2173eea687cde9) |
| Merchant / gas sponsor | `0x9a46479e2c1cfda09cb91b12283ccce03322e6b9` |
| Verifier deployment | [Transaction](https://testnet.arcscan.app/tx/0x6e03166667709b4199ad739cb53526b994b60391a270683f9b73c29ae799c31a) |
| Gate deployment | [Transaction](https://testnet.arcscan.app/tx/0xa42faf61598cfdb93bc0ebb140721f41069a97c5fc978fc08a612643ac48dbac) |
| Merchant initial funding: 0.10 test USDC | [Transaction](https://testnet.arcscan.app/tx/0x966c51682fcc6c3c124b90e1b7ef9cd8bc9394b8c29508c62a524987f386fb74) |

Both fixed RPC providers confirmed matching successful deployment receipts and
complete runtime bytecode against the independently pinned package. The gate
runtime hash is `0x065e1463c16af0cafdc4f0cfcfb282b49d89fdca2ab1e2790d602b346b0c9dc1`.
The policy-compatible replacement contracts used 0.034468623 test USDC in gas.
Including the original contracts and initial funding, the dedicated deployer
has used 0.069386562 of its approved cumulative 0.10 test-USDC fee budget. These transactions are deployment/funding evidence, not a beer purchase.
Only new dedicated test keys and free faucet test USDC were used.

## Product acceptance and its limits

| Expected experience | Verified boundary |
| --- | --- |
| Ask Mate to buy one beer | On-device model tool and deterministic controls implemented; user confirmed that “buy beer” opens checkout; the completed purchase was started from the screen. Repeated voice-order completion still needs acceptance |
| Authenticate a My Number card | User completed physical card interaction; the resulting proof was accepted for purchase; revocation remains unchecked |
| Produce the age proof locally | User screenshot reports 12.0 s for a successful real-card proof on iPhone; native synthetic proof and negative-input checks also passed; no peak-memory benchmark |
| Verify before payment | Worker calls the deployed age gate with order-bound inputs via two-provider eth_call before payment; the real-card order completed |
| Pay and retain an Arc receipt | Confirmed actual 0.10 test-USDC transfer and authorization use in transaction linked above |
| Automatically follow the outcome | PR #46 merged at `0ee3350adb1739dca597c127630803fe2a66d0cc`; read-only bounded observation, original order preserved |

Age verification is a contract call, not a separate on-chain age transaction.
The x402 token transfer does not itself invoke the age gate: the Worker enforces
the verification-before-fulfillment boundary. Both-provider agreement is an RPC
trust assumption. See [the shop protocol](../services/shop/README.md).

The original build 4 was replaced wirelessly with **0.3.0 (6)** after the
paired iPhone joined the Mac's network. That app contains the policy-compatible
setup and new gate above, and the user completed the purchase with it. Builds 7
and **8** were subsequently installed and normally launched; installed-app
inventory independently confirmed both versions. Build 7 adds a visible Arc
Explorer button, selectable transaction hash and explicit copy action to
checkout and history. A fresh voice request
now suppresses terminal announcements from the previous order; read-only store
readiness retries up to three times without retrying card input or payment.

Build 8 adds a globe language menu to the purchase screen and other sheets.
Choosing English changes display and future purchase narration together without
replacing the current checkout. The preference survives relaunch; Settings can
still configure display and spoken language separately. Touch and hold the face
or swipe up to access the same menu in Controls. No control is added to the face.
The physical phone's language interaction still requires user confirmation;
installation and automated simulator checks are separate evidence.

## Proving and prize claims

The ProveKit private-spending-policy runtime and signed-card age prover are
separate paths. The age prover uses the pinned experimental ProveKit Groth16
branch and its EVM exporter with a reviewed masking patch; it is not evidence
of standard ProveKit age-proof performance. Its replacement setup is about 653 MiB plus a
13.1 MiB verifier. The observed 12.0 s is one successful order, not a general speed benchmark.
The experimental backend and single-party test setup are not for mainnet.
World ID, AgentKit and Selfie Check are not integrated into this checkout.

The purchase screen now shows elapsed local-processing time while proving and
the measured successful duration afterward, retained with that order on the
phone. The monotonic timer covers `AgeProofService.prove`: resource preparation
if not already cached, witness preparation, native proving/local verification
and output validation. It excludes card/PIN interaction, earlier store-readiness
checks and network verification/payment. A separate native-call duration is
kept locally; neither timing value is submitted to the shop. Failure or
cancellation cannot create a successful timing record. The user-supplied successful screen records 12.0 s with this timer; no
peak-memory measurement or general performance claim follows from one sample.

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
  buyer settlement evidence are separate requirements. Settlement is now
  confirmed; meaningful Circle Agent Stack use is still outstanding.
- [Privy financial flow](https://ethglobal.com/events/ethonline2026/prizes/privy):
  the iOS wallet SDK and public application/client IDs are configured, and a
  physical-phone wallet purchase now has the receipt evidence above; prize
  eligibility still requires checking the full sponsor criteria.
- [The Graph AI use case](https://ethglobal.com/events/ethonline2026/prizes/the-graph):
  the fixed-store beer flow does not use live Graph data to make a decision.
  The earlier specialist-discovery integration does not establish this claim.

Neither local ZK nor use of ProveKit alone establishes eligibility for a
[World prize](https://ethglobal.com/events/ethonline2026/prizes/world).


## Card-start and purchase interaction follow-up

The 0.3.0 (4) app separates camera shutdown from the serialized DockKit motor
commands. A nonresponsive stand can no longer hold the camera shutdown task.
Checkout waits for actual camera OFF for at most five seconds; CoreNFC has an
eight-second activation deadline and only shows the hold-card state after its
activation callback. Timeout and cancellation clear the PIN without retrying.
These changes address a reproducible software wait; they are not confirmation
that the user's physical card now authenticates.

A current request for one beer can start its order automatically after shop,
wallet and matching two-RPC balance checks. This creates the order only; card
interaction and the exact payment signature still require the user. Short
spoken guidance follows checkout state in the conversation language, while
display language remains separately selectable (English by default). The
purchase screen keeps long explanations in Purchase details.

Validation: `make test`, simulator build, 12 native regression/checkout tests
and the language-switch UI test pass. The regression tests include an
indefinitely blocked stand command, actual-camera-stop gating, stop during
startup, foreground recovery and cancellation. They use injected hardware,
not physical stand/card results. An opt-in physical NFC activation-only test
opens and immediately closes the system reader without connecting to a card
or sending an APDU; it does not authenticate a card or prove an age.

## Card-proof compatibility fix

The original circuit rejected a mandatory critical certificatePolicies extension
from the official physical-card profile. Adding that extension to the synthetic
fixture reproduced the failure with the old setup. The replacement processes
the specified policy without weakening unknown-critical, signature, age, order
or government-root checks. See [the fix and acceptance boundaries](card-proof-policy-fix.md).

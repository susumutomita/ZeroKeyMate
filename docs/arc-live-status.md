# Live checkout status — 2026-09-13

The [Mate Atelier storefront](https://zerokeymate-arc-shop.oyster880.workers.dev/)
is deployed on Cloudflare Workers with its dedicated D1 database and settlement
Durable Object. A physical iPhone probe reproduced one `settlement_network`
readiness failure followed by two healthy results. The merchant's public
chain/balance/gas reads now retry up to three times, with 250/500 ms delays.
Wrong chain, insufficient sponsor funds and fees above the cap still close
checkout; signing and broadcast are unchanged. Worker version
`fba92e5a-c050-4d0d-b088-94fd167dbdc6` was published on September 13.

After deployment, two physical-phone probes each returned three of three
healthy catalog responses. Eight subsequent Mac reads were also healthy.
These are public-read probes, not purchases. The precise underlying RPC error
was not captured; the fixed diagnostic deliberately exposes no raw errors.
The user subsequently supplied a real purchase video, matched below. This does
not establish that every intermittent failure or recovery path is resolved.

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
The user supplied an English physical-phone purchase screen and an English
checkout recording. In-place language switching and persistence also passed
a separate automated simulator test.

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

Current recommendations are **Privy Best financial flow** and **Arc Best
DeFi/Onchain Finance Application**. They match the actual embedded-wallet
payment flow; full eligibility and the entrant's pool remain organizer decisions.
The Arc Agentic category additionally requires meaningful Circle Agent Stack
use, which is absent from this checkout. The Graph Arc purchase-history source
was merged in PR #49, but a live deployment and data-driven decision remain
incomplete. See the [current partner matrix](prize-strategy.md).

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


## Repeated settlements and recorded purchase

On September 13 at approximately 21:26 JST, a narrow read-only D1 query found
five completed orders and no `payment_pending` order. Both fixed Arc RPCs
independently confirmed all five successful 0.10 test-USDC transfers, matching
block hashes and AuthorizationUsed events. This is five distinct authorizations,
not retries of one transfer. No assistant test submitted these payments.

| Order created (JST) | Confirmed transaction | Block |
| --- | --- | --- |
| 20:13:25 | [First physical-card purchase](https://testnet.arcscan.app/tx/0xfe77313324c3438cfc935dd87c14efe56bc6f3a1a4a4150a9ee661c045856eb3) | 61889554 |
| 20:27:26 | [Second settlement](https://testnet.arcscan.app/tx/0x6c01f3154d670693e4240b5da2257afff9896855c30288807fb8689e05c363e6) | 61891202 |
| 21:09:01 | [Third settlement](https://testnet.arcscan.app/tx/0x19686891c24c0ec029784ae90bd77892ecfab3397256e8f93834b8b3e06e2869) | 61896054 |
| 21:11:01 | [Fourth settlement](https://testnet.arcscan.app/tx/0x91649434ae26d6210f103baf748b947521903b692ceca5005b5431c9eaa86a5b) | 61896916 |
| 21:16:58 | [Recorded purchase](https://testnet.arcscan.app/tx/0x50546d317c7fb534f813c3171ab026cb3a0bafbfd16c217f1bda7517bda725d2) | 61897001 |

The last receipt was mined at **21:17:36 JST**, with block hash
`0x3de70f0616076fece5592a986023c35a82f4e46a6d94bbf80e912bbade2614a4`
and settlement gas **0.001831473 test USDC**. The user-provided 36.8368-second
1080p recording shows physical NFC activation/read success, proof processing,
exact payment approval, completion and an explorer view with this block and
payment timestamp. Audio has not been independently transcribed; do not claim
that this review verifies the spoken trigger. The physical clip was filmed with
another phone. The organizer's mobile-filming rule has no stated hardware-demo
exception, so submission-format compliance remains unresolved.

Validation of the readiness fix: **51 shop tests pass**, including bounded
read failure, unchanged financial caps and distinct second-order authorization.
Those route tests inject RPC/facilitator responses and do not replace the live
receipts above. `make test` also passes (90 Swift, 64 API, 21 launcher tests).
The native build and opt-in physical probe passed; no card or saved order was
accessed by the probe. Tests are not a guarantee of universal availability.

## Latest saved-order recovery and submission assets

The separately enabled physical-phone saved-order probe passed on September 13. It ran the app's normal status recovery and reported: “Yes. Your Mate Lager test purchase is complete, and the payment is confirmed on Arc Testnet.” The attachment contains only a fixed allowlisted answer and whether a saved order exists; no order capability or card data is exported. This establishes recovery of that saved order, not universal repeat-checkout reliability.

The user subsequently supplied a **58.4584-second edited device walkthrough**, combining successful recorded takes. It replaces the shorter recording as presentation material, and must not be described as one uncut order. A light non-generative audio filter was applied; the compressed video stream has the same SHA-256 before and after (`173d531bf0b73b716b356a2a34271503dbf5e092d5993d304fe645bb99eb4091`). This preserves image frames, timing and speed. Audio playback quality still needs the speaker's final listening check.

The [public project LP](https://zerokeymate-arc-shop.oyster880.workers.dev/demo/) was published with actual app screenshots, the edited walkthrough, an explanation of local proving and payment, and the store link. Worker version: `8ce02e99-e313-4840-ab8f-08ffb8504fb7`. Public reads after deployment returned the LP with HTTP 200 and the catalog with `checkoutAvailable: true`. No contract, payment, database schema or secret was changed by this static-asset publication. The browser loaded the video metadata as 58.4584 seconds with no media error.

Later user-supplied screenshots show **12.2 seconds** for another local proof run and [this transaction](https://testnet.arcscan.app/tx/0xf784fa4affa64f2f1d9c4fd9b3991757889332bbf097828cd3865e6f071b83f0), at block 61900557. This screenshot evidence is distinct from the five two-RPC receipt checks above.

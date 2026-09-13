# ZeroKey Mate presentation package

The main narrative is **problem → real recorded experience → how it works → technology stack → evidence**. It follows the short, one-message-per-slide structure of the supplied historical ZeroKeyCI deck without reusing that project's claims.

- [Open the offline English deck](index.html): nine main slides and two status/trust appendices. Arrow keys and Space navigate; print produces one page per slide.
- [Open the large-text human reading guide](narration.html): nine short sections, Japanese pronunciation hints and adjustable text size. It is display-only and never records or uploads audio.
- [Read the narration and editing notes](../demo.md): the final 3:27 film includes 50 seconds of the supplied device recording, then explains the local agent, proof, disclosure boundary and payment.
- [Public project overview](https://zerokeymate-arc-shop.oyster880.workers.dev/demo/): recorded walkthrough, actual app screenshots, technology explanation, receipt and store links.

The [pitch PDF](ZeroKeyMate-pitch.pdf), [3:27 narrated film](../../services/shop/public/demo/assets/submission.mp4), [English subtitles](submission-en.srt) and [original visual assets](../../images/) are committed to the repository. The recording is not a continuous same-order capture. The short walkthrough does not replace the required 2–4-minute human-narrated submission video.

## Claim-to-code map

| Slide / claim | Source and evidence |
| --- | --- |
| 4: local language model proposes a supported order | [ShopPlanner.swift](../../apps/ios/ZeroKeyMate/ShopPlanner.swift), [VoiceService.swift](../../apps/ios/ZeroKeyMate/VoiceService.swift), [ShopCheckout.swift](../../apps/ios/ZeroKeyMate/ShopCheckout.swift) |
| 5: signed credential, card possession, age and time checks | [Noir circuit](../../circuits/jpki_age/src/main.nr), [certificate parser](../../circuits/jpki_age/src/certificate.nr), [AgeProofService.swift](../../apps/ios/ZeroKeyMate/AgeProofService.swift) |
| 5: World Foundation ProveKit, experimental backend | [Pinned source manifest](../../config/age-proof-sources.json), [native build](../../scripts/build-age-native.py), [EVM exporter](../../scripts/build-age-evm.py). This is not World ID authentication. |
| 6: private witness stays on the phone | [AgeProofService.swift](../../apps/ios/ZeroKeyMate/AgeProofService.swift), [proof submission schema](../../services/shop/src/age.mjs). Public payment information and authentication still use network services. |
| 7: contract verification, then exact Privy/x402 payment | [Age Gate](../../contracts/src/MateAgeGate.sol), [two-provider checks](../../services/shop/src/age-rpc.mjs), [WalletService.swift](../../apps/ios/ZeroKeyMate/WalletService.swift), [Worker checkout](../../services/shop/src/worker.mjs), [sponsor queue](../../services/shop/src/settlement-queue.mjs) |
| 9: 12.0 seconds and actual payment | [Physical purchase and receipt evidence](../arc-live-status.md). The timing includes local preparation and verification, excludes NFC/network, and is one observation. Later supplied screenshots show 12.2 seconds for a different run. |
| 10–11: current boundaries | [Partner matrix](../prize-strategy.md), [card-policy and proof assumptions](../card-proof-policy-fix.md), [README](../../README.md) |

## Submission artwork

The submission logo and cover were created with the built-in OpenAI image generator, using the user-supplied Mate face as the reference. The deployed versions are [logo](../../services/shop/public/demo/assets/logo.png) and [cover](../../services/shop/public/demo/assets/cover.png). The app screenshots are actual user-supplied captures, kept visually separate from the generated cover.

The logo prompt asks for the existing friendly two-eye face, no mouth or text, as a square ivory/forest-green icon. The cover prompt asks for a 16:9 editorial phone-on-stand illustration with the exact text “ZeroKey Mate”, “Your companion. Your rules.” and “Local AI · Local ZK · Arc payments”. The [full generation prompts](artwork-prompts.md) are included for attribution.

No AI voiceover or synthesized replacement pronunciation is included. The human-narrated 207.38-second export has been uploaded and saved in the ETHGlobal dashboard. The entrant reported successful final submission on September 13, 2026. Award eligibility and judging remain with the organizers.

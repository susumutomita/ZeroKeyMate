# Acceptance criteria and evaluation scope

The delivered revision is source-complete for the documented product paths but runtime-unverified. Each criterion requires evidence from the actual build/device/deployment. Do not fill this table with assumed results.

| Area | Required evidence |
|---|---|
| Startup | Clean checkout builds and opens with `./mate`; missing credentials produce real unavailable states, not fake integration success. |
| Native proof | Changing inputs creates a freshly generated verified proof, with measured duration/byte count; mutation fails verification. |
| Circuit | Actual prover rejects over-budget, zero amount, forbidden service, changed commitment and changed action witnesses. |
| Finance | Real Privy owner/agent setup, signed grant, Sepolia deposit and confirmed Executed event match the approved request. |
| Recovery | Lost-response retries use identical action/nonce/raw transaction; no duplicate charge. Reverted/pending/expired states remain distinct. |
| ENS | Name resolves through actual ENSv2; agent avatar update succeeds, address update lacks permission; owner revocation blocks further avatar edits. |
| Discovery | A live Graph response is used in selection; deleted/inactive/mismatched/unreachable providers do not become fallback entries. |
| Specialist | Actual local model processes only reviewed text; result withheld before verified payment and recoverable afterwards. |
| Privacy | Camera/microphone off initially; stop/background/detach halt acquisition; no raw frames/audio, private budget/salt/notes in outbound requests. |
| Design | Actual portrait/landscape screenshots, readable small-device layout, VoiceOver labels, minimum 44-point controls, reduced-motion behavior. No clipped prices, covered alerts or falsely green statuses. |
| Hardware | Belkin stand pairs, connects, tracks within its physical limits; detach and permissions behave on the user's iPhone. |

No design rendering or automated accessibility result is being presented as evidence in this source-only delivery. Simulator cannot establish DockKit behavior or on-device Foundation Models availability. Test harness tokens/fixtures are isolated from production paths. Sponsor eligibility and finalist selection require separate submission review.

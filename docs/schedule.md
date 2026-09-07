# Delivery schedule

Updated 2026-09-07. **The entrant has not confirmed the event.** The dates below are a proposed plan for ETHOnline 2026, not a confirmed registration, eligibility decision or completion promise. All working dates are in Japan Standard Time (JST, UTC+9).

## Deadline to confirm

The official [ETHOnline 2026 submission guide](https://ethglobal.com/events/ethonline2026/info/details) specifies **September 13, 2026 at 12:00 pm EDT**, which is **September 14, 2026 at 01:00 JST** (September 13 at 16:00 UTC). The [event listing](https://ethglobal.com/events) runs September 4–16; the event end date is not the submission deadline. This leaves roughly six days from September 7.

Confirm the actual event URL, registration/track and deadline in the Hacker Dashboard before treating this as the project's deadline. If the event is different, replace these dates. Our proposed submission target is **September 13 at 18:00 JST**, seven hours before the ETHOnline cutoff.

## One demonstration to finish

Show one bounded translation: review a short Japanese note and price, prove policy compliance, obtain the English result and recover the same request without paying twice. Demonstrate rejection of an invalid request with actual test evidence. The stand supplies the companion experience; adding more services or expressive movements is not required for this story.

The current evidence supports native UI plus a separate local proof/payment/recovery demonstration. A seamless physical-iPhone-to-live-service demonstration is a remaining goal. Do not present separately recorded segments as one completed live transaction.

## Proposed daily plan

| JST date | Work | Completion evidence / decision |
| --- | --- | --- |
| Sep 7 | Confirm event, track, prize targets and device/stand availability; agree on the one demo | Confirmed deadline and scope; use cases in English/Japanese README |
| Sep 8 | Resolve the pending-operation correctness issue (#6), audit source completeness (#5) using permitted project/public sources, and test explicit sensor start/stop on the phone | No stale request can replace the approved one; camera OFF only after stop; no silent restart after undock/background |
| Sep 9–10 | Connect one translation flow on the target iPhone: necessary service setup, owner approval, real proof, settlement and recovery; measure proof time/memory; verify stand tracking | A reproducible run with matching request, proof and receipt. Live partner integrations count only when actually verified |
| Sep 10 evening | Choose the demonstrated scope based on evidence | If mobile/live integration remains blocked, freeze an explicitly separated app-UI and local-protocol demo. Do not invent a payment or stand result |
| Sep 11 | Fix demo-blocking defects, freeze features, run required tests/builds and rehearse from a fresh start | Repeatable demo and a validation record for the exact commit; English screenshots |
| Sep 12 | Record the three-minute demo with human narration; finish submission text, contribution history and relevant prize evidence | Playable video, working links, clear simulation/trust labels and verified claims |
| Sep 13, by 18:00 | Entrant checks the Hacker Dashboard, uploads and completes submission | Dashboard shows the submission saved/submitted and video playable; keep confirmation |
| Sep 13, 18:00–Sep 14, 01:00 | Buffer for upload/form corrections | No planned new feature work; official cutoff at 01:00 JST if ETHOnline is confirmed |

This is an aggressive planning estimate. Apple signing/device availability, on-device proving and live service configuration are dependencies, not solved tasks. If the critical path cannot finish by September 10, use the honest local-demo scope; some prize requirements may then be unmet.

## Priorities and ownership

- **Implementation first:** #6 correctness and #5 source completeness audit. The #5 title refers to source recovery, but this plan does not authorize importing unrelated private code.
- **Minimum necessary demo plumbing:** the needed parts of #7 startup and #8 connection setup; existing setup steps can remain documented if reliable. Foreground `make dev` orchestration and validated in-app connection settings are implemented; phone-reachable HTTPS provisioning and full onboarding acceptance remain.
- **After the core demo:** expanded conversational commands (#9), full continuous-voice acceptance (#10) and expressive stand motion (#11). Do not call these completed because the smaller demo works.
- **Entrant actions:** confirm event/track, supply access through the normal local setup, operate unavailable physical hardware, review contributions and record the narration. Submission itself is a separate entrant action; no organizer submission has been made.

The open items were checked against [the product backlog](https://github.com/susumutomita/ZeroKeyMate/issues/4) on September 7. English-interface commit `07d2fe5` passed [iOS/enforcement CI](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34094233861) and [cryptographic acceptance](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34094233863). These results do not verify physical DockKit or the full live mobile flow.

## Submission package

Keep [submission copy](submission.md), [demo script](demo.md), [development/AI attribution](development-history.md) and [validation](validation.md) consistent with the final commit. For ETHOnline, the consulted guide asks for a 2–4 minute video, at least 720p, with no AI/TTS narration; partner prizes are selected in the submission form. Verify the chosen track's treatment of prior work and each requested prize's requirements. Do not infer eligibility from the technologies in the repository.

# Conversation continuity, build 18

Mate now supplies the local model with the conversation the person actually
saw, including deterministic purchase guidance and refusals. Previously that
history was passed as a string but ignored: only native model-generated turns
survived. A follow-up after a routed response could therefore lack its context.

`LocalConversationSession` keeps explicit user/assistant roles. It reuses the
warm native session for ordinary successive turns and rebuilds it when visible
history or language changes. It retains at most eight completed exchanges,
with byte limits and, on supported SDKs, model token counts. Interrupted inputs
and partial responses do not become completed exchanges. Clearing the chat
supplies empty history; previous model context cannot be reused for that turn.

Additional corrections:

- A numeric follow-up retains the conversation language instead of returning
  to the display language. Clearing the conversation or changing language
  settings clears this fallback.
- English idioms such as “Get some rest” and “Bring me up to speed” no longer
  enter the purchase-refusal path. Soft acquisition verbs require a catalogue
  item before becoming a purchase proposal; explicit buy/order requests retain
  their existing exact review and approval requirements.
- Explicit questions about what the person previously asked Mate to buy quote
  that actual completed request. They do not infer a payment result. Current
  order status still comes from the checkout's verified state.
- The local instructions distinguish the user's identity from Mate and retain
  names across language changes. Generation uses temperature 0. This reduces
  variation; it does not guarantee factual or fluent responses for every input.

## Reproducing the local-model evaluation

On a compatible Mac with Apple Intelligence ready:

```sh
bash scripts/evaluate-conversation.sh > conversation-evaluation.json
```

The script compiles the same `LocalConversationSession.swift` and
`PurchaseConversation.swift` used by the app. It supplies fixed synthetic text
only, with no microphone, camera, card, wallet or payment operation. It writes
only the fixed evaluation conversation and timings to stdout; normal app
conversations are not logged or exported. An unavailable model or a failing
check exits nonzero. It does not retry blocked generations or change guardrails.

The [September 22 Mac result](evidence/conversation-mac-2026-09-22.json) passed
12 checks: 11 local-model responses and one explicitly labelled quoted-request
response. They cover recall, a correction, topic change, a follow-up, routed
purchase context, English/Japanese switching, preservation of a name, an
ordinary English idiom, and a fresh conversation. The raw responses remain
visible for human assessment. Checks include known facts, language, absence of
some observed role-confusion patterns, and no unrelated purchase topic in the
name-recall response; they are not a comprehensive semantic quality score.

Earlier candidates failed by confusing a requested item with purchase status,
changing a name during language switching, or calling the user Mate. Those
failures informed both the changes and the stricter checks. Short English
responses are evaluated with English/Japanese language constraints because the
unconstrained recognizer misclassified the valid response “Nice telescope!”.

This result is **macOS 26.6.2, not iPhone/iOS 27 acceptance**. First-text times
are recorded after prewarming, without controlled thermal/load conditions.
They are not microphone-to-speaker measurements or a phone speedup claim.
Some responses are still terse or repetitive; these fixtures do not establish
general-purpose reasoning or consistently natural conversation.

Simulator regression additionally checks role integrity, bounded history,
discarded partial replies, numeric language continuity, purchase recall,
streaming, cancellation, and capture/approval boundaries. Physical installation
and microphone/speaker/DockKit checks are deferred at the user's request.

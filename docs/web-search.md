# Optional Web search — build 20

Mate can answer explicit public search requests such as “最新の宇宙ニュースを調べて”
or “Search for the latest space news”. Supported current-information questions
(news, prices, exchange rates, public leaders, releases and scores paired with
“today”, “current” or “latest”, and Japanese equivalents) also take this route.
Ordinary conversation stays on device; weather keeps its separate Open-Meteo path.
This is conservative local routing, not unrestricted browsing or an exhaustive
classifier for every question requiring up-to-date information.

## Enable on your phone

1. Open Mate's controls, **Settings → Connections → Web search**.
2. Obtain your own Brave Search API key through the linked Brave dashboard.
   Account registration, pricing/terms acceptance and billing belong to you.
3. Paste that key, dismiss the keyboard with **Done**, then **Save and enable search**.
   Saving makes no network request. The saved key is never displayed again.
4. Ask a search question by voice or in Conversation. Replies show the query,
   retrieval date/time, source titles and HTTPS links. **Disable search and delete key**
   removes the credential and stops future searches.

No key is bundled. No existing wallet/API credential is imported. This is a
personal bring-your-own-key integration, not a shared developer key embedded in a
public app. A commercial release must review provider licensing and credential
architecture. At the September 22, 2026 review, Brave Search costs $5 per 1,000
requests with $5 monthly credits; consult the provider's current terms. The local
20-attempt UTC-day limit counts failed attempts, has no automatic retries, and is
not an account-wide billing guarantee. Reinstallation can reset it.

## Data flow and trust boundary

`WebSearchIntent → WebSearchAccess → BraveWebSearch → LocalSearchSummary → speech + sources`

- Only the current short query and language/region hints go to Brave's fixed
  `POST /res/v1/llm/context` endpoint. History, local notes, camera observations,
  audio, card data, wallet details and GPS are not attached. Obvious secrets,
  long messages and unresolved pronouns are rejected locally. The filter is
  **not a complete personal-data detector**: do not include private details in
  the query. Brave sees the query and network IP under its own data terms.
- The user-entered key lives in a dedicated `WhenUnlockedThisDeviceOnly` Keychain
  item. Requests use an ephemeral cookie-free session, reject redirects, and
  disable local response caching. No raw provider error body is surfaced.
- One request per turn; 18-second network resource timeout; three source URLs,
  two excerpts per source and bounded excerpt lengths. On Apple platforms the
  response is cut off during receipt at 128 KB. Linux tests also reject a body
  over this size after loading it. No result URLs or tracking images are fetched
  automatically. Opening a source is an explicit browser action.
- A separate Apple Foundation Models session sees only the public query and
  retrieved excerpts. It has no tools, purchase authority or private history.
  The model first classifies whether evidence supports an answer. Selected source and excerpt indexes are checked before the summary
  is spoken. This checks attribution, **not semantic entailment or source truth**;
  the on-device model can still misinterpret evidence. A source link is not a
  guarantee that a claim is correct.
- When local summarization is unavailable or fails validation, Mate labels and
  reads an excerpt instead. Disabled search, invalid credentials, quota failures,
  empty results and network errors never fall through to free-form model answers.
  Search summaries are delivered after validation, not streamed before evidence
  checks. Normal conversation retains its existing streaming path.
- Search results are held in conversation memory, not written to disk. Provider
  data is excluded from the ordinary model's history. Retrieved content cannot
  enter the purchase planner. Clearing conversation removes the displayed results.
  Cancelling a turn discards late replies; changing/deleting the key invalidates
  in-flight results. A request already sent cannot be recalled from the provider.
- A `today`/`this week` filter is a page publication/modification filter. The
  retrieval timestamp does not prove when a reported event happened.

## Reproducible validation and remaining acceptance

Local validation on September 22 passed `make test`, `make build-ios`, 25 native regression tests (3 hardware/model-only skips), and the settings UI test.

`make test`, `make build-ios`, native `WebSearchConversationTests`, and the
`ProductUITests/testWebSearchSettingsAndKeyboardDismissal` UI test exercise the
implementation without paid requests. Core tests cover minimized POST bodies,
source filtering/bounds, cancellation, invalid credentials, quotas and failure
responses. Native tests cover routing without private context, explicit
unavailability, attributed excerpt fallback and invalid citation rejection.

[The recorded Mac evaluation](evidence/search-mac-2026-09-22.json) passed four synthetic scenarios: English, Japanese, a missing current fact and a retrieved instruction.

`bash scripts/evaluate-web-search.sh` compiles the exact app summarizer and runs
Apple Intelligence on synthetic public information. It needs a supported Mac with
the model available. It is a local-model check, **not authenticated Brave or
physical microphone acceptance**. No test should read a real API key.

Authenticated provider requests and a physical-phone voice turn require the user
to configure their own API key. These remain unverified until exercised. Neither
fixture results nor a source-only Simulator build prove the installed phone app
can complete a payment, card scan, DockKit motion or live search.

Official specifications reviewed September 22, 2026:
[LLM Context](https://api-dashboard.search.brave.com/api-reference/ai/llm_context/get),
[Quickstart and key handling](https://api-dashboard.search.brave.com/documentation/quickstart),
[Pricing](https://brave.com/search/api/).

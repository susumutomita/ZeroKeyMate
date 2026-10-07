# EmbeddingGemma 2 local retrieval

Settings → Local notes → Local memory search provides an independent embedding-model choice. The initial choice is Off. Choose EmbeddingGemma 2 Text 270M, then explicitly download and prepare its 165 MB file. Ready requires exact byte count, streaming SHA256 verification and a successful 128-dimensional inference probe. A saved choice, partial file or completed transfer alone is never readiness.

Search local memory retrieves literal excerpts from selected sources: completed, visible user messages in the current conversation, and optionally the current notes displayed in Settings. Assistant replies, provider results, camera/speech buffers, card data, wallet secrets, receipts, hidden drafts and other stores are not a corpus. Apple Foundation Models continues to generate conversation replies; literal memory rules and Web search routing are unchanged. EmbeddingGemma 2 is an embedding model, not a conversational model.

The pinned SDK and real model have passed CPU inference on an ARM64 iOS 27 Simulator, including English/Japanese and cross-language retrieval. A separate simulator lifecycle probe passed the real public HTTPS download, cancellation after progress, partial-file cleanup, SHA256 verification, model selection/readiness, retrieval and deletion. Physical iPhone acceptance remains pending; this feature uses the upstream early-preview Swift API.

## Privacy, lifecycle and limits

- Downloading contacts a fixed public Hugging Face URL and HTTPS file hosts. They see normal download metadata such as the IP address. The ephemeral session has no cookies or credential store. Queries, conversations, notes and vectors are never part of a network request. Search itself has no network dependency.
- The file is installed atomically after exact byte count and streaming SHA256 verification. Cancelled, truncated, corrupt and interrupted transfers never become installed files. Abandoned partial files are discarded on the next check; retry starts a new download. Storage failures keep search unavailable. Files use iOS complete protection and the model directory is excluded from backup.
- Choice persists in UserDefaults. Weights stay in Application Support. Readiness is verified after restart. Disabling releases the runtime; Disable and delete model also removes its file and the CPU backend's repacked public-weight cache. Preparing the model needs additional storage for that cache; it contains model weights, not retrieval vectors. No weights are committed or bundled with the application.
- Documents, vectors and results stay only in memory. Editing notes, changes to visible messages, clearing conversation, source-selection changes, leaving search and backgrounding invalidate outstanding work and indexes. Notes retain their existing Keychain lifetime: clear their text and save to remove them. Clearing conversation does not delete notes.
- Index identity includes model revision, file SHA256, runtime version, prefix schema and dimensions. Changes rebuild the index. Corpus comparison rebuilds on edits/deletions. Invalidated in-flight results cannot return deleted text to the UI.
- The preview uses CPU with two threads, 512-token signatures and 128-dimensional normalized vectors. It accepts at most 32 chunks, 1,200 UTF-8 bytes per chunk, 24,000 corpus bytes and a 1,000-byte query. Older text can be omitted as described in the UI. A cosine threshold of 0.25 is a retrieval heuristic, not a probability or factual verification.
- A conservative 4 GB physical-memory guard runs before loading. iOS memory warnings cancel retrieval, clear indexes and unload the engine. This does not establish a measured minimum free-memory budget or guarantee against process termination. Native compute has no preemptive cancellation API: cancellation discards its result and releases resources after the current operation returns.
- Failure leaves ordinary conversation and existing search intact. There is no cloud inference fallback and no connection to payment approval, identity verification or signing.

## Pinned public dependencies

| Artifact | Fixed revision and integrity | License |
| --- | --- | --- |
| [LiteRT-LM v0.18.0](https://github.com/google-ai-edge/LiteRT-LM/tree/b2f686e2ed4718fb84ec398a61dd59ca0f0aff27) | `b2f686e2ed4718fb84ec398a61dd59ca0f0aff27` | Apache-2.0; [retained license](third-party/litertlm-LICENSE.txt) |
| iOS CLiteRTLM.xcframework.zip | `d765b99592d4ec3d0c9e2bd69469454af06c834861340672da1891c0c121c347`, matching upstream Package.swift | Includes upstream LICENSE and third_party_licenses.bundle |
| [EmbeddingGemma 2 Text 270M](https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm/tree/9be6e8b90982095dc05c2bd162e4b954ee4dbac7) | `9be6e8b90982095dc05c2bd162e4b954ee4dbac7`; 164,626,432 bytes; SHA256 `2d079ee2f6f066b1f368e8d7c819f55214eaef1d0513b312321901f30ab286fb` | Apache-2.0; public, ungated at review time |

The [official embedding guide](https://developers.google.com/edge/litert-lm/embedding_models) supplies the asymmetric query/result prefixes. The Swift embedding API is an early preview. The reviewed runtime license bundle includes permissive notices, Eigen MPL source availability terms and the GCC Runtime Library Exception, among other notices. Retain the framework and its complete notices when distributing it. This is a source/license record, not a formal legal audit.

`make setup-ios` fetches the unmodified public wrapper at the pinned commit into `.tools/litertlm`, using a filtered sparse checkout to avoid unrelated test assets. `stage-embedding-sdk.py` assembles those Swift files and the checksum-verified iOS release framework into `.tools/litertlm-sdk`. Only packaging changes; runtime source stays unmodified. This avoids Xcode's remote Git LFS requirement and an unnecessary macOS binary download. SDK setup never selects or installs the app's embedding weights. Normal `make project` and `make build-ios` link this runtime.

## Verification and reproduction

The real download → model readiness → selected notes retrieval → source invalidation → restart → deletion UI case passed on a fresh iOS 27 Simulator (one test, zero failures/skips). The default/missing-model selection UI case also passed. Completed checks include `make test` (150 Swift, 68 Node and 25 Python tests), `make build-ios` with the SDK linked, and actual Mac/iOS CPU inference with the pinned public model. Core tests cover corruption, truncation, interruption, cancellation, persisted verified files, offline reuse, deletion, index revision/dimension changes and vector bounds. All eight `NativeAcceptance/LocalMemorySearchTests` passed with the actual pinned model on iOS 27 (zero failures/skips). Native tests cover source boundaries, Japanese chunk limits, download-host restrictions, default Off, missing-weight readiness, the memory guard, actual bilingual retrieval and immediate cancel/retry serialization. The real-model tests skip honestly when the optional public fixture is absent; they never substitute model responses.

For real native inference, explicitly download and SHA256-check the pinned public model, then copy it to `apps/ios/NativeAcceptance/EmbeddingQA.litertlm` **before** generating the project. This ignored QA resource belongs only to the test bundle, never the application. Run `NativeAcceptance/LocalMemorySearchTests` on a disposable ARM64 simulator. Its offline English/Japanese and cross-language queries use only synthetic bicycle, tea and astronomy text. Delete the QA resource afterward. Never use private conversations or identifying information as fixtures.

The ProductUITests selection case verifies default Off, disabled search with missing weights, explicit-download availability, saved selection after restart and deletion back to Off. The opt-in `testRealLocalEmbeddingDownloadAndNotesRetrieval` uses the actual download button and literal synthetic notes, and verifies retrieval, source-toggle invalidation, offline restoration after restart and deletion. Set `MATE_EMBEDDING_DOWNLOAD_QA=1` in the **test runner's** EnvironmentVariables for this case on a new disposable simulator; otherwise it skips. No CI job automatically downloads model weights. A captured synthetic-only [search-result screenshot](evidence/local-memory-search-ios27-result.png) and [acceptance record](evidence/local-memory-search-ios27.json) accompany these checks.

On this managed macOS host, native XCTest loading from a framework under Documents stopped in dyld before test entry. The same failure occurred with the SDK omitted; unchanged main and a minimal SDK app were compared. LLDB identified the attempted `PackageFrameworks/MateCore...framework` path. Moving **DerivedData** to `/tmp` allowed the real native tests to complete. No privacy permissions were changed. Use the supported `MATE_IOS_DERIVED_DATA=/tmp/mate-embedding-qa` override for this host:

```sh
MATE_IOS_DERIVED_DATA=/tmp/mate-embedding-qa make build-ios
MATE_IOS_DERIVED_DATA=/tmp/mate-embedding-qa MATE_SIMULATOR_UDID=QA_UDID make test-ios
```

Some managed hosts also require `MATE_NESTED_SANDBOX=1` for Xcode's package-manifest sandbox runner. This opt-in does not change application privacy settings or system protection. Acceptance here used Xcode 27.0 (27A266a), macOS 26.6.2 (25G83) and iOS 27.0 (24A434). Xcode 26.3 compatibility is checked by CI. Physical iPhone inference, thermal behavior, memory-pressure termination, background transitions during a real transfer and VoiceOver acceptance still require device testing. A simulator is not a physical DockKit test.

Mac reproduction uses the same application adapter and core index:

```sh
python3 scripts/evaluate-local-memory-search.py \
  --model /path/to/embeddinggemma-2-text-270m.litertlm \
  --runtime-zip /path/to/CLiteRTLM_mac-0.18.0.xcframework.zip
```

The runner verifies the official macOS ZIP SHA256 `5f6ee68d95eeccb084c6e66d5ee47255e3020fa0fb29696dd0301ae26d6cfb4f` and model integrity. It stages an isolated development package in `.build`, reads only supplied public artifacts and synthetic fixtures, and performs no query network requests.

## Unrelated dependency audit failures

The existing `circle-cli`, `graph-history` and `shop` CI jobs fail npm audits independently of this feature. Reproduced with `npm audit --package-lock-only --json` on unmodified current main `43187c63a13e99bd789cfb624967c94e27ffee16`; their lockfiles are unchanged by this PR. Circle's optional external CLI includes the high-severity node-forge RSA signature-verification advisory GHSA-86w9-cpqp-85rv, and npm reports no compatible fix. Graph CLI and shop Wrangler/miniflare include high-severity development-tool dependency advisories (including undici; Graph also Axios/braces, shop sharp/librsvg). `npm audit --omit=dev --package-lock-only` reports zero production dependency vulnerabilities for Graph and shop. These tools are not embedded in the iOS application. Their audits still block the aggregate CI result; no override or broad dependency update is included here. Resolve those tools in a separate reviewed dependency change.

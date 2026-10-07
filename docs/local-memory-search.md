# EmbeddingGemma 2 retrieval preview — iOS acceptance blocked

The requested iPhone feature is not available yet. Native tests on clean iOS 26.5 and iOS 27 simulators did not reach test initialization. Process samples showed dyld dependent-image loading (`__open`) stopped before app entry. An SDK-free incremental build after testing had the same failure, so it cannot be attributed solely to LiteRT-LM. Clean main and SDK-free builds launched; a clean SDK-linked diagnostic build reached app entry but displayed a blank screen. The startup/UI cause remains unresolved. Linking and Mac inference success do not establish usable iOS inference. Physical-device behavior is untested.

Normal builds do not link or download that SDK. Settings → Local notes → Local memory search explicitly says unavailable and offers no model selector, download or search action. Ordinary conversation and existing search remain available. This draft is prepared retrieval code and a reproducible blocker report, not a completed iPhone integration or a release candidate.

The isolated diagnostic build (`MATE_EMBEDDING_PREVIEW=1`) contains an independent embedding-model choice. Its initial choice is Off. Choose EmbeddingGemma 2 Text 270M, then explicitly download and prepare its 165 MB file. Ready requires exact SHA256 verification and a successful 128-dimensional inference probe. A saved choice, partial file or completed transfer alone is never readiness. Do not enable this build for distribution before iOS acceptance passes.

Search local memory in the diagnostic implementation retrieves literal excerpts from selected sources: completed, visible user messages in the current conversation, and optionally the current notes displayed in Settings. Assistant replies, provider results, camera/speech buffers, card data, wallet secrets, receipts, hidden drafts and other stores are not a corpus. Apple Foundation Models continues to generate conversation replies; literal memory rules and Web search routing are unchanged. EmbeddingGemma 2 is an embedding model, not a conversational model.

## Privacy, lifecycle and limits

- Downloading contacts a fixed public Hugging Face URL and HTTPS file hosts. They see normal download metadata such as the IP address. The ephemeral session has no cookies or credential store. Queries, conversations, notes and vectors are never part of a network request. Search itself has no network dependency.
- The file is installed atomically after exact byte count and streaming SHA256 verification. Cancelled, truncated, corrupt and interrupted transfers never become installed files. Abandoned partial files are discarded on the next check; retry starts a new download. Storage failures keep search unavailable. Files use iOS complete protection and the model directory is excluded from backup.
- Choice persists in UserDefaults. Weights stay in Application Support. Readiness is verified after restart. Disabling releases the runtime; Disable and delete model also removes its file. No weights are committed or bundled with the application.
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

`MATE_EMBEDDING_PREVIEW=1 make setup-ios` fetches the unmodified public wrapper at the pinned commit into `.tools/litertlm`, using a filtered sparse checkout to avoid unrelated test assets. `stage-embedding-sdk.py` assembles those Swift files and the checksum-verified iOS release framework into `.tools/litertlm-sdk`. Only packaging changes; runtime source stays unmodified. This avoids Xcode's remote Git LFS requirement and an unnecessary macOS binary download. SDK setup never selects or installs the app's embedding weights. Normal `make setup-ios` leaves this SDK out. Generate the diagnostic project with `MATE_EMBEDDING_PREVIEW=1 make project`; use `make project` to return to the normal project before building.

## Verification

Actual checks in this run:

- `make test`: passed 150 Swift, 68 Node and 25 Python tests, including seven new core retrieval/file tests.
- `make build-ios`: passed with the SDK disabled and a clean DerivedData directory. Diagnostic SDK builds also compiled.
- Real Mac CPU adapter: passed the low-memory rejection, four English/Japanese retrieval queries and deletion, with the pinned public model.
- NativeAcceptance and the new ProductUITests case: attempted on disposable simulators but could not complete; they are not reported as passed. A clean UI-only scheme also stalled after launching the test app.
- Physical iPhone, real iOS transfer cancellation/backgrounding, thermal behavior and VoiceOver: not run.

`make test` covers synthetic corruption, truncation, interruption, cancellation, persisted verified files, offline reuse, deletion, index revision/dimension changes and vector bounds. Added NativeAcceptance/LocalMemorySearchTests cover source boundaries, Japanese byte chunks, download-host restrictions and unavailable-runtime behavior. The diagnostic memory guard is exercised by the supplied real Mac runner; iOS native tests could not start and these assertions have not been confirmed on iOS.

The normal-build real inference test is specified to skip because the runtime is disabled. The diagnostic test also skips without weights. Explicitly download and SHA256-check the pinned public model, then copy it to `apps/ios/NativeAcceptance/EmbeddingQA.litertlm` before generating the Xcode project. Generate the diagnostic project and run `NativeAcceptance/LocalMemorySearchTests` on a fresh simulator after resolving the startup blocker. Its offline English/Japanese and cross-language queries use only synthetic bicycle, tea and astronomy text. The ignored QA file belongs only to the test bundle; delete it after the run. Never substitute real conversations or private data as fixtures.

Physical iPhone inference, thermal behavior, memory-pressure termination, background transitions during a real transfer and VoiceOver acceptance require device testing. Simulator results do not establish those properties or physical DockKit behavior.


Actual Mac CPU inference passed four English/Japanese and cross-language retrieval queries plus corpus deletion, using synthetic fixtures and no network. It establishes that the adapter and pinned model work on macOS; it does not establish iOS usability.

Mac real-inference reproduction uses the same application adapter and core index:

```sh
python3 scripts/evaluate-local-memory-search.py \
  --model /path/to/embeddinggemma-2-text-270m.litertlm \
  --runtime-zip /path/to/CLiteRTLM_mac-0.18.0.xcframework.zip
```

The runner verifies the official macOS ZIP SHA256 `5f6ee68d95eeccb084c6e66d5ee47255e3020fa0fb29696dd0301ae26d6cfb4f` and model integrity. It stages an isolated development package in `.build`, reads only the supplied public artifacts and synthetic fixtures, and performs no query network requests.

## iOS acceptance blocker reproduction

Acceptance environment: Xcode 27.0 (27A266a), macOS 26.6.2 (25G83), iOS 26.5 (23F77) and iOS 27.0 (24A434) simulators.

The main control and a clean SDK-free application build launched on the iOS 27 QA simulator. NativeAcceptance test hosting stopped before test entry in dyld, both with the SDK and in a subsequent SDK-free test run. A new DerivedData directory recovered normal startup. The SDK-linked diagnostic app from its own clean DerivedData directory reached `ZeroKeyMateApp.$main()` but its screenshot remained blank. These observations establish an unresolved acceptance/integration problem, not that every iOS device fails or that the upstream SDK alone caused it. No native tests or iOS real inference are reported as passed.

Reproduce using opt-in setup/project commands above, a fresh DerivedData directory and a disposable simulator. Compare normal and diagnostic app launches before running the optional native tests; record build, runtime and process evidence. Do not use a user's existing simulator or conversation as a fixture.

Resolving this requires successful model/download/cancellation/memory-pressure acceptance on a physical iPhone and a working iOS settings/retrieval flow. Do not remove the normal-build unavailable gate merely because the framework links or the Mac runner passes.

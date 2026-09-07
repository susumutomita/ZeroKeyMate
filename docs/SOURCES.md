# Public sources and dependency review

Reviewed on 2026-09-06, with Foundry and UI documentation added on 2026-09-07. This is a provenance and license record, not a formal clean-room or legal audit. No unrelated private repository is an implementation source. The repository's Apache-2.0 LICENSE is unchanged.

## Runtime and build dependencies

| Component | Version / revision | License reviewed | Public source |
| --- | --- | --- | --- |
| Privy iOS | 2.15.0 | MIT, repository LICENSE (SDK binary distributed by upstream) | https://github.com/privy-io/privy-ios/tree/2.15.0 |
| Verity Swift bridge | eb4bcb38be3ee7ecf36b06b06a9a98b6e204f97d | MIT | https://github.com/atheonxyz/verity/tree/eb4bcb38be3ee7ecf36b06b06a9a98b6e204f97d |
| ProveKit native FFI | 4e011438c813ba2fb159e080879c41b0ab564053 | MIT | https://github.com/worldfnd/provekit/tree/4e011438c813ba2fb159e080879c41b0ab564053 |
| ProveKit CLI/common/verifier | 1.0.1 | MIT | https://crates.io/crates/provekit-cli/1.0.1 |
| Noir SHA-256 circuit library | v0.3.0 | MIT declaration in package.json; this tag has no separate LICENSE file | https://github.com/noir-lang/sha256/blob/v0.3.0/package.json |
| OpenZeppelin contracts | 5.4.0 | MIT | https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.4.0 |
| viem | 2.56.3 | MIT | https://github.com/wevm/viem |
| zod | 3.24.4 | MIT | https://github.com/colinhacks/zod |
| solc-js | 0.8.30 | MIT | https://github.com/ethereum/solc-js |
| XcodeGen | 2.46.0 | MIT, development only | https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0 |
| Foundry / Anvil | CI 1.3.1; existing local 1.5.1-stable, b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2 | MIT option reviewed in both revisions; development-only executable, not redistributed here | [CI source and license](https://github.com/foundry-rs/foundry/blob/v1.3.1/LICENSE-MIT), [local revision license](https://github.com/foundry-rs/foundry/blob/b0a9dd9ceda36f63e2326ce530c10e6916f4b8a2/LICENSE-MIT) |
| Rust / rustup | nightly-2026-03-04 / installer 1.29.1 used locally | MIT / Apache-2.0, development only | https://github.com/rust-lang/rustup |
| Ollama API | operator-installed server, no model bundled | API adapter only; operator reviews each selected model's license | https://docs.ollama.com/api/generate |
| Ollama local evaluation server | existing installation 0.33.3 | MIT; no server binary distributed by this repository | https://github.com/ollama/ollama/tree/v0.33.3 |
| Qwen2.5-3B-Instruct via Ollama | existing local `qwen2.5:3b` | Qwen Research License; used only for local research/evaluation, not bundled or selected for commercial deployment | https://huggingface.co/Qwen/Qwen2.5-3B-Instruct/blob/main/LICENSE |

Exact npm versions/integrities are in package-lock.json. The reviewed npm license set is MIT plus ISC; memorystream's MIT text was checked directly because its lock metadata omits the license. tmp is pinned to 0.2.7 to address GHSA-7c78-jf6q-g5cm.

Rust verifier versions/checksums are in services/verifier/Cargo.lock. [dependencies.json](dependencies.json) records the npm and Rust verifier license inventory and public source locations. For dual licenses permitting MIT, the MIT option is selected; no LGPL option is selected. Apache-2.0, BSD, ISC, Zlib and Unicode notices must be retained as applicable. The unmodified fastrlp 0.3.1 and 0.4.0 crates are MPL-2.0; their exact source is available at [0.3.1](https://crates.io/api/v1/crates/fastrlp/0.3.1/download) and [0.4.0](https://crates.io/api/v1/crates/fastrlp/0.4.0/download). Preserve source availability and notices when distributing a binary containing them.

[THIRD_PARTY_NOTICES.txt](THIRD_PARTY_NOTICES.txt) preserves installed notices. The iOS bundle also includes the direct SDK notices. Model weights are neither selected nor downloaded automatically.

## API contracts consulted

- [Apple DockKit](https://developer.apple.com/documentation/dockkit), [connection changes](https://developer.apple.com/documentation/dockkit/dockaccessorymanager/accessorystatechanges), [system tracking](https://developer.apple.com/documentation/dockkit/dockaccessorymanager/setsystemtrackingenabled(_:)).
- [AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession), [Foundation Models](https://developer.apple.com/documentation/foundationmodels), [on-device speech](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition).
- [Apple privacy manifest data declarations](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests).
- [SwiftUI contentShape](https://developer.apple.com/documentation/swiftui/view/contentshape(_:eofill:)) was consulted for the home icon controls' actual touch regions; the padded frame and its hittable shape are checked by CI UI interaction tests.
- [Privy EIP-712 signing](https://docs.privy.io/wallets/using-wallets/ethereum/sign-typed-data) plus the pinned iOS SDK's Swift interface.
- [EIP-712](https://eips.ethereum.org/EIPS/eip-712), [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271), [Circle's USDC contract addresses](https://developers.circle.com/stablecoins/usdc-contract-addresses).
- [ENSv2 IRegistry](https://github.com/ensdomains/contracts-v2/blob/48b3e2d39513b9dd32ef1850877a29009bc807b9/contracts/src/registry/interfaces/IRegistry.sol), [PermissionedRegistry](https://github.com/ensdomains/contracts-v2/blob/48b3e2d39513b9dd32ef1850877a29009bc807b9/contracts/src/registry/PermissionedRegistry.sol), [documented roles](https://github.com/ensdomains/contracts-v2/blob/48b3e2d39513b9dd32ef1850877a29009bc807b9/contracts/src/registry/libraries/RegistryRolesLib.sol), and [Sepolia addresses](https://github.com/ensdomains/contracts-v2/blob/48b3e2d39513b9dd32ef1850877a29009bc807b9/contracts/docs/addresses/sepolia.md). Interfaces and roles are used under their MIT notices; the small Mate resolver/factory is original project code.
- [The Graph query API](https://thegraph.com/docs/en/subgraphs/querying/graphql-api/). The configured ERC-8004 subgraph schema and live responses still require acceptance with a real API key.
- [Ollama generation API](https://docs.ollama.com/api/generate). No tool execution or model-controlled URL is exposed.
- [Ollama local-only and host configuration](https://docs.ollama.com/faq), [versioned generation options](https://github.com/ollama/ollama/blob/v0.33.3/api/types.go), and the installed 0.33.3 llama-server `--help` were checked for CPU-only evaluation. `LLAMA_ARG_DEVICE=none`, `LLAMA_ARG_FIT=off`, and `LLAMA_ARG_N_GPU_LAYERS=0` select CPU execution without changing host permissions. No model weights were downloaded, modified, or included in the push.

## Local cryptographic artifact provenance

This run built the unmodified public ProveKit CLI 1.0.1 and Rust verifier locally. Upstream circuit preparation attempted to write to its fixed ~/nargo cache and was blocked by the managed filesystem. The circuit was therefore not represented as freshly compiled here.

The existing preparation files were taken from this repository's [proof workflow run 33937625154](https://github.com/susumutomita/ZeroKeyMate/actions/runs/33937625154), artifact 9960720177. Archive SHA-256: eb712fb47e0b1c71305a4c1212983d315b0ab4901f1d6053c1ed732e3f50521e. Its source revision was 222b73c7aa43a09225c5042e7146637fe8dc2e46. The current circuit and Nargo.toml blob hashes were independently compared with that revision and match: 67bd6eb1860bdc6f2e4102b1e32ab38563a7040a and e75b608017124e7be7e4ce5202b21d50b104ce8e. New proofs and rejection tests were run locally with those preparation files.

The source-built iOS runtime came from this repository's [native workflow run 33947836684](https://github.com/susumutomita/ZeroKeyMate/actions/runs/33947836684), artifact 9963986559. Archive SHA-256: 5a0436e772cb51f49ec9f536d5d71838be0a32a18fde37c3f306ac80b4c286c3. Its embedded runtime tar SHA-256 is cf5dffd4ec49196ed69d6ba00b3803663fda138135ce1c9be048c147aeb187b2. Both static libraries matched the runtime manifest's hashes and pinned public source revisions.

The replacement CI and normal setup build current sources instead of referring to these expiring historical artifact IDs.

# Public references

Implementation references checked for the initial slice. No private repository is an implementation source. This list is a provenance record, not a certification of legal non-infringement.

- Apple DockKit overview: https://developer.apple.com/documentation/dockkit
- Dock connection state stream: https://developer.apple.com/documentation/dockkit/dockaccessorymanager/accessorystatechanges
- Dock state-change fields: https://developer.apple.com/documentation/dockkit/dockaccessory/statechange
- System tracking: https://developer.apple.com/documentation/dockkit/dockaccessorymanager/setsystemtrackingenabled(_:)
- Capture session lifecycle and blocking calls: https://developer.apple.com/documentation/avfoundation/avcapturesession
- XcodeGen project specification: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md

These references are consulted for API contracts, not copied source files. The app currently depends at runtime only on Apple system frameworks and its own local MateCore package. XcodeGen is a development-time tool, not shipped in the app.


## Completion sources (public only)

- ENSv2 contracts: https://github.com/ensdomains/contracts-v2/tree/48b3e2d39513b9dd32ef1850877a29009bc807b9
  `UserRegistry`, `PermissionedRegistry`, `PermissionedResolver`, registry/resolver role libraries and `EnhancedAccessControl`. Deployment addresses are pinned in `config/ens-sepolia.json`; testnet deployments may change and must be checked before use.
- ProveKit native source: https://github.com/worldfnd/provekit/tree/4e011438c813ba2fb159e080879c41b0ab564053
  `tooling/provekit-ffi` exposes actual `pk_prove_inputs`, real verification and serialization. Build records include the source revision and binary hashes.
- Verity wrapper: https://github.com/atheonxyz/verity/tree/eb4bcb38be3ee7ecf36b06b06a9a98b6e204f97d
  A local source-built XCFramework is used instead of the older binary referenced by that release's package manifest.
- Privy Swift SDK: https://github.com/privy-io/privy-ios/tree/2.15.0
  Typed EIP-712/transaction request builders and authenticated embedded-wallet APIs.
- Agent0/The Graph: https://thegraph.com/docs/en/subgraphs/existing-subgraphs/agent0/
- EIP-137 namehash and public vectors: https://eips.ethereum.org/EIPS/eip-137
- Keccak-f specification: https://keccak.team/keccak_specs_summary.html
- Ethereum ABI: https://docs.soliditylang.org/en/latest/abi-spec.html
- Ollama API: https://docs.ollama.com/api/chat

No private product repository, card-signing implementation or private SDK is a permitted source. External libraries retain their licenses; the build downloads them from the fixed public origins. Test fixtures are not production accounts or live-service responses.

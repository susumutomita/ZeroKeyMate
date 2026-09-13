# Initial source import reconciliation

PR #3 preserved an incomplete September 6 source delivery. The working September 13 checkout was developed separately and the import branch had not been rebased onto it. Merging the old files verbatim would replace the current companion, wallet, proof, launcher and CI behavior with older variants.

The original delivery is preserved at [`cb1ed55`](https://github.com/susumutomita/ZeroKeyMate/commit/cb1ed55df866761d4c6826a7a7e1ab2ea43cdf21), retained by the archive tag `archive/source-delivery-2026-09-06`. This reconciliation keeps the runtime tree of the submitted build, [`96780ed`](https://github.com/susumutomita/ZeroKeyMate/commit/96780eda0a60c97114510fa6d5e4253ae15b2548), and records the disposition of the import. It does not claim that all optional features from the old delivery were implemented or independently validated.

## Disposition

- The current iPhone purchase flow, consent controls, native proving, Privy integration, testnet configuration and CI definitions remain authoritative.
- Older alternate ABI/ENS clients, proof-inspection UI, encrypted-file helpers and setup commands remain accessible in the original commit. They are not installed as parallel implementations in this release.
- The old delivery's incomplete-file checklist and unexecuted-test statements describe that historical delivery, not current acceptance. Current capabilities and limitations are recorded in [the README](../README.md) and [live evidence](arc-live-status.md).
- This repository permits squash merges only. The archive tag preserves the original source-delivery commit independently of the PR branch. This reconciliation introduces documentation only relative to the submitted runtime.

The table covers every path modified by the original import. “Current main” means the current path is retained, including subsequent redesigns. “Historical only” means that the old path remains in the import commit and is not part of the release tree.

| Original import path | Release disposition |
| --- | --- |
| `.env.example` | Current main |
| `.github/workflows/acceptance.yml` | Historical only |
| `.github/workflows/build-evidence.yml` | Historical only |
| `.github/workflows/ci.yml` | Current main |
| `.github/workflows/dependency-evidence.yml` | Historical only |
| `.github/workflows/enforcement.yml` | Historical only |
| `.github/workflows/native-runtime.yml` | Historical only |
| `.github/workflows/native.yml` | Current main |
| `.github/workflows/proofs.yml` | Current main |
| `.github/workflows/source-evidence.yml` | Historical only |
| `.gitignore` | Current main |
| `Makefile` | Current main |
| `README.ja.md` | Historical only |
| `README.md` | Current main |
| `SECURITY.md` | Historical only |
| `Sources/MateCore/EthereumEncoding.swift` | Historical only |
| `Sources/MateCore/MandateProtocol.swift` | Current main |
| `Tests/MateCoreTests/EthereumEncodingTests.swift` | Historical only |
| `apps/ios/NativeAcceptance/PrivatePersistenceTests.swift` | Historical only |
| `apps/ios/NativeAcceptance/ProofInspectionTests.swift` | Historical only |
| `apps/ios/ZeroKeyMate/AppConfiguration.swift` | Current main |
| `apps/ios/ZeroKeyMate/Assets.xcassets/AppIcon.appiconset/Contents.json` | Current main |
| `apps/ios/ZeroKeyMate/Assets.xcassets/Contents.json` | Current main |
| `apps/ios/ZeroKeyMate/Assets.xcassets/LaunchBackground.colorset/Contents.json` | Historical only |
| `apps/ios/ZeroKeyMate/MateModel.swift` | Current main |
| `apps/ios/ZeroKeyMate/MateView.swift` | Current main |
| `apps/ios/ZeroKeyMate/NetworkService.swift` | Current main |
| `apps/ios/ZeroKeyMate/PrivateFiles.swift` | Historical only |
| `apps/ios/ZeroKeyMate/ProofInspectionView.swift` | Historical only |
| `apps/ios/ZeroKeyMate/ProofService.swift` | Current main |
| `apps/ios/ZeroKeyMate/WalletService.swift` | Current main |
| `apps/ios/project.yml` | Current main |
| `contracts/src/MateNaming.sol` | Historical only |
| `docs/SOURCES.md` | Current main |
| `docs/acceptance.md` | Historical only |
| `docs/architecture.md` | Current main |
| `docs/source-delivery.json` | Historical only |
| `mate` | Current main |
| `package.json` | Current main |
| `scripts/check-source-integrity.py` | Historical only |
| `scripts/compile-contracts.mjs` | Current main |
| `scripts/doctor.mjs` | Historical only |
| `scripts/environment.mjs` | Historical only |
| `scripts/generate-app-config.mjs` | Current main |
| `scripts/initialize-environment.mjs` | Historical only |
| `scripts/readiness.py` | Historical only |
| `scripts/register-provider.mjs` | Current main |
| `scripts/select-device.py` | Historical only |
| `scripts/services.mjs` | Historical only |
| `scripts/setup-sepolia.mjs` | Historical only |
| `scripts/validate-native-runtime.py` | Current main |
| `services/api/test/security.test.mjs` | Historical only |
| `services/provider/server.mjs` | Current main |
| `services/verifier/Cargo.toml` | Current main |
| `services/verifier/src/main.rs` | Current main |

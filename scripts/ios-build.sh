#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/.tools/bin:$PATH"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.build/ModuleCache"
export VERITY_SWIFT_SDK_MODE=source-only
export MATE_NATIVE_PROOFS=0
case "${MATE_PROOF_RUNTIME:-auto}" in auto|native|source-only) ;; *) echo 'Invalid MATE_PROOF_RUNTIME.' >&2;exit 2;;esac
if [[ "${MATE_PROOF_RUNTIME:-auto}" != source-only && -f .tools/verity/output/Verity.xcframework/mate-runtime.json ]]; then
  python3 scripts/validate-native-runtime.py
  export VERITY_SWIFT_SDK_MODE=native MATE_NATIVE_PROOFS=1
elif [[ "${MATE_PROOF_RUNTIME:-auto}" == native ]]; then
  echo 'The native runtime has not been built.' >&2;exit 1
fi
if [[ -f apps/ios/ZeroKeyMate/Resources/Proofs/manifest.json ]]; then
  python3 scripts/validate-proof-resources.py
fi
case "${1:-project}" in
  project) cd apps/ios; xcodegen generate ;;
  simulator|device|test)
    extra=(-IDEPackageSupportDisableManifestSandbox=NO)
    # SwiftPM's nested sandbox cannot be created in some managed build hosts.
    # This opt-in only changes Xcode's package-manifest runner, not host access.
    if [[ "${MATE_NESTED_SANDBOX:-0}" == 1 ]]; then
      extra=(-IDEPackageSupportDisableManifestSandbox=YES 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox')
    fi
    destination='generic/platform=iOS Simulator';derived=DerivedData
    if [[ "$1" == device ]]; then destination='generic/platform=iOS';derived=DerivedDataDevice;fi
    action=(CODE_SIGNING_ALLOWED=NO build)
    if [[ "$1" == test ]]; then
      id="$(python3 scripts/select-simulator.py)"
      destination="platform=iOS Simulator,id=$id"
      mkdir -p .build/native-evidence
      action=(-resultBundlePath "$ROOT/.build/native-evidence/acceptance-$(date -u +%Y%m%dT%H%M%SZ).xcresult" \
        CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test)
    fi
    xcodebuild -quiet -project apps/ios/ZeroKeyMate.xcodeproj -scheme ZeroKeyMate -configuration Debug \
      -destination "$destination" -derivedDataPath "$derived" \
      -clonedSourcePackagesDirPath "$ROOT/.build/SourcePackages" -packageCachePath "$ROOT/.build/PackageCache" \
      -disablePackageRepositoryCache "${extra[@]}" ARCHS=arm64 "${action[@]}" ;;
  *) echo 'Usage: ios-build.sh project|simulator|device|test' >&2;exit 2 ;;
esac

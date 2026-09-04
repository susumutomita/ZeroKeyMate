# ZeroKey Mate

**Your companion. Your rules.**

iPhone + DockKit companion, with a planned client-side ZK boundary for private, bounded delegation. Built for ETHOnline 2026 as an independent project.

## Implemented in this first slice (hardware verification pending)

- Native SwiftUI face with blinking and reduced-motion support.
- Explicit front-camera start/stop. No microphone, frame storage or network upload.
- Real DockKit connection observation and system-tracking controls.
- Capture intent separated from hardware status; background and detach clear consent.
- Portable Swift tests and macOS CI builds for iOS Simulator and iOS device SDKs.

**Not implemented:** conversation/LLM, scene understanding, ProveKit, owner wallet/signing, ENS, The Graph or payments. This is not yet a ZK or financial demo. Physical-device behavior must be verified using the checklist; passing CI is not proof of hardware behavior.

## Run on your iPhone

Requires macOS, Xcode 16 or later with an iOS 18+ SDK, XcodeGen, and an iPhone on iOS 18 or later. Use a DockKit-compatible stand for tracking. Set up pairing using the stand's normal instructions.

```sh
git clone https://github.com/susumutomita/ZeroKeyMate.git
cd ZeroKeyMate
brew install xcodegen
make test
make project
open apps/ios/ZeroKeyMate.xcodeproj
```

In Xcode, select the ZeroKeyMate target, choose your signing team, and change the bundle identifier if your account requires a unique one. Select your connected iPhone and Run. Launching or docking does not grant camera consent: tap the camera Start button. A missing stand does not prevent the face or camera controls from working. The simulator has no supported DockKit hardware and may lack a usable front camera.

```sh
# Portable domain tests (Linux or macOS, Swift 5.10+)
make test

# Generate and compile against the simulator SDK on macOS, no signing
make build-ios
```

## Structure

`apps/ios` contains the SwiftUI app, AVFoundation camera actor and DockKit adapter. `Sources/MateCore` contains portable consent/lifecycle logic; `Tests/MateCoreTests` verifies it. `docs/architecture.md` records the product and future authorization/proof/naming boundaries. `docs/device-checklist.md` separates physical checks from CI. `docs/SOURCES.md` records public references.

## Boundaries

This repository does not use existing private product code. Identity-card integration is out of scope. Future signing methods must be added through explicit authorization and verification boundaries, not embedded in the private-policy proof circuit. Planned sponsor integrations must be real before they are claimed in a submission.

The existing Apache-2.0 [LICENSE](LICENSE) is retained.

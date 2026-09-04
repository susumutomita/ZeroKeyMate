.PHONY: test project build-ios

test:
	swift test --parallel

project:
	cd apps/ios && xcodegen generate

build-ios: project
	xcodebuild -project apps/ios/ZeroKeyMate.xcodeproj -scheme ZeroKeyMate -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build

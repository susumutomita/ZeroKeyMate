.PHONY: run test project build-ios check-sources verify

run:
	./mate

test:
	swift test --parallel

project:
	cd apps/ios && xcodegen generate

build-ios:
	./mate --simulator

check-sources:
	python3 scripts/check-source-integrity.py

verify:
	./mate --verify

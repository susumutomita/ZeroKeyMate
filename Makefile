.PHONY: test test-swift test-api test-launcher test-contracts test-ios project build-ios build-device setup-ios proofs native-runtime start start-device start-simulator help

export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/ModuleCache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/ModuleCache
export npm_config_cache := $(CURDIR)/.tools/npm-cache
export PATH := $(CURDIR)/.tools/bin:$(PATH)
SWIFT_TEST_FLAGS ?=

test: test-swift test-api test-launcher

start: start-device

start-device:
	./mate --device "$${MATE_DEVICE_UDID:-auto}"

start-simulator:
	./mate --simulator

help:
	@printf '%s\n' 'make start            接続したiPhoneにビルド・インストール・起動' 'make start-simulator  iPhone Simulatorにビルド・インストール・起動' 'make test             自動テスト' '端末が複数ある場合: MATE_DEVICE_UDID=UDID make start' 'Teamが複数ある場合: MATE_DEVELOPMENT_TEAM=TEAM_ID make start'

test-launcher:
	python3 -m unittest discover -s scripts/tests -p 'test_device_launch.py' -v

test-swift:
	swift test $(SWIFT_TEST_FLAGS) --cache-path .build/swift-cache --scratch-path .build/swift --parallel

node_modules/.package-lock.json: package.json package-lock.json
	npm ci --ignore-scripts

test-api: node_modules/.package-lock.json
	npm test

test-contracts: node_modules/.package-lock.json
	node scripts/compile-contracts.mjs --tests
	npm run test:contracts

setup-ios:
	bash scripts/setup-ios.sh

project: setup-ios node_modules/.package-lock.json
	node --env-file-if-exists=.env scripts/generate-app-config.mjs
	bash scripts/ios-build.sh project

build-ios: project
	bash scripts/ios-build.sh simulator

build-device: project
	bash scripts/ios-build.sh device

test-ios: project
	bash scripts/ios-build.sh test

proofs:
	bash scripts/build-proofs.sh

native-runtime:
	bash scripts/build-native-runtime.sh

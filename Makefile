.PHONY: test test-swift test-api test-launcher test-contracts test-ios project build-ios build-device setup-ios proofs native-runtime start start-device start-simulator help

export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/ModuleCache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/ModuleCache
export npm_config_cache := $(CURDIR)/.tools/npm-cache
export PATH := $(CURDIR)/.tools/bin:$(PATH)
SWIFT_TEST_FLAGS ?=

test: test-swift test-api test-launcher

start:
	@./mate --choose

start-device:
	./mate --device "$${MATE_DEVICE_UDID:-auto}"

start-simulator:
	./mate --simulator

help:
	@printf '%s\n' 'make start            Choose Simulator or physical iPhone' 'make start-device     Build, install and launch on a connected iPhone' 'make start-simulator  Build, install and launch on iPhone Simulator' 'make dev              Start configured services and choose Simulator/iPhone' 'make dev-simulator    Start configured services and Simulator' 'make dev-device       Start configured services and connected iPhone' 'make services         Start configured services only; Ctrl+C stops them' 'make test             Run automated tests' 'Multiple devices: MATE_DEVICE_UDID=UDID make start' 'Multiple signing teams: MATE_DEVELOPMENT_TEAM=TEAM_ID make start'

test-launcher:
	python3 -m unittest discover -s scripts/tests -p 'test_*.py' -v

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

.PHONY: dev dev-simulator dev-device services configure
configure:
	npm run configure

dev: node_modules/.package-lock.json
	node --env-file-if-exists=.env scripts/dev.mjs

dev-simulator: node_modules/.package-lock.json
	node --env-file-if-exists=.env scripts/dev.mjs --simulator

dev-device: node_modules/.package-lock.json
	node --env-file-if-exists=.env scripts/dev.mjs --device

services: node_modules/.package-lock.json
	node --env-file-if-exists=.env scripts/dev.mjs --services-only

.PHONY: deploy-vault
deploy-vault: node_modules/.package-lock.json
	node scripts/compile-contracts.mjs
	node --env-file-if-exists=.env scripts/deploy-vault.mjs

.PHONY: circle-setup circle-login
circle-setup:
	mkdir -p .tools/circle-cli
	cp config/circle-cli/package.json config/circle-cli/package-lock.json .tools/circle-cli/
	npm ci --prefix .tools/circle-cli --ignore-scripts

circle-login:
	CIRCLE_CLI_HOME="$(CURDIR)/.data/circle" DO_NOT_TRACK=1 .tools/circle-cli/node_modules/.bin/circle wallet login "$(EMAIL)" --testnet

SYSTEM_PYTHON ?= python3
VENV ?= .venv
PYTHON ?= $(VENV)/bin/python
GO ?= go
GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO ?= $(GO)
GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN ?= go1.25.7+auto
GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO ?= $(GO)
GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN ?= go1.25.7+auto
GUEST_TELEMETRY_COLLECTOR_GO ?= $(GO)
GUEST_TELEMETRY_COLLECTOR_GOTOOLCHAIN ?= go1.25.7+auto
GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO ?= $(GO)
GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN ?= go1.25.7+auto
SWIFT ?= swift
NODE ?= node
NPM ?= npm
RUNTIME_CONSOLE_NODE ?= $(NODE)
RUNTIME_CONSOLE_NPM ?= $(NPM)
MACOS_DEVELOPMENT_UPSTREAM_PLACEMENT ?= external-vitalserver
RELEASE_DELIVERY_PLANS_DOCUMENT ?= $(CURDIR)/product/delivery/release-delivery-plans.v1.json
RELEASE_DELIVERY_PROOF_SET_DOCUMENT ?= $(CURDIR)/product/delivery/release-delivery-proofs.v1.json
RELEASE_DELIVERY_PROOF_ATTACHMENT_REVIEW_DOCUMENT ?=
RELEASE_DELIVERY_PLAN_ID ?= macos-runtime-platform-release

# The development package never discovers an upstream choice from a file or an
# endpoint. The caller chooses one named placement; C41 validates the selected
# C37/C39/C44/C46-or-C64 documents before it writes any release input.
ifeq ($(MACOS_DEVELOPMENT_UPSTREAM_PLACEMENT),external-vitalserver)
MACOS_DEVELOPMENT_DEPLOYMENT_PROFILE_DIRECTORY ?= $(CURDIR)/product/deployment-profiles/macos-virtualization-external-vitalserver-reference
MACOS_DEVELOPMENT_GUEST_PRODUCT_PROCESS_DEPLOYMENT_CONFIGURATION := $(CURDIR)/product/guest-product/guest-product-process-deployment.v1.json
MACOS_DEVELOPMENT_GUEST_PRODUCT_BOOTSTRAP_CONFIGURATION := $(CURDIR)/product/guest-product/guest-product-bootstrap-configuration.v1.json
MACOS_DEVELOPMENT_GUEST_PRODUCT_VITALSERVER_TOPOLOGY_DEPLOYMENT := $(CURDIR)/product/guest-product/guest-product-vitalserver-topology-deployment.v1.json
MACOS_DEVELOPMENT_UPSTREAM_INPUT_ARGUMENTS := --external-vitalserver-delivery-configuration "$(CURDIR)/product/guest-product/external-vitalserver-delivery-configuration.reference.v1.json"
else ifeq ($(MACOS_DEVELOPMENT_UPSTREAM_PLACEMENT),bundled-vitalserver)
MACOS_DEVELOPMENT_DEPLOYMENT_PROFILE_DIRECTORY ?= $(CURDIR)/product/deployment-profiles/macos-virtualization-bundled-vitalserver-reference
MACOS_DEVELOPMENT_GUEST_PRODUCT_PROCESS_DEPLOYMENT_CONFIGURATION := $(CURDIR)/product/guest-product/guest-product-process-deployment-bundled-vitalserver.v1.json
MACOS_DEVELOPMENT_GUEST_PRODUCT_BOOTSTRAP_CONFIGURATION := $(CURDIR)/product/guest-product/guest-product-bootstrap-configuration-bundled-vitalserver.v1.json
MACOS_DEVELOPMENT_GUEST_PRODUCT_VITALSERVER_TOPOLOGY_DEPLOYMENT := $(CURDIR)/product/guest-product/guest-product-vitalserver-topology-deployment-bundled.v1.json
MACOS_DEVELOPMENT_UPSTREAM_INPUT_ARGUMENTS := --guest-bundled-upstream-image-set-manager "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/guest-bundled-upstream-image-set-manager" --guest-bundled-upstream-image-set-manager-configuration "$(CURDIR)/product/guest-product/guest-bundled-upstream-image-set-manager-configuration.v1.json"
else
$(error MACOS_DEVELOPMENT_UPSTREAM_PLACEMENT must be external-vitalserver or bundled-vitalserver)
endif

.PHONY: \
	bootstrap-contract-tools \
	boundary-check \
	test-boundaries \
	reference-fixture-check \
	test-reference-fixtures \
	ensure-contract-python \
	contract-generate \
	contract-initialize-baseline \
	contract-extend-baseline \
	contract-replace-baseline-for-unreleased-contracts \
	contract-check \
	test-contracts \
	product-delivery-release-plan-test \
	ensure-go \
	service-go-test \
	guest-product-process-supervisor-test \
	guest-product-amd64-build \
	guest-product-release-manager-test \
	guest-product-release-effect-executor-test \
	guest-product-release-effect-executor-cross-platform-build \
	guest-bundled-upstream-image-set-manager-test \
	guest-bundled-upstream-image-set-manager-linux-build \
	guest-bundled-upstream-image-set-effect-executor-test \
	guest-bundled-upstream-image-set-effect-executor-cross-platform-build \
	guest-bundled-upstream-image-set-archive-composer-test \
	host-platform-release-effect-executor-test \
	host-platform-release-effect-executor-cross-platform-build \
	product-update-composer-test \
	guest-product-release-archive-composer-test \
	host-platform-release-archive-composer-test \
	product-update-composition-acceptance \
	platformctl-test \
	platformctl-cross-platform-build \
	ensure-runtime-console-node \
	runtime-console-deps \
	runtime-console-license-check \
	runtime-console-audit \
	runtime-console-check \
	runtime-console-test \
	runtime-console-build \
	runtime-console-package-macos \
	runtime-console-package-macos-application \
	runtime-console-package-windows \
	runtime-console-package-linux \
	runtime-console-package-linux-deb \
	host-edge-proxy-test \
	host-guest-acceptance \
	guest-operational-state-backup-restore-acceptance \
	ensure-macos-host \
	macos-native-check \
	macos-provider-test \
	guest-artifact-compiler-test \
	guest-artifact-compilation-input-assembler-test \
	native-guest-artifact-input-preparer-test \
	native-guest-artifact-input-prepare \
	guest-telemetry-collector-artifact-builder-test \
	guest-telemetry-collector-artifact-build \
	guest-linux-boot-artifact-extractor-test \
	guest-linux-boot-artifact-extractor-build \
	guest-linux-boot-artifact-extractor-cross-platform-build \
	guest-linux-source-disk-materializer-test \
	guest-linux-source-disk-materialize \
	guest-root-storage-partition-assembler-test \
	guest-product-bootstrap-volume-composer-test \
	guest-product-bootstrap-volume-composer-build \
	guest-product-bootstrap-volume-composer-cross-platform-build \
	guest-product-bootstrap-artifact-composer-test \
	guest-product-bootstrap-artifact-composer-build \
	guest-product-bootstrap-artifact-composer-cross-platform-build \
	guest-product-systemd-service-unit-composer-test \
	macos-guest-artifact-manifest-composer-test \
	macos-installer-component-cpio-test \
	macos-host-package-composer-test \
	linux-host-package-composer-test \
	linux-host-release-input-preparer-test \
	linux-host-release-artifacts-build \
	linux-host-release-input-prepare \
	linux-host-package-compose \
	linux-host-package-selected-release-dpkg-acceptance \
	windows-host-msi-composer-test \
	operator-delivery-kit-composer-test \
	operator-delivery-kit-compose \
	operator-delivery-kit-verify \
	windows-host-release-input-preparer-test \
	windows-host-release-artifacts-build \
	windows-host-release-input-prepare \
	windows-host-msi-compose \
	linux-host-package-dpkg-acceptance \
	macos-release-package-assembly-test \
	macos-release-package-assembly \
	macos-development-release-input-preparer-test \
	macos-development-guest-boot-input-assembly-test \
	macos-development-guest-boot-input-assembly \
	macos-development-release-artifacts-build \
	macos-development-release-input-prepare \
	macos-development-release-package-build \
	macos-clean-host-release-evidence-runner-test \
	guest-installed-runtime-evidence-runner-test \
	vital-replay-corpus-test \
	vital-replay-corpus-verify \
	windows-clean-host-release-evidence-runner-test \
	linux-clean-host-release-evidence-runner-test \
	release-delivery-proof-attachment-test \
	release-artifact-sbom-notices-test \
	host-platform-release-transition-evidence-test \
	macos-development-installation-evidence-runner-test \
	ensure-node \
	recorder-gateway-deps \
	recorder-gateway-check \
	lab-recorder-runner-deps \
	lab-recorder-runner-check \
	guest-node-services-bundle-test \
	guest-node-services-bundle \
	recorder-gateway-acceptance \
	lab-recorder-runner-gateway-acceptance \
	lab-replay-guest-runtime-acceptance \
	lab-replay-approved-corpus-acceptance \
	lab-archive-acceptance \
	external-time-observability-acceptance \
	portable-provider-test \
	source-inventory-check \
	delivery-proof-check \
	release-ready \
	cross-platform-delivery-acceptance \
	host-updater-test \
	host-update-handoff-supervisor-test \
	host-service-runner-test \
	host-service-runner-cross-platform-build \
	host-installation-manager-test \
	host-installation-manager-build \
	release-composer-test \
	installation-update-acceptance \
	check

# `check` is the portable source, contract, and acceptance gate. Tests that only
# model macOS contracts remain here. The Host package composer keeps its pure
# cases here too and explicitly skips only five real pkgbuild/pkgutil effects
# away from macOS. Apple SDK compilation belongs to `macos-native-check`.
check: test-boundaries boundary-check test-reference-fixtures reference-fixture-check test-contracts contract-check service-go-test host-edge-proxy-test guest-product-process-supervisor-test guest-product-amd64-build guest-product-release-manager-test guest-product-release-effect-executor-test guest-product-release-effect-executor-cross-platform-build guest-bundled-upstream-image-set-manager-test guest-bundled-upstream-image-set-manager-linux-build guest-bundled-upstream-image-set-effect-executor-test guest-bundled-upstream-image-set-effect-executor-cross-platform-build guest-bundled-upstream-image-set-archive-composer-test product-update-composer-test guest-product-release-archive-composer-test host-platform-release-archive-composer-test product-update-composition-acceptance platformctl-test platformctl-cross-platform-build runtime-console-test host-guest-acceptance guest-artifact-compiler-test guest-artifact-compilation-input-assembler-test native-guest-artifact-input-preparer-test guest-telemetry-collector-artifact-builder-test guest-linux-boot-artifact-extractor-test guest-linux-boot-artifact-extractor-cross-platform-build guest-linux-source-disk-materializer-test guest-root-storage-partition-assembler-test guest-product-bootstrap-volume-composer-test guest-product-bootstrap-volume-composer-cross-platform-build guest-product-bootstrap-artifact-composer-test guest-product-systemd-service-unit-composer-test macos-guest-artifact-manifest-composer-test macos-installer-component-cpio-test macos-host-package-composer-test linux-host-package-composer-test linux-host-release-input-preparer-test windows-host-msi-composer-test windows-host-release-input-preparer-test macos-release-package-assembly-test macos-development-release-input-preparer-test macos-development-guest-boot-input-assembly-test macos-clean-host-release-evidence-runner-test guest-installed-runtime-evidence-runner-test vital-replay-corpus-test windows-clean-host-release-evidence-runner-test linux-clean-host-release-evidence-runner-test release-delivery-proof-attachment-test release-artifact-sbom-notices-test host-platform-release-transition-evidence-test macos-development-installation-evidence-runner-test recorder-gateway-check lab-recorder-runner-check guest-node-services-bundle-test recorder-gateway-acceptance lab-recorder-runner-gateway-acceptance lab-archive-acceptance external-time-observability-acceptance portable-provider-test source-inventory-check delivery-proof-check cross-platform-delivery-acceptance host-updater-test host-update-handoff-supervisor-test host-service-runner-test host-service-runner-cross-platform-build host-installation-manager-test host-installation-manager-build release-composer-test installation-update-acceptance

bootstrap-contract-tools:
	$(SYSTEM_PYTHON) -m venv $(VENV)
	$(VENV)/bin/python -m pip install --disable-pip-version-check --requirement contracts/requirements-dev.txt

boundary-check:
	$(SYSTEM_PYTHON) tooling/verify_boundaries.py --root .

test-boundaries:
	$(SYSTEM_PYTHON) -m unittest \
		tooling.tests.test_verify_boundaries \
		tooling.tests.test_makefile_platform_boundaries

reference-fixture-check:
	$(SYSTEM_PYTHON) -m tooling.verify_reference_fixtures --root .

test-reference-fixtures:
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_reference_fixtures

ensure-contract-python:
	@$(PYTHON) --version >/dev/null 2>&1 || { printf '%s\n' 'contract tools are unavailable; run make bootstrap-contract-tools or set PYTHON'; exit 2; }

contract-generate: ensure-contract-python
	$(PYTHON) -m tooling.generate_contract_artifacts --root .

contract-initialize-baseline: ensure-contract-python
	$(PYTHON) -m tooling.generate_contract_artifacts --root . --initialize-baseline

contract-extend-baseline: ensure-contract-python
	$(PYTHON) -m tooling.generate_contract_artifacts --root . --extend-baseline

contract-replace-baseline-for-unreleased-contracts: ensure-contract-python
	$(PYTHON) -m tooling.generate_contract_artifacts --root . --replace-baseline-for-unreleased-contracts

contract-check: ensure-contract-python
	$(PYTHON) -m tooling.verify_contracts --root .

test-contracts: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_contracts

product-delivery-release-plan-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_product_delivery_release_plan

ensure-go:
	@$(GO) version >/dev/null 2>&1 || { printf '%s\n' 'Go is unavailable; install Go 1.23 or set GO'; exit 2; }

service-go-test: ensure-go
	cd services/guest-runtime && $(GO) test ./...
	cd services/host-agent && $(GO) test ./...
	cd services/host-installation-manager && $(GO) test ./...

host-edge-proxy-test: ensure-go
	cd services/host-edge-proxy && $(GO) test ./...

guest-product-process-supervisor-test: ensure-go
	cd services/guest-product-process-supervisor && $(GO) test ./...

# C39 amd64 selects these Linux Guest binaries. This compilation proof does
# not build a release input or claim a booted native Guest.
guest-product-amd64-build: ensure-go
	cd services/guest-runtime && mkdir -p .build
	cd services/guest-runtime && GOOS=linux GOARCH=amd64 $(GO) build -o .build/linux-amd64-guest-runtime ./cmd/guest-runtime
	cd services/guest-product-process-supervisor && mkdir -p .build
	cd services/guest-product-process-supervisor && GOOS=linux GOARCH=amd64 $(GO) build -o .build/linux-amd64-guest-product-process-supervisor ./cmd/guest-product-process-supervisor
	cd services/guest-product-release-manager && mkdir -p .build
	cd services/guest-product-release-manager && GOOS=linux GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/linux-amd64-guest-product-release-manager ./cmd/guest-product-release-manager

guest-product-release-manager-test: ensure-go
	cd services/guest-product-release-manager && GOTOOLCHAIN=go1.25.7+auto $(GO) test ./...

guest-product-release-effect-executor-test: ensure-go
	cd services/guest-product-release-effect-executor && $(GO) test ./...

guest-product-release-effect-executor-cross-platform-build: ensure-go
	cd services/guest-product-release-effect-executor && mkdir -p .build
	cd services/guest-product-release-effect-executor && GOOS=darwin GOARCH=arm64 $(GO) build -o .build/darwin-arm64-guest-product-release-effect-executor ./cmd/guest-product-release-effect-executor
	cd services/guest-product-release-effect-executor && GOOS=linux GOARCH=amd64 $(GO) build -o .build/linux-amd64-guest-product-release-effect-executor ./cmd/guest-product-release-effect-executor
	cd services/guest-product-release-effect-executor && GOOS=windows GOARCH=amd64 $(GO) build -o .build/windows-amd64-guest-product-release-effect-executor.exe ./cmd/guest-product-release-effect-executor

guest-bundled-upstream-image-set-manager-test: ensure-go
	cd services/guest-bundled-upstream-image-set-manager && GOTOOLCHAIN=go1.25.7+auto $(GO) test ./...

guest-bundled-upstream-image-set-manager-linux-build: ensure-go
	cd services/guest-bundled-upstream-image-set-manager && mkdir -p .build
	cd services/guest-bundled-upstream-image-set-manager && GOOS=linux GOARCH=arm64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/linux-arm64-guest-bundled-upstream-image-set-manager ./cmd/guest-bundled-upstream-image-set-manager

guest-bundled-upstream-image-set-effect-executor-test: ensure-go
	cd services/guest-bundled-upstream-image-set-effect-executor && GOTOOLCHAIN=go1.25.7+auto $(GO) test ./...

guest-bundled-upstream-image-set-effect-executor-cross-platform-build: ensure-go
	cd services/guest-bundled-upstream-image-set-effect-executor && mkdir -p .build
	cd services/guest-bundled-upstream-image-set-effect-executor && GOOS=darwin GOARCH=arm64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/darwin-arm64-guest-bundled-upstream-image-set-effect-executor ./cmd/guest-bundled-upstream-image-set-effect-executor
	cd services/guest-bundled-upstream-image-set-effect-executor && GOOS=linux GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/linux-amd64-guest-bundled-upstream-image-set-effect-executor ./cmd/guest-bundled-upstream-image-set-effect-executor
	cd services/guest-bundled-upstream-image-set-effect-executor && GOOS=windows GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/windows-amd64-guest-bundled-upstream-image-set-effect-executor.exe ./cmd/guest-bundled-upstream-image-set-effect-executor

guest-bundled-upstream-image-set-archive-composer-test: ensure-go
	cd tooling/guest-bundled-upstream-image-set-archive-composer && GOTOOLCHAIN=go1.25.7+auto $(GO) test ./...

host-platform-release-effect-executor-test: ensure-go
	cd services/host-platform-release-effect-executor && GOTOOLCHAIN=go1.25.7+auto $(GO) test ./...

host-platform-release-effect-executor-cross-platform-build: ensure-go
	cd services/host-platform-release-effect-executor && mkdir -p .build
	cd services/host-platform-release-effect-executor && GOOS=darwin GOARCH=arm64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/darwin-arm64-host-platform-release-effect-executor ./cmd/host-platform-release-effect-executor
	cd services/host-platform-release-effect-executor && GOOS=linux GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/linux-amd64-host-platform-release-effect-executor ./cmd/host-platform-release-effect-executor
	cd services/host-platform-release-effect-executor && GOOS=windows GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/windows-amd64-host-platform-release-effect-executor.exe ./cmd/host-platform-release-effect-executor

check: host-platform-release-effect-executor-test host-platform-release-effect-executor-cross-platform-build

check: operator-delivery-kit-composer-test

check: product-delivery-release-plan-test

product-update-composer-test: ensure-go
	cd tooling/product-update-composer && GOTOOLCHAIN=go1.25.7+auto $(GO) test ./...

guest-product-release-archive-composer-test: ensure-go
	cd tooling/guest-product-release-archive-composer && GOTOOLCHAIN=go1.25.7+auto $(GO) test ./...

host-platform-release-archive-composer-test: ensure-go
	cd tooling/host-platform-release-archive-composer && GOTOOLCHAIN=go1.25.7+auto $(GO) test ./...

product-update-composition-acceptance: ensure-go
	RUNTIME_PLATFORM_GO="$(GO)" $(SYSTEM_PYTHON) -m unittest acceptance.harness.test_product_update_composition

platformctl-test: ensure-go
	cd interfaces/platformctl && $(GO) test ./...

platformctl-cross-platform-build: ensure-go
	cd interfaces/platformctl && mkdir -p .build
	cd interfaces/platformctl && GOOS=darwin GOARCH=arm64 $(GO) build -o .build/darwin-arm64-platformctl ./cmd/platformctl
	cd interfaces/platformctl && GOOS=linux GOARCH=amd64 $(GO) build -o .build/linux-amd64-platformctl ./cmd/platformctl
	cd interfaces/platformctl && GOOS=windows GOARCH=amd64 $(GO) build -o .build/windows-amd64-platformctl.exe ./cmd/platformctl

ensure-runtime-console-node:
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	[ -n "$$node_path" ] || { printf '%s\n' 'Runtime Console requires Node 22.12+; set RUNTIME_CONSOLE_NODE'; exit 2; }; \
	node_version="$$($$node_path --version)"; \
	case "$$node_version" in v22.*) ;; *) printf '%s\n' "Runtime Console requires Node >=22.12.0 <23; selected RUNTIME_CONSOLE_NODE reports $$node_version"; exit 2;; esac; \
	node_minor="$${node_version#v22.}"; node_minor="$${node_minor%%.*}"; \
	case "$$node_minor" in ''|*[!0-9]*) printf '%s\n' "Runtime Console could not parse selected Node version $$node_version"; exit 2;; esac; \
	[ "$$node_minor" -ge 12 ] || { printf '%s\n' "Runtime Console requires Node >=22.12.0 <23; selected RUNTIME_CONSOLE_NODE reports $$node_version"; exit 2; }

runtime-console-deps: ensure-runtime-console-node
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) ci --include=dev

runtime-console-license-check: runtime-console-deps
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) run license-check

runtime-console-audit: runtime-console-deps
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) audit

runtime-console-check: runtime-console-license-check
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) run check

runtime-console-test: runtime-console-check
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) run test

runtime-console-build: runtime-console-check
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) run build

runtime-console-package-macos: runtime-console-check runtime-console-audit
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) run package:macos

runtime-console-package-macos-application: runtime-console-check runtime-console-audit
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) run package:macos-application

runtime-console-package-windows: runtime-console-check runtime-console-audit
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) run package:windows

runtime-console-package-linux: runtime-console-check runtime-console-audit
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) run package:linux

runtime-console-package-linux-deb: runtime-console-check runtime-console-audit
	@node_path="$$(command -v "$(RUNTIME_CONSOLE_NODE)")"; \
	cd interfaces && PATH="$$(dirname "$$node_path"):$$PATH" $(RUNTIME_CONSOLE_NPM) run package:linux-deb

host-guest-acceptance: ensure-go
	RUNTIME_PLATFORM_GO="$(GO)" $(SYSTEM_PYTHON) -m unittest acceptance.harness.test_host_guest_control

guest-operational-state-backup-restore-acceptance: ensure-go
	@test -n "$(VITALSERVER_GUEST_STATE_BACKUP_TEST_SOURCE_DATABASE_URL)" \
		&& test -n "$(VITALSERVER_GUEST_STATE_BACKUP_TEST_EMPTY_TARGET_DATABASE_URL)" \
		&& test -n "$(VITALSERVER_GUEST_STATE_BACKUP_TEST_PG_DUMP_PATH)" \
		&& test -n "$(VITALSERVER_GUEST_STATE_BACKUP_TEST_PG_RESTORE_PATH)" \
		|| { printf '%s\n' 'C76 acceptance requires a freshly migrated source URL, a distinct empty target URL, and absolute pg_dump/pg_restore paths'; exit 2; }
	cd services/guest-runtime && \
		VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL="$(VITALSERVER_GUEST_STATE_BACKUP_TEST_SOURCE_DATABASE_URL)" \
		$(GO) test -count=1 ./internal/adapters/gueststatepostgresqlrepository
	cd services/guest-runtime && \
		VITALSERVER_GUEST_STATE_BACKUP_TEST_SOURCE_DATABASE_URL="$(VITALSERVER_GUEST_STATE_BACKUP_TEST_SOURCE_DATABASE_URL)" \
		VITALSERVER_GUEST_STATE_BACKUP_TEST_EMPTY_TARGET_DATABASE_URL="$(VITALSERVER_GUEST_STATE_BACKUP_TEST_EMPTY_TARGET_DATABASE_URL)" \
		VITALSERVER_GUEST_STATE_BACKUP_TEST_PG_DUMP_PATH="$(VITALSERVER_GUEST_STATE_BACKUP_TEST_PG_DUMP_PATH)" \
		VITALSERVER_GUEST_STATE_BACKUP_TEST_PG_RESTORE_PATH="$(VITALSERVER_GUEST_STATE_BACKUP_TEST_PG_RESTORE_PATH)" \
		$(GO) test -count=1 \
			-run TestGuestOperationalStateBackupRestoresBothOwnedDatabasesToEmptyTargets \
			./internal/adapters/gueststatebackupstageexecutor

ensure-macos-host:
	@test "$$(uname -s)" = "Darwin" || { printf '%s\n' 'macOS native checks require a macOS Host'; exit 2; }

# The Provider compiles against Apple Virtualization. Running the package
# composer module again on macOS exercises the five explicitly Darwin-gated
# pkgbuild/pkgutil cases in addition to its portable policy tests.
macos-native-check: ensure-macos-host macos-provider-test macos-host-package-composer-test

macos-provider-test: ensure-macos-host
	@$(SWIFT) --version >/dev/null 2>&1 || { printf '%s\n' 'Swift is unavailable; install Xcode Command Line Tools or set SWIFT'; exit 2; }
	$(SWIFT) test --package-path providers/macos-virtualization
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_macos_virtual_machine_command_cli

guest-artifact-compiler-test:
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_guest_artifact_compiler

guest-artifact-compilation-input-assembler-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_guest_artifact_compilation_input_assembler

native-guest-artifact-input-preparer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_native_guest_artifact_input_preparer

# This prepares only the C41 source declaration for an amd64 Guest. The
# caller supplies the raw root-storage base and architecture-matched artifacts;
# C41/C35/C65 and later C62 own their separate effects.
native-guest-artifact-input-prepare: ensure-contract-python
	@[ -n "$(NATIVE_GUEST_RELEASE_ROOT)" ] || { printf '%s\n' 'set NATIVE_GUEST_RELEASE_ROOT to an existing absolute release workspace containing artifacts'; exit 2; }
	@[ -n "$(NATIVE_GUEST_INPUT_ASSEMBLY_ID)" ] || { printf '%s\n' 'set NATIVE_GUEST_INPUT_ASSEMBLY_ID'; exit 2; }
	@[ -n "$(NATIVE_GUEST_COMPILATION_ID)" ] || { printf '%s\n' 'set NATIVE_GUEST_COMPILATION_ID'; exit 2; }
	@[ -n "$(NATIVE_GUEST_ARTIFACT_SET_ID)" ] || { printf '%s\n' 'set NATIVE_GUEST_ARTIFACT_SET_ID'; exit 2; }
	@[ -n "$(NATIVE_GUEST_ROOT_STORAGE_SOURCE)" ] || { printf '%s\n' 'set NATIVE_GUEST_ROOT_STORAGE_SOURCE to the explicit amd64 raw Guest root storage source'; exit 2; }
	$(PYTHON) -m tooling.native_guest_artifact_input_preparer \
		--release-root "$(NATIVE_GUEST_RELEASE_ROOT)" \
		--assembly-id "$(NATIVE_GUEST_INPUT_ASSEMBLY_ID)" \
		--compilation-id "$(NATIVE_GUEST_COMPILATION_ID)" \
		--artifact-set-id "$(NATIVE_GUEST_ARTIFACT_SET_ID)" \
		--guest-product-bootstrap-artifact-composer "$(NATIVE_GUEST_RELEASE_ROOT)/artifacts/guest-product-bootstrap-artifact-composer" \
		--guest-root-storage "$(NATIVE_GUEST_ROOT_STORAGE_SOURCE)" \
		--guest-runtime "$(NATIVE_GUEST_RELEASE_ROOT)/artifacts/guest-runtime" \
		--guest-telemetry-collector "$(NATIVE_GUEST_RELEASE_ROOT)/artifacts/guest-telemetry-collector" \
		--guest-telemetry-collector-configuration "$(CURDIR)/product/observability/guest-telemetry-collector.yaml" \
		--guest-node-services "$(NATIVE_GUEST_RELEASE_ROOT)/artifacts/guest-node-services.tar.gz" \
		--guest-product-process-supervisor "$(NATIVE_GUEST_RELEASE_ROOT)/artifacts/guest-product-process-supervisor" \
		--guest-product-process-deployment-configuration "$(CURDIR)/product/guest-product/guest-product-process-deployment.v1.json" \
		--guest-product-release-manager "$(NATIVE_GUEST_RELEASE_ROOT)/artifacts/guest-product-release-manager" \
		--guest-product-release-manager-configuration "$(CURDIR)/product/guest-product/guest-product-release-manager-configuration.v1.json" \
		--guest-product-service-manager-deployment-configuration "$(CURDIR)/product/guest-product/guest-product-service-manager-deployment.v1.json" \
		--guest-product-bootstrap-configuration "$(CURDIR)/product/guest-product/guest-product-bootstrap-configuration-amd64.v1.json" \
		--guest-product-vitalserver-topology-deployment "$(CURDIR)/product/guest-product/guest-product-vitalserver-topology-deployment.v1.json" \
		--external-vitalserver-delivery-configuration "$(CURDIR)/product/guest-product/external-vitalserver-delivery-configuration.reference.v1.json"

guest-telemetry-collector-artifact-builder-test:
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_guest_telemetry_collector_artifact_builder

guest-telemetry-collector-artifact-build:
	@[ -n "$(GUEST_TELEMETRY_COLLECTOR_GUEST_ARCHITECTURE)" ] || { printf '%s\n' 'set GUEST_TELEMETRY_COLLECTOR_GUEST_ARCHITECTURE to arm64 or amd64'; exit 2; }
	@[ -n "$(GUEST_TELEMETRY_COLLECTOR_OUTPUT_ARTIFACT)" ] || { printf '%s\n' 'set GUEST_TELEMETRY_COLLECTOR_OUTPUT_ARTIFACT to an absolute new artifact path'; exit 2; }
	$(SYSTEM_PYTHON) tooling/guest_telemetry_collector_artifact_builder.py --builder-configuration "$(CURDIR)/product/observability/guest-telemetry-collector-builder.yaml" --collector-configuration "$(CURDIR)/product/observability/guest-telemetry-collector.yaml" --output-artifact "$(GUEST_TELEMETRY_COLLECTOR_OUTPUT_ARTIFACT)" --go-executable "$(GUEST_TELEMETRY_COLLECTOR_GO)" --go-toolchain "$(GUEST_TELEMETRY_COLLECTOR_GOTOOLCHAIN)" --guest-architecture "$(GUEST_TELEMETRY_COLLECTOR_GUEST_ARCHITECTURE)"

guest-linux-boot-artifact-extractor-test:
	cd tooling/guest-linux-boot-artifact-extractor && GOTOOLCHAIN="$(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN)" $(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO) test ./...

guest-linux-boot-artifact-extractor-build:
	cd tooling/guest-linux-boot-artifact-extractor && mkdir -p .build
	cd tooling/guest-linux-boot-artifact-extractor && GOTOOLCHAIN="$(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN)" GOOS=darwin GOARCH=arm64 $(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO) build -o .build/darwin-arm64-guest-linux-boot-artifact-extractor ./cmd/guest-linux-boot-artifact-extractor

guest-linux-boot-artifact-extractor-cross-platform-build: guest-linux-boot-artifact-extractor-build
	cd tooling/guest-linux-boot-artifact-extractor && mkdir -p .build
	cd tooling/guest-linux-boot-artifact-extractor && GOTOOLCHAIN="$(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN)" GOOS=linux GOARCH=amd64 $(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO) build -o .build/linux-amd64-guest-linux-boot-artifact-extractor ./cmd/guest-linux-boot-artifact-extractor
	cd tooling/guest-linux-boot-artifact-extractor && GOTOOLCHAIN="$(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN)" GOOS=windows GOARCH=amd64 $(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO) build -o .build/windows-amd64-guest-linux-boot-artifact-extractor.exe ./cmd/guest-linux-boot-artifact-extractor

guest-linux-source-disk-materializer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_guest_linux_source_disk_materializer

# C73 only converts a caller-declared QCOW2 input to raw disk bytes. It does
# not download, partition, bootstrap, or select the subsequent C42 boot input.
guest-linux-source-disk-materialize: ensure-contract-python
	@[ -n "$(GUEST_LINUX_SOURCE_DISK_MATERIALIZATION_DECLARATION)" ] || { printf '%s\n' 'set GUEST_LINUX_SOURCE_DISK_MATERIALIZATION_DECLARATION to an absolute C73 declaration path'; exit 2; }
	@[ -n "$(GUEST_LINUX_SOURCE_DISK_MATERIALIZATION_OUTPUT_DIRECTORY)" ] || { printf '%s\n' 'set GUEST_LINUX_SOURCE_DISK_MATERIALIZATION_OUTPUT_DIRECTORY to a new absolute output directory'; exit 2; }
	@[ -n "$(GUEST_LINUX_SOURCE_DISK_QEMU_IMG_EXECUTABLE)" ] || { printf '%s\n' 'set GUEST_LINUX_SOURCE_DISK_QEMU_IMG_EXECUTABLE to the selected qemu-img executable'; exit 2; }
	$(PYTHON) -m tooling.guest_linux_source_disk_materializer \
		--declaration "$(GUEST_LINUX_SOURCE_DISK_MATERIALIZATION_DECLARATION)" \
		--output-directory "$(GUEST_LINUX_SOURCE_DISK_MATERIALIZATION_OUTPUT_DIRECTORY)" \
		--qemu-img-executable "$(GUEST_LINUX_SOURCE_DISK_QEMU_IMG_EXECUTABLE)"

guest-root-storage-partition-assembler-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_guest_root_storage_partition_assembler

guest-product-bootstrap-volume-composer-test:
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN)" $(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO) test ./...

guest-product-bootstrap-volume-composer-build:
	cd tooling/guest-product-bootstrap-volume-composer && mkdir -p .build
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN)" GOOS=darwin GOARCH=arm64 $(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO) build -o .build/darwin-arm64-guest-product-bootstrap-volume-composer ./cmd/guest-product-bootstrap-volume-composer

guest-product-bootstrap-volume-composer-cross-platform-build: guest-product-bootstrap-volume-composer-build
	cd tooling/guest-product-bootstrap-volume-composer && mkdir -p .build
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN)" GOOS=linux GOARCH=amd64 $(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO) build -o .build/linux-amd64-guest-product-bootstrap-volume-composer ./cmd/guest-product-bootstrap-volume-composer
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN)" GOOS=windows GOARCH=amd64 $(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO) build -o .build/windows-amd64-guest-product-bootstrap-volume-composer.exe ./cmd/guest-product-bootstrap-volume-composer

guest-product-bootstrap-artifact-composer-test:
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN)" $(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO) test ./internal/guestproductbootstrapartifactcompositionapplication ./internal/guestproductbootstrapplancomposer ./internal/guestproductbootstrapvolumeapplication ./internal/nocloudguestproductbootstrapvolumeadapter

guest-product-bootstrap-artifact-composer-build:
	cd tooling/guest-product-bootstrap-volume-composer && mkdir -p .build
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN)" GOOS=darwin GOARCH=arm64 $(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO) build -o .build/darwin-arm64-guest-product-bootstrap-artifact-composer ./cmd/guest-product-bootstrap-artifact-composer

guest-product-bootstrap-artifact-composer-cross-platform-build: guest-product-bootstrap-artifact-composer-build
	cd tooling/guest-product-bootstrap-volume-composer && mkdir -p .build
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN)" GOOS=linux GOARCH=amd64 $(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO) build -o .build/linux-amd64-guest-product-bootstrap-artifact-composer ./cmd/guest-product-bootstrap-artifact-composer
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN)" GOOS=windows GOARCH=amd64 $(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO) build -o .build/windows-amd64-guest-product-bootstrap-artifact-composer.exe ./cmd/guest-product-bootstrap-artifact-composer

guest-product-systemd-service-unit-composer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_guest_product_systemd_service_unit_composer

macos-guest-artifact-manifest-composer-test:
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_macos_guest_artifact_manifest_composer

macos-installer-component-cpio-test:
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_macos_installer_component_cpio

macos-host-package-composer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_macos_host_package_composer

linux-host-package-composer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_linux_host_package_composer

# The selected C23 profile and each absolute source byte are captured in one
# caller-owned preparation document. This derives C48 and its systemd units;
# it does not compile a binary, call dpkg, or claim a Linux Host was installed.
linux-host-release-input-preparer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_linux_host_release_input_preparer

# Cross-compile the Linux Host service and operator utility bytes that C48 can
# name. The caller must choose a new absolute output directory, profile, and DEB composition
# separately so this target cannot create deployment state by accident.
linux-host-release-artifacts-build: ensure-go
	@artifact_root="$(LINUX_HOST_RELEASE_ARTIFACT_DIRECTORY)"; \
	[ -n "$$artifact_root" ] || { printf '%s\n' 'set LINUX_HOST_RELEASE_ARTIFACT_DIRECTORY to a new absolute output directory'; exit 2; }; \
	case "$$artifact_root" in /*) ;; *) printf '%s\n' 'LINUX_HOST_RELEASE_ARTIFACT_DIRECTORY must be absolute on the build host'; exit 2;; esac; \
	[ ! -e "$$artifact_root" ] || { printf '%s\n' 'LINUX_HOST_RELEASE_ARTIFACT_DIRECTORY already exists; use a new release workspace'; exit 2; }; \
	parent="$$(dirname "$$artifact_root")"; name="$$(basename "$$artifact_root")"; mkdir -p "$$parent"; \
	staging="$$(mktemp -d "$$parent/.$$name.XXXXXX")"; \
	cleanup() { rm -rf "$$staging"; }; trap cleanup EXIT HUP INT TERM; \
	(cd services/host-agent && GOOS=linux GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/host-agent" ./cmd/host-agent); \
	(cd services/host-edge-proxy && GOOS=linux GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/host-edge-proxy" ./cmd/host-edge-proxy); \
	(cd services/host-installation-manager && GOOS=linux GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/host-installation-manager" ./cmd/host-installation-manager); \
	(cd services/host-update-handoff-supervisor && GOOS=linux GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/host-update-handoff-supervisor" ./cmd/host-update-handoff-supervisor); \
	(cd interfaces/platformctl && GOOS=linux GOARCH=amd64 $(GO) build -o "$$staging/platformctl" ./cmd/platformctl); \
	(cd providers/os-provider-bridge && GOOS=linux GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/linux-kvm-libvirt-systemd-bridge" ./cmd/linux-kvm-libvirt-systemd-bridge); \
	for artifact in host-agent host-edge-proxy host-installation-manager host-update-handoff-supervisor platformctl linux-kvm-libvirt-systemd-bridge; do test -s "$$staging/$$artifact" || { printf '%s\n' "missing Linux Host artifact: $$artifact"; exit 2; }; done; \
	mv "$$staging" "$$artifact_root"; trap - EXIT HUP INT TERM

linux-host-release-input-prepare: ensure-contract-python
	@[ -n "$(LINUX_HOST_RELEASE_INPUT_PREPARATION)" ] || { printf '%s\n' 'set LINUX_HOST_RELEASE_INPUT_PREPARATION to an absolute Linux Host release-input preparation JSON path'; exit 2; }
	$(PYTHON) -m tooling.linux_host_release_input_preparer --preparation "$(LINUX_HOST_RELEASE_INPUT_PREPARATION)"

linux-host-package-compose: ensure-contract-python
	@[ -n "$(LINUX_HOST_PACKAGE_COMPOSITION)" ] || { printf '%s\n' 'set LINUX_HOST_PACKAGE_COMPOSITION to an absolute LinuxHostPackageComposition JSON path'; exit 2; }
	$(PYTHON) -m tooling.linux_host_package_composer --composition "$(LINUX_HOST_PACKAGE_COMPOSITION)"

# Runs one already prepared product C48 release through real dpkg in an
# amd64 Debian container. Docker has no systemd PID 1, so the proof supplies a
# declared test systemctl adapter; actual systemd registration stays C24 work.
linux-host-package-selected-release-dpkg-acceptance: ensure-contract-python
	@[ -n "$(LINUX_HOST_PACKAGE_COMPOSITION)" ] || { printf '%s\n' 'set LINUX_HOST_PACKAGE_COMPOSITION to the selected absolute LinuxHostPackageComposition JSON path'; exit 2; }
	RUNTIME_PLATFORM_LINUX_DPKG_ACCEPTANCE=1 RUNTIME_PLATFORM_LINUX_PRODUCT_PACKAGE_COMPOSITION="$(LINUX_HOST_PACKAGE_COMPOSITION)" $(PYTHON) -m unittest tooling.tests.test_linux_host_package_dpkg_acceptance.LinuxHostPackageDpkgAcceptanceTests.test_selected_product_release_runs_through_real_dpkg_lifecycle

# WiX source composition is deterministic and runs on every development host.
# Producing and exercising an MSI requires an explicitly provisioned Windows
# WiX v4 toolchain and remains separate clean-Host evidence.
windows-host-msi-composer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_windows_host_msi_composer

operator-delivery-kit-composer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_operator_delivery_kit_composer

# One delivery kit is a new immutable directory. The caller names all source
# bytes; this target never treats a pre-existing package as installation proof.
operator-delivery-kit-compose: ensure-contract-python
	@[ -n "$(OPERATOR_DELIVERY_KIT_RELEASE_SET_ID)" ] || { printf '%s\n' 'set OPERATOR_DELIVERY_KIT_RELEASE_SET_ID'; exit 2; }
	@[ -n "$(OPERATOR_DELIVERY_KIT_RELEASE_DELIVERY_PLANS_DOCUMENT)" ] || { printf '%s\n' 'set OPERATOR_DELIVERY_KIT_RELEASE_DELIVERY_PLANS_DOCUMENT to an absolute C23 document path'; exit 2; }
	@[ -n "$(OPERATOR_DELIVERY_KIT_RELEASE_DELIVERY_PLAN_ID)" ] || { printf '%s\n' 'set OPERATOR_DELIVERY_KIT_RELEASE_DELIVERY_PLAN_ID'; exit 2; }
	@[ -n "$(OPERATOR_DELIVERY_KIT_HOST_INSTALLER_ARTIFACT)" ] || { printf '%s\n' 'set OPERATOR_DELIVERY_KIT_HOST_INSTALLER_ARTIFACT to an absolute artifact path'; exit 2; }
	@[ -n "$(OPERATOR_DELIVERY_KIT_RUNTIME_CONSOLE_ARTIFACT)" ] || { printf '%s\n' 'set OPERATOR_DELIVERY_KIT_RUNTIME_CONSOLE_ARTIFACT to an absolute artifact path'; exit 2; }
	@[ -n "$(OPERATOR_DELIVERY_KIT_RUNTIME_CONSOLE_ARTIFACT_RECEIPT)" ] || { printf '%s\n' 'set OPERATOR_DELIVERY_KIT_RUNTIME_CONSOLE_ARTIFACT_RECEIPT to an absolute C71 receipt path'; exit 2; }
	@[ -n "$(OPERATOR_DELIVERY_KIT_OPERATOR_INTERFACE_BOOTSTRAP_CONFIGURATION)" ] || { printf '%s\n' 'set OPERATOR_DELIVERY_KIT_OPERATOR_INTERFACE_BOOTSTRAP_CONFIGURATION to an absolute C53 path'; exit 2; }
	@[ -n "$(OPERATOR_DELIVERY_KIT_OUTPUT_DIRECTORY)" ] || { printf '%s\n' 'set OPERATOR_DELIVERY_KIT_OUTPUT_DIRECTORY to a new absolute output directory'; exit 2; }
	$(PYTHON) -m tooling.operator_delivery_kit_composer --release-set-id "$(OPERATOR_DELIVERY_KIT_RELEASE_SET_ID)" --release-delivery-plans-document "$(OPERATOR_DELIVERY_KIT_RELEASE_DELIVERY_PLANS_DOCUMENT)" --release-delivery-plan-id "$(OPERATOR_DELIVERY_KIT_RELEASE_DELIVERY_PLAN_ID)" --host-installer-artifact "$(OPERATOR_DELIVERY_KIT_HOST_INSTALLER_ARTIFACT)" --runtime-console-artifact "$(OPERATOR_DELIVERY_KIT_RUNTIME_CONSOLE_ARTIFACT)" --runtime-console-artifact-receipt "$(OPERATOR_DELIVERY_KIT_RUNTIME_CONSOLE_ARTIFACT_RECEIPT)" --operator-interface-bootstrap-configuration "$(OPERATOR_DELIVERY_KIT_OPERATOR_INTERFACE_BOOTSTRAP_CONFIGURATION)" --output-directory "$(OPERATOR_DELIVERY_KIT_OUTPUT_DIRECTORY)"

# Read-only verification for one downloaded C72 kit. C53 is checked only when
# a caller explicitly supplies one Host-installed bootstrap file.
operator-delivery-kit-verify: ensure-contract-python
	@[ -n "$(OPERATOR_DELIVERY_KIT_DIRECTORY)" ] || { printf '%s\n' 'set OPERATOR_DELIVERY_KIT_DIRECTORY to an absolute C72 delivery-kit directory'; exit 2; }
	@set -- --delivery-kit-directory "$(OPERATOR_DELIVERY_KIT_DIRECTORY)"; \
	if [ -n "$(OPERATOR_DELIVERY_KIT_VERIFY_BOOTSTRAP_CONFIGURATION)" ]; then set -- "$$@" --operator-interface-bootstrap-configuration "$(OPERATOR_DELIVERY_KIT_VERIFY_BOOTSTRAP_CONFIGURATION)"; fi; \
	$(PYTHON) -m tooling.operator_delivery_kit_verifier "$$@"

# This prepares a C48 release source whose hashes, C70 service definitions,
# and MSI composition are all derived from the same explicit selected bytes.
# It does not call WiX or claim an MSI exists.
windows-host-release-input-preparer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_windows_host_release_input_preparer

# Cross-compile the Windows Host service and operator utility bytes that C48
# can name. The caller supplies an empty absolute output directory; this target does not select a
# deployment profile, ProductCode, MSI output, or WiX toolchain.
windows-host-release-artifacts-build: ensure-go
	@artifact_root="$(WINDOWS_HOST_RELEASE_ARTIFACT_DIRECTORY)"; \
	[ -n "$$artifact_root" ] || { printf '%s\n' 'set WINDOWS_HOST_RELEASE_ARTIFACT_DIRECTORY to a new absolute output directory'; exit 2; }; \
	case "$$artifact_root" in /*) ;; *) printf '%s\n' 'WINDOWS_HOST_RELEASE_ARTIFACT_DIRECTORY must be absolute on the build host'; exit 2;; esac; \
	[ ! -e "$$artifact_root" ] || { printf '%s\n' 'WINDOWS_HOST_RELEASE_ARTIFACT_DIRECTORY already exists; use a new release workspace'; exit 2; }; \
	parent="$$(dirname "$$artifact_root")"; name="$$(basename "$$artifact_root")"; mkdir -p "$$parent"; \
	staging="$$(mktemp -d "$$parent/.$$name.XXXXXX")"; \
	cleanup() { rm -rf "$$staging"; }; trap cleanup EXIT HUP INT TERM; \
	(cd services/host-agent && GOOS=windows GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/host-agent.exe" ./cmd/host-agent); \
	(cd services/host-edge-proxy && GOOS=windows GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/host-edge-proxy.exe" ./cmd/host-edge-proxy); \
	(cd services/host-installation-manager && GOOS=windows GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/host-installation-manager.exe" ./cmd/host-installation-manager); \
	(cd services/host-service-runner && GOOS=windows GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/host-service-runner.exe" ./cmd/host-service-runner); \
	(cd services/host-update-handoff-supervisor && GOOS=windows GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/host-update-handoff-supervisor.exe" ./cmd/host-update-handoff-supervisor); \
	(cd interfaces/platformctl && GOOS=windows GOARCH=amd64 $(GO) build -o "$$staging/platformctl.exe" ./cmd/platformctl); \
	(cd providers/os-provider-bridge && GOOS=windows GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$staging/windows-hyperv-scm-bridge.exe" ./cmd/windows-hyperv-scm-bridge); \
	for artifact in host-agent.exe host-edge-proxy.exe host-installation-manager.exe host-service-runner.exe host-update-handoff-supervisor.exe platformctl.exe windows-hyperv-scm-bridge.exe; do test -s "$$staging/$$artifact" || { printf '%s\n' "missing Windows Host artifact: $$artifact"; exit 2; }; done; \
	mv "$$staging" "$$artifact_root"; trap - EXIT HUP INT TERM

# The selected C23 profile and each absolute source byte are captured in one
# caller-owned preparation document. The release tool creates C48/C70/C53
# inputs but does not discover WiX or claim that an MSI was compiled.
windows-host-release-input-prepare: ensure-contract-python
	@[ -n "$(WINDOWS_HOST_RELEASE_INPUT_PREPARATION)" ] || { printf '%s\n' 'set WINDOWS_HOST_RELEASE_INPUT_PREPARATION to an absolute Windows Host release-input preparation JSON path'; exit 2; }
	$(PYTHON) -m tooling.windows_host_release_input_preparer --preparation "$(WINDOWS_HOST_RELEASE_INPUT_PREPARATION)"

# The caller names all C48 sources and the intended WiX/MSI output through one
# explicit composition document.  This target has no default fixture and never
# claims that an MSI exists unless the document names an actual WiX v4 tool.
windows-host-msi-compose: ensure-contract-python
	@[ -n "$(WINDOWS_HOST_MSI_COMPOSITION)" ] || { printf '%s\n' 'set WINDOWS_HOST_MSI_COMPOSITION to an absolute WindowsHostMSIComposition JSON path'; exit 2; }
	$(PYTHON) -m tooling.windows_host_msi_composer --composition "$(WINDOWS_HOST_MSI_COMPOSITION)"

# This is an opt-in Linux clean-container proof. It compiles the manager for
# amd64, then a Debian container executes the generated package's real dpkg
# preinst/postinst/prerm/postrm lifecycle. It is intentionally separate from
# `check`: Docker availability and a container image are external evidence.
linux-host-package-dpkg-acceptance: ensure-go ensure-contract-python
	cd services/host-installation-manager && mkdir -p .build
	cd services/host-installation-manager && GOOS=linux GOARCH=amd64 $(GO) build -o .build/linux-amd64-host-installation-manager ./cmd/host-installation-manager
	RUNTIME_PLATFORM_LINUX_DPKG_ACCEPTANCE=1 RUNTIME_PLATFORM_LINUX_HOST_INSTALLATION_MANAGER="$(CURDIR)/services/host-installation-manager/.build/linux-amd64-host-installation-manager" $(PYTHON) -m unittest tooling.tests.test_linux_host_package_dpkg_acceptance

macos-release-package-assembly-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_macos_release_package_assembly

macos-release-package-assembly: ensure-contract-python
	@[ -n "$(MACOS_RELEASE_PACKAGE_ASSEMBLY_DECLARATION)" ] || { printf '%s\n' 'set MACOS_RELEASE_PACKAGE_ASSEMBLY_DECLARATION to an absolute C47 declaration path'; exit 2; }
	$(PYTHON) -m tooling.macos_release_package_assembly --assembly-declaration "$(MACOS_RELEASE_PACKAGE_ASSEMBLY_DECLARATION)"

macos-development-release-input-preparer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_macos_development_release_input_preparer

macos-development-guest-boot-input-assembly-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_macos_development_guest_boot_input_assembly

# C42/C43 consume one caller-selected immutable raw source image. The source
# filesystem layout, boot-source kind and identity, and root-storage identity
# are all command inputs. A QCOW2 source must be made raw by C73 first; this
# target never downloads, discovers, or guesses one.
macos-development-guest-boot-input-assembly: guest-linux-boot-artifact-extractor-build ensure-contract-python
	@[ -n "$(MACOS_DEVELOPMENT_RELEASE_ROOT)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_RELEASE_ROOT to an existing absolute release workspace'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_BOOT_INPUT_ASSEMBLY_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_BOOT_INPUT_ASSEMBLY_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_C42_EXTRACTION_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_C42_EXTRACTION_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_C43_ASSEMBLY_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_C43_ASSEMBLY_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_SOURCE_IMAGE)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_SOURCE_IMAGE to one explicit raw ARM64 source disk'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_SOURCE_IMAGE_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_SOURCE_IMAGE_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_SOURCE_ORIGIN_URI)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_SOURCE_ORIGIN_URI'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_SOURCE_RELEASE)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_SOURCE_RELEASE'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_SOURCE_FILESYSTEM_LAYOUT)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_SOURCE_FILESYSTEM_LAYOUT'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_SOURCE_ROOT_STORAGE_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_SOURCE_ROOT_STORAGE_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_TARGET_ROOT_STORAGE_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_TARGET_ROOT_STORAGE_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_TARGET_ROOT_STORAGE_OUTPUT_RELATIVE_PATH)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_TARGET_ROOT_STORAGE_OUTPUT_RELATIVE_PATH'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_KERNEL_SOURCE_KIND)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_KERNEL_SOURCE_KIND'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_SOURCE_KIND)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_SOURCE_KIND'; exit 2; }
	$(PYTHON) -m tooling.macos_development_guest_boot_input_assembly \
		--release-root "$(MACOS_DEVELOPMENT_RELEASE_ROOT)" \
		--assembly-id "$(MACOS_DEVELOPMENT_GUEST_BOOT_INPUT_ASSEMBLY_ID)" \
		--c42-extraction-id "$(MACOS_DEVELOPMENT_C42_EXTRACTION_ID)" \
		--c43-assembly-id "$(MACOS_DEVELOPMENT_C43_ASSEMBLY_ID)" \
		--source-image "$(MACOS_DEVELOPMENT_GUEST_SOURCE_IMAGE)" \
		--source-image-id "$(MACOS_DEVELOPMENT_GUEST_SOURCE_IMAGE_ID)" \
		--source-origin-uri "$(MACOS_DEVELOPMENT_GUEST_SOURCE_ORIGIN_URI)" \
		--source-release "$(MACOS_DEVELOPMENT_GUEST_SOURCE_RELEASE)" \
		--source-filesystem-layout "$(MACOS_DEVELOPMENT_GUEST_SOURCE_FILESYSTEM_LAYOUT)" \
		$(if $(MACOS_DEVELOPMENT_GUEST_SOURCE_FILESYSTEM_PARTITION_INDEX),--source-filesystem-partition-index "$(MACOS_DEVELOPMENT_GUEST_SOURCE_FILESYSTEM_PARTITION_INDEX)") \
		$(if $(MACOS_DEVELOPMENT_GUEST_SOURCE_MATERIALIZATION_RECEIPT),--source-materialization-receipt "$(MACOS_DEVELOPMENT_GUEST_SOURCE_MATERIALIZATION_RECEIPT)") \
		$(if $(MACOS_DEVELOPMENT_GUEST_SOURCE_MATERIALIZATION_ID),--source-materialization-id "$(MACOS_DEVELOPMENT_GUEST_SOURCE_MATERIALIZATION_ID)") \
		--source-root-storage-id "$(MACOS_DEVELOPMENT_GUEST_SOURCE_ROOT_STORAGE_ID)" \
		--target-root-storage-id "$(MACOS_DEVELOPMENT_GUEST_TARGET_ROOT_STORAGE_ID)" \
		--target-root-storage-output-relative-path "$(MACOS_DEVELOPMENT_GUEST_TARGET_ROOT_STORAGE_OUTPUT_RELATIVE_PATH)" \
		--kernel-source-kind "$(MACOS_DEVELOPMENT_GUEST_KERNEL_SOURCE_KIND)" \
		$(if $(MACOS_DEVELOPMENT_GUEST_KERNEL_GUEST_ABSOLUTE_PATH),--kernel-guest-absolute-path "$(MACOS_DEVELOPMENT_GUEST_KERNEL_GUEST_ABSOLUTE_PATH)") \
		$(if $(MACOS_DEVELOPMENT_GUEST_KERNEL_EXTERNAL_ARTIFACT),--kernel-external-artifact "$(MACOS_DEVELOPMENT_GUEST_KERNEL_EXTERNAL_ARTIFACT)") \
		$(if $(MACOS_DEVELOPMENT_GUEST_KERNEL_EXTERNAL_ORIGIN_URI),--kernel-external-origin-uri "$(MACOS_DEVELOPMENT_GUEST_KERNEL_EXTERNAL_ORIGIN_URI)") \
		$(if $(MACOS_DEVELOPMENT_GUEST_KERNEL_EXTERNAL_RELEASE),--kernel-external-release "$(MACOS_DEVELOPMENT_GUEST_KERNEL_EXTERNAL_RELEASE)") \
		--initial-ramdisk-source-kind "$(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_SOURCE_KIND)" \
		$(if $(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_GUEST_ABSOLUTE_PATH),--initial-ramdisk-guest-absolute-path "$(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_GUEST_ABSOLUTE_PATH)") \
		$(if $(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_EXTERNAL_ARTIFACT),--initial-ramdisk-external-artifact "$(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_EXTERNAL_ARTIFACT)") \
		$(if $(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_EXTERNAL_ORIGIN_URI),--initial-ramdisk-external-origin-uri "$(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_EXTERNAL_ORIGIN_URI)") \
		$(if $(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_EXTERNAL_RELEASE),--initial-ramdisk-external-release "$(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_EXTERNAL_RELEASE)") \
		--c42-extractor-executable "$(CURDIR)/tooling/guest-linux-boot-artifact-extractor/.build/darwin-arm64-guest-linux-boot-artifact-extractor"

# Builds the release-selected executable/configuration bytes that C41/C47 name
# later. C42/C43 boot/root-storage and the Linux ARM64 Node distribution remain
# caller-owned inputs: this target neither acquires nor infers them.
macos-development-release-artifacts-build: ensure-go ensure-node
	@release_root="$(MACOS_DEVELOPMENT_RELEASE_ROOT)"; \
	[ -n "$$release_root" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_RELEASE_ROOT to an existing absolute release workspace'; exit 2; }; \
	[ -n "$(GUEST_NODE_DISTRIBUTION_ROOT)" ] || { printf '%s\n' 'set GUEST_NODE_DISTRIBUTION_ROOT to an explicit Linux ARM64 Node distribution root'; exit 2; }; \
	case "$$release_root" in /*) ;; *) printf '%s\n' 'MACOS_DEVELOPMENT_RELEASE_ROOT must be absolute'; exit 2;; esac; \
	[ -d "$$release_root" ] || { printf '%s\n' 'MACOS_DEVELOPMENT_RELEASE_ROOT must already exist'; exit 2; }; \
	[ ! -e "$$release_root/artifacts" ] || { printf '%s\n' 'MACOS_DEVELOPMENT_RELEASE_ROOT/artifacts already exists; use a new release workspace'; exit 2; }; \
	staging_root="$$(mktemp -d "$$release_root/.artifacts-staging.XXXXXX")"; \
	cleanup() { "$(SYSTEM_PYTHON)" -c 'import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)' "$$staging_root"; }; \
	trap cleanup EXIT HUP INT TERM; \
	artifact_root="$$staging_root/artifacts"; \
	mkdir "$$artifact_root"; \
	(cd services/host-agent && GOOS=darwin GOARCH=arm64 $(GO) build -o "$$artifact_root/host-agent" ./cmd/host-agent); \
	(cd services/host-edge-proxy && GOOS=darwin GOARCH=arm64 $(GO) build -o "$$artifact_root/host-edge-proxy" ./cmd/host-edge-proxy); \
	(cd services/host-installation-manager && GOOS=darwin GOARCH=arm64 $(GO) build -o "$$artifact_root/host-installation-manager" ./cmd/host-installation-manager); \
	(cd services/host-updater && GOOS=darwin GOARCH=arm64 $(GO) build -o "$$artifact_root/host-updater" ./cmd/host-updater); \
	(cd services/host-update-handoff-supervisor && GOOS=darwin GOARCH=arm64 $(GO) build -o "$$artifact_root/host-update-handoff-supervisor" ./cmd/host-update-handoff-supervisor); \
	(cd interfaces/platformctl && GOOS=darwin GOARCH=arm64 $(GO) build -o "$$artifact_root/platformctl" ./cmd/platformctl); \
	(cd services/guest-product-release-effect-executor && GOOS=darwin GOARCH=arm64 $(GO) build -o "$$artifact_root/guest-product-release-effect-executor" ./cmd/guest-product-release-effect-executor); \
	(cd services/guest-runtime && GOOS=linux GOARCH=arm64 $(GO) build -o "$$artifact_root/guest-runtime" ./cmd/guest-runtime); \
	(cd services/guest-product-process-supervisor && GOOS=linux GOARCH=arm64 $(GO) build -o "$$artifact_root/guest-product-process-supervisor" ./cmd/guest-product-process-supervisor); \
	(cd services/guest-product-release-manager && GOOS=linux GOARCH=arm64 $(GO) build -o "$$artifact_root/guest-product-release-manager" ./cmd/guest-product-release-manager); \
	(cd services/guest-bundled-upstream-image-set-manager && GOOS=linux GOARCH=arm64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o "$$artifact_root/guest-bundled-upstream-image-set-manager" ./cmd/guest-bundled-upstream-image-set-manager); \
	(cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN)" GOOS=darwin GOARCH=arm64 $(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO) build -o "$$artifact_root/guest-product-bootstrap-artifact-composer" ./cmd/guest-product-bootstrap-artifact-composer); \
	(cd providers/macos-virtualization && $(SWIFT) build -c release --product macos-virtual-machine-supervisor); \
	cp "providers/macos-virtualization/.build/release/macos-virtual-machine-supervisor" "$$artifact_root/macos-virtual-machine-supervisor"; \
	$(MAKE) runtime-console-package-macos-application; \
	ditto "$(CURDIR)/.tmp/runtime-console-desktop/mac-arm64/VitalServer Runtime Platform.app" "$$artifact_root/VitalServer Runtime Platform.app"; \
	$(MAKE) guest-telemetry-collector-artifact-build GUEST_TELEMETRY_COLLECTOR_GO="$(GO)" GUEST_TELEMETRY_COLLECTOR_GUEST_ARCHITECTURE="arm64" GUEST_TELEMETRY_COLLECTOR_OUTPUT_ARTIFACT="$$artifact_root/guest-telemetry-collector"; \
	$(MAKE) guest-node-services-bundle GUEST_NODE_SERVICES_GUEST_ARCHITECTURE="arm64" GUEST_NODE_DISTRIBUTION_ROOT="$(GUEST_NODE_DISTRIBUTION_ROOT)" GUEST_NODE_SERVICES_BUNDLE_OUTPUT="$$artifact_root/guest-node-services.tar.gz"; \
	for artifact in host-agent host-edge-proxy host-installation-manager host-updater host-update-handoff-supervisor platformctl guest-product-release-effect-executor guest-runtime guest-product-process-supervisor guest-product-release-manager guest-bundled-upstream-image-set-manager guest-product-bootstrap-artifact-composer macos-virtual-machine-supervisor guest-telemetry-collector guest-node-services.tar.gz; do test -s "$$artifact_root/$$artifact" || { printf '%s\n' "missing declared development artifact: $$artifact"; exit 2; }; done; \
	test -x "$$artifact_root/VitalServer Runtime Platform.app/Contents/MacOS/VitalServer Runtime Platform" || { printf '%s\n' 'missing declared macOS operator application entrypoint'; exit 2; }; \
	"$(SYSTEM_PYTHON)" -c 'import os, sys; os.rename(sys.argv[1], sys.argv[2])' "$$artifact_root" "$$release_root/artifacts"; \
	rmdir "$$staging_root"; \
	trap - EXIT

# This creates only C41/C47 desired input from already-built artifacts. It
# never selects a Linux root image or Node distribution: all three are caller
# supplied, and their later C41 identities are recorded by the owning assembler.
macos-development-release-input-prepare: ensure-contract-python
	@[ -n "$(MACOS_DEVELOPMENT_RELEASE_ROOT)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_RELEASE_ROOT to an existing absolute release workspace containing selected artifacts'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_RELEASE_ASSEMBLY_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_RELEASE_ASSEMBLY_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_INPUT_ASSEMBLY_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_INPUT_ASSEMBLY_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_COMPILATION_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_COMPILATION_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_ARTIFACT_SET_ID)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_ARTIFACT_SET_ID'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_KERNEL_SOURCE)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_KERNEL_SOURCE to the explicit C42 kernel output'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_SOURCE)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_SOURCE to the explicit C42 initial RAM disk output'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_ROOT_STORAGE_SOURCE)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_ROOT_STORAGE_SOURCE to the explicit C43 root-storage output'; exit 2; }
	$(PYTHON) -m tooling.macos_development_release_input_preparer \
		--release-root "$(MACOS_DEVELOPMENT_RELEASE_ROOT)" \
		--assembly-id "$(MACOS_DEVELOPMENT_RELEASE_ASSEMBLY_ID)" \
		--guest-input-assembly-id "$(MACOS_DEVELOPMENT_GUEST_INPUT_ASSEMBLY_ID)" \
		--guest-compilation-id "$(MACOS_DEVELOPMENT_GUEST_COMPILATION_ID)" \
		--guest-artifact-set-id "$(MACOS_DEVELOPMENT_GUEST_ARTIFACT_SET_ID)" \
		--release-delivery-plans "$(CURDIR)/product/delivery/release-delivery-plans.v1.json" \
		--release-delivery-plan-id "macos-runtime-platform-release" \
		--payload-base-path "/Library/Application Support/VitalServerRuntimePlatform" \
		--guest-product-bootstrap-artifact-composer "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/guest-product-bootstrap-artifact-composer" \
		--guest-kernel "$(MACOS_DEVELOPMENT_GUEST_KERNEL_SOURCE)" \
		--guest-initial-ramdisk "$(MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_SOURCE)" \
		--guest-root-storage "$(MACOS_DEVELOPMENT_GUEST_ROOT_STORAGE_SOURCE)" \
		--guest-runtime "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/guest-runtime" \
		--guest-telemetry-collector "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/guest-telemetry-collector" \
		--guest-node-services "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/guest-node-services.tar.gz" \
		--guest-product-process-supervisor "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/guest-product-process-supervisor" \
		--guest-product-release-manager "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/guest-product-release-manager" \
		--host-agent "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/host-agent" \
		--host-edge-proxy "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/host-edge-proxy" \
		--host-installation-manager "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/host-installation-manager" \
		--host-update-handoff-supervisor "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/host-update-handoff-supervisor" \
		--platformctl "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/platformctl" \
		--macos-virtual-machine-supervisor "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/macos-virtual-machine-supervisor" \
		--operator-application-bundle "$(MACOS_DEVELOPMENT_RELEASE_ROOT)/artifacts/VitalServer Runtime Platform.app" \
		--host-agent-deployment-configuration "$(MACOS_DEVELOPMENT_DEPLOYMENT_PROFILE_DIRECTORY)/host-agent-deployment-configuration.v1.json" \
		--operator-interface-bootstrap-configuration "$(MACOS_DEVELOPMENT_DEPLOYMENT_PROFILE_DIRECTORY)/operator-interface-bootstrap-configuration.v1.json" \
		--host-edge-proxy-deployment-configuration "$(MACOS_DEVELOPMENT_DEPLOYMENT_PROFILE_DIRECTORY)/host-edge-proxy-deployment-configuration.v1.json" \
		--host-update-handoff-supervisor-configuration "$(MACOS_DEVELOPMENT_DEPLOYMENT_PROFILE_DIRECTORY)/host-update-handoff-supervisor-configuration.v1.json" \
		--host-update-trust-store "$(MACOS_DEVELOPMENT_DEPLOYMENT_PROFILE_DIRECTORY)/update-trust-store.v1.json" \
		--macos-virtual-machine-configuration "$(MACOS_DEVELOPMENT_DEPLOYMENT_PROFILE_DIRECTORY)/macos-virtual-machine-configuration.v1.json" \
		--guest-product-process-deployment-configuration "$(MACOS_DEVELOPMENT_GUEST_PRODUCT_PROCESS_DEPLOYMENT_CONFIGURATION)" \
		--guest-product-release-manager-configuration "$(CURDIR)/product/guest-product/guest-product-release-manager-configuration.v1.json" \
		--guest-product-service-manager-deployment-configuration "$(CURDIR)/product/guest-product/guest-product-service-manager-deployment.v1.json" \
		--guest-product-bootstrap-configuration "$(MACOS_DEVELOPMENT_GUEST_PRODUCT_BOOTSTRAP_CONFIGURATION)" \
		--guest-product-vitalserver-topology-deployment "$(MACOS_DEVELOPMENT_GUEST_PRODUCT_VITALSERVER_TOPOLOGY_DEPLOYMENT)" \
		$(MACOS_DEVELOPMENT_UPSTREAM_INPUT_ARGUMENTS) \
		--guest-telemetry-collector-configuration "$(CURDIR)/product/observability/guest-telemetry-collector.yaml" \
		--virtualization-entitlements "$(CURDIR)/providers/macos-virtualization/MacOSVirtualMachineSupervisor.entitlements" \
		--pkgbuild "/usr/bin/pkgbuild" \
		--pkgutil "/usr/sbin/pkgutil" \
		--codesign "/usr/bin/codesign" \
		--builder-timeout-seconds "$(or $(MACOS_DEVELOPMENT_GUEST_ARTIFACT_BUILDER_TIMEOUT_SECONDS),3600)"

# One release workspace is one immutable build attempt. Every child target
# publishes a new named output and rejects prior output, so a failed attempt is
# inspectable but cannot be confused with a later package release.
macos-development-release-package-build:
	@[ -n "$(MACOS_DEVELOPMENT_RELEASE_ROOT)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_RELEASE_ROOT to a new existing release workspace'; exit 2; }
	@[ -n "$(MACOS_DEVELOPMENT_GUEST_TARGET_ROOT_STORAGE_OUTPUT_RELATIVE_PATH)" ] || { printf '%s\n' 'set MACOS_DEVELOPMENT_GUEST_TARGET_ROOT_STORAGE_OUTPUT_RELATIVE_PATH'; exit 2; }
	$(MAKE) macos-development-release-artifacts-build
	$(MAKE) macos-development-guest-boot-input-assembly
	$(MAKE) macos-development-release-input-prepare \
		MACOS_DEVELOPMENT_GUEST_KERNEL_SOURCE="$(MACOS_DEVELOPMENT_RELEASE_ROOT)/guest-boot-inputs/c42-artifacts/boot/Image" \
		MACOS_DEVELOPMENT_GUEST_INITIAL_RAMDISK_SOURCE="$(MACOS_DEVELOPMENT_RELEASE_ROOT)/guest-boot-inputs/c42-artifacts/boot/initrd.img" \
		MACOS_DEVELOPMENT_GUEST_ROOT_STORAGE_SOURCE="$(MACOS_DEVELOPMENT_RELEASE_ROOT)/guest-boot-inputs/c43-artifacts/$(MACOS_DEVELOPMENT_GUEST_TARGET_ROOT_STORAGE_OUTPUT_RELATIVE_PATH)"
	$(MAKE) macos-release-package-assembly \
		MACOS_RELEASE_PACKAGE_ASSEMBLY_DECLARATION="$(MACOS_DEVELOPMENT_RELEASE_ROOT)/release-input/macos-release-package-assembly.json"

macos-clean-host-release-evidence-runner-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_macos_clean_host_release_evidence_runner

guest-installed-runtime-evidence-runner-test: ensure-contract-python
	PYTHONWARNINGS=error::ResourceWarning $(PYTHON) -m unittest tooling.tests.test_guest_installed_runtime_evidence_runner

vital-replay-corpus-test: ensure-contract-python
	PYTHONWARNINGS=error::ResourceWarning $(PYTHON) -m unittest tooling.tests.test_vital_replay_corpus

vital-replay-corpus-verify: ensure-contract-python
	@[ -n "$(VITAL_REPLAY_CORPUS_MANIFEST)" ] || { printf '%s\n' 'set VITAL_REPLAY_CORPUS_MANIFEST to an absolute approved C79 manifest path'; exit 2; }
	@[ -n "$(VITAL_REPLAY_CORPUS_DIRECTORY)" ] || { printf '%s\n' 'set VITAL_REPLAY_CORPUS_DIRECTORY to the absolute reviewed corpus directory'; exit 2; }
	$(PYTHON) -m tooling.vital_replay_corpus \
		--contract-root "$(CURDIR)" \
		--manifest "$(VITAL_REPLAY_CORPUS_MANIFEST)" \
		--corpus-directory "$(VITAL_REPLAY_CORPUS_DIRECTORY)"

windows-clean-host-release-evidence-runner-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_windows_clean_host_release_evidence_runner

linux-clean-host-release-evidence-runner-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_linux_clean_host_release_evidence_runner

release-delivery-proof-attachment-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_release_delivery_proof_attachment

release-artifact-sbom-notices-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_release_artifact_sbom_notices

host-platform-release-transition-evidence-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_host_platform_release_transition_evidence

macos-development-installation-evidence-runner-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_macos_development_installation_evidence_runner

ensure-node:
	@node_path="$$(command -v "$(NODE)")"; \
	[ -n "$$node_path" ] || { printf '%s\n' 'Node.js is unavailable; install Node 20.19+ LTS or set NODE'; exit 2; }; \
	node_version="$$($$node_path --version)"; \
	case "$$node_version" in v20.*) ;; *) printf '%s\n' "Guest Node Services require Node >=20.19.0 <21; selected NODE reports $$node_version"; exit 2;; esac; \
	node_minor="$${node_version#v20.}"; node_minor="$${node_minor%%.*}"; \
	case "$$node_minor" in ''|*[!0-9]*) printf '%s\n' "Guest Node Services could not parse selected Node version $$node_version"; exit 2;; esac; \
	[ "$$node_minor" -ge 19 ] || { printf '%s\n' "Guest Node Services require Node >=20.19.0 <21; selected NODE reports $$node_version"; exit 2; }; \
	PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) --version >/dev/null 2>&1 || { printf '%s\n' 'npm is unavailable for the selected Node 20 runtime; set NPM from the same installation'; exit 2; }

recorder-gateway-deps: ensure-node
	@node_path="$$(command -v "$(NODE)")"; \
	cd services/recorder-gateway && PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) ci --include=dev

recorder-gateway-check: recorder-gateway-deps
	@node_path="$$(command -v "$(NODE)")"; \
	cd services/recorder-gateway && PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) run check
	@node_path="$$(command -v "$(NODE)")"; \
	cd services/recorder-gateway && PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) test

lab-recorder-runner-deps: ensure-node
	@node_path="$$(command -v "$(NODE)")"; \
	cd services/lab-recorder-runner && PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) ci

lab-recorder-runner-check: lab-recorder-runner-deps
	@node_path="$$(command -v "$(NODE)")"; \
	cd services/lab-recorder-runner && PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) run check
	@node_path="$$(command -v "$(NODE)")"; \
	cd services/lab-recorder-runner && PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) test

guest-node-services-bundle-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_guest_node_services_bundle_composer

guest-node-services-bundle: recorder-gateway-check lab-recorder-runner-check
	@[ -n "$(GUEST_NODE_SERVICES_GUEST_ARCHITECTURE)" ] || { printf '%s\n' 'set GUEST_NODE_SERVICES_GUEST_ARCHITECTURE to arm64 or amd64'; exit 2; }
	@[ -n "$(GUEST_NODE_DISTRIBUTION_ROOT)" ] || { printf '%s\n' 'set GUEST_NODE_DISTRIBUTION_ROOT to an absolute Linux Node distribution root for GUEST_NODE_SERVICES_GUEST_ARCHITECTURE'; exit 2; }
	@[ -n "$(GUEST_NODE_SERVICES_BUNDLE_OUTPUT)" ] || { printf '%s\n' 'set GUEST_NODE_SERVICES_BUNDLE_OUTPUT to a new absolute tar-gzip output path'; exit 2; }
	@node_path="$$(command -v "$(NODE)")"; \
	staging_root="$$(mktemp -d "$${TMPDIR:-/tmp}/vitalserver-guest-node-services.XXXXXX")"; \
	trap '$(SYSTEM_PYTHON) -c '\''import shutil, sys; shutil.rmtree(sys.argv[1], ignore_errors=True)'\'' "$$staging_root"' EXIT; \
	for service in recorder-gateway lab-recorder-runner; do \
		mkdir -p "$$staging_root/$$service"; \
		cp "services/$$service/package.json" "services/$$service/package-lock.json" "$$staging_root/$$service/"; \
		PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) --prefix "$$staging_root/$$service" ci --omit=dev --ignore-scripts; \
		cp -R "services/$$service/dist" "$$staging_root/$$service/dist"; \
	done; \
	$(SYSTEM_PYTHON) -m tooling.guest_node_services_bundle_composer --node-distribution-root "$(GUEST_NODE_DISTRIBUTION_ROOT)" --guest-architecture "$(GUEST_NODE_SERVICES_GUEST_ARCHITECTURE)" --recorder-gateway-root "$$staging_root/recorder-gateway" --lab-recorder-runner-root "$$staging_root/lab-recorder-runner" --lab-scenario-catalog "$$(pwd)/product/guest-product/lab-scenario-catalog.v1.json" --output-archive "$(GUEST_NODE_SERVICES_BUNDLE_OUTPUT)"

recorder-gateway-acceptance: recorder-gateway-deps ensure-contract-python
	@node_path="$$(command -v "$(NODE)")"; \
	PATH="$$(dirname "$$node_path"):$$PATH" RUNTIME_PLATFORM_GO="$(GO)" RUNTIME_PLATFORM_NODE="$(NODE)" RUNTIME_PLATFORM_NPM="$(NPM)" $(PYTHON) -m unittest acceptance.harness.test_bundled_capability acceptance.harness.test_recorder_gateway

lab-recorder-runner-gateway-acceptance: recorder-gateway-check lab-recorder-runner-check ensure-contract-python
	@node_path="$$(command -v "$(NODE)")"; \
	PATH="$$(dirname "$$node_path"):$$PATH" RUNTIME_PLATFORM_NODE="$(NODE)" $(PYTHON) -m unittest acceptance.harness.test_lab_recorder_runner_gateway

lab-replay-guest-runtime-acceptance: recorder-gateway-check lab-recorder-runner-check ensure-contract-python ensure-go
	@test -n "$(VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL)" \
		|| { printf '%s\n' 'C4 acceptance requires a migrated PostgreSQL test database URL'; exit 2; }
	@node_path="$$(command -v "$(NODE)")"; \
	PATH="$$(dirname "$$node_path"):$$PATH" \
		RUNTIME_PLATFORM_GO="$(GO)" \
		RUNTIME_PLATFORM_NODE="$(NODE)" \
		VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL="$(VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL)" \
		$(PYTHON) -m unittest acceptance.harness.test_lab_replay_guest_runtime

lab-replay-approved-corpus-acceptance: recorder-gateway-check lab-recorder-runner-check ensure-contract-python ensure-go
	@test -n "$(VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL)" \
		|| { printf '%s\n' 'C79 replay acceptance requires a migrated PostgreSQL test database URL'; exit 2; }
	@test -n "$(VITAL_REPLAY_CORPUS_MANIFEST)" \
		|| { printf '%s\n' 'C79 replay acceptance requires an absolute approved manifest path'; exit 2; }
	@test -n "$(VITAL_REPLAY_CORPUS_DIRECTORY)" \
		|| { printf '%s\n' 'C79 replay acceptance requires an absolute reviewed corpus directory'; exit 2; }
	@node_path="$$(command -v "$(NODE)")"; \
	PATH="$$(dirname "$$node_path"):$$PATH" \
		RUNTIME_PLATFORM_GO="$(GO)" \
		RUNTIME_PLATFORM_NODE="$(NODE)" \
		RUNTIME_PLATFORM_VITAL_REPLAY_CORPUS_MANIFEST="$(VITAL_REPLAY_CORPUS_MANIFEST)" \
		RUNTIME_PLATFORM_VITAL_REPLAY_CORPUS_DIRECTORY="$(VITAL_REPLAY_CORPUS_DIRECTORY)" \
		VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL="$(VITALSERVER_RECORDER_CATALOG_TEST_DATABASE_URL)" \
		$(PYTHON) -m unittest \
		acceptance.harness.test_lab_replay_guest_runtime.LabReplayGuestRuntimeAcceptance.test_guest_worker_persists_vitalserver_acknowledged_replay

lab-archive-acceptance: ensure-go ensure-contract-python
	RUNTIME_PLATFORM_GO="$(GO)" $(PYTHON) -m unittest acceptance.harness.test_lab_archive_deletion

external-time-observability-acceptance: ensure-go ensure-contract-python
	RUNTIME_PLATFORM_GO="$(GO)" $(PYTHON) -m unittest acceptance.harness.test_external_time_observability

portable-provider-test: ensure-go
	cd providers/os-provider-bridge && $(GO) test ./...
	mkdir -p providers/os-provider-bridge/.build
	cd providers/os-provider-bridge && GOOS=linux GOARCH=amd64 $(GO) build -o .build/linux-kvm-libvirt-systemd-bridge ./cmd/linux-kvm-libvirt-systemd-bridge
	cd providers/os-provider-bridge && GOOS=windows GOARCH=amd64 $(GO) build -o .build/windows-hyperv-scm-bridge.exe ./cmd/windows-hyperv-scm-bridge

source-inventory-check: ensure-contract-python
	$(PYTHON) -m tooling.generate_source_inventory_sbom --root . --check

delivery-proof-check: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_delivery_proofs
	$(PYTHON) -m tooling.verify_delivery_proofs --root .

# This target intentionally fails while any C24 stage is pending. It is the
# release assertion, not a development check, and must run on the matching OS
# clean-host runner after evidence is attached.
release-ready: ensure-contract-python
	@[ -n "$(RELEASE_DELIVERY_PROOF_ATTACHMENT_REVIEW_DOCUMENT)" ] || { printf '%s\n' 'set RELEASE_DELIVERY_PROOF_ATTACHMENT_REVIEW_DOCUMENT to an absolute C74 review document path'; exit 2; }
	$(PYTHON) -m tooling.verify_delivery_proofs --root . --release-delivery-plans-document "$(RELEASE_DELIVERY_PLANS_DOCUMENT)" --source-release-delivery-proof-set-document "$(CURDIR)/product/delivery/release-delivery-proofs.v1.json" --release-delivery-proof-set-document "$(RELEASE_DELIVERY_PROOF_SET_DOCUMENT)" --release-delivery-proof-attachment-review-document "$(RELEASE_DELIVERY_PROOF_ATTACHMENT_REVIEW_DOCUMENT)" --release-delivery-plan-id "$(RELEASE_DELIVERY_PLAN_ID)" --require-verified

cross-platform-delivery-acceptance: ensure-go ensure-contract-python
	RUNTIME_PLATFORM_GO="$(GO)" $(PYTHON) -m unittest acceptance.harness.test_cross_platform_delivery

host-updater-test: ensure-go
	cd services/host-updater && $(GO) test ./...

host-update-handoff-supervisor-test: ensure-go
	cd services/host-update-handoff-supervisor && $(GO) test ./...

host-service-runner-test: ensure-go
	cd services/host-service-runner && GOTOOLCHAIN=go1.25.7+auto $(GO) test ./...

host-service-runner-cross-platform-build: ensure-go
	cd services/host-service-runner && mkdir -p .build
	cd services/host-service-runner && GOOS=darwin GOARCH=arm64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/darwin-arm64-host-service-runner ./cmd/host-service-runner
	cd services/host-service-runner && GOOS=linux GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/linux-amd64-host-service-runner ./cmd/host-service-runner
	cd services/host-service-runner && GOOS=windows GOARCH=amd64 GOTOOLCHAIN=go1.25.7+auto $(GO) build -o .build/windows-amd64-host-service-runner.exe ./cmd/host-service-runner

host-installation-manager-test: ensure-go
	cd services/host-installation-manager && $(GO) test ./...

host-installation-manager-build: ensure-go
	cd services/host-installation-manager && mkdir -p .build
	cd services/host-installation-manager && GOOS=darwin GOARCH=arm64 $(GO) build -o .build/darwin-arm64-host-installation-manager ./cmd/host-installation-manager
	cd services/host-installation-manager && GOOS=linux GOARCH=amd64 $(GO) build -o .build/linux-amd64-host-installation-manager ./cmd/host-installation-manager
	cd services/host-installation-manager && GOOS=windows GOARCH=amd64 $(GO) build -o .build/windows-amd64-host-installation-manager.exe ./cmd/host-installation-manager

release-composer-test: ensure-go
	cd tooling/release-composer && $(GO) test ./...

installation-update-acceptance: ensure-go ensure-contract-python
	RUNTIME_PLATFORM_GO="$(GO)" $(PYTHON) -m unittest acceptance.harness.test_installation_update_foundation

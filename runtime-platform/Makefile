SYSTEM_PYTHON ?= python3
VENV ?= .venv
PYTHON ?= $(VENV)/bin/python
GO ?= go
GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO ?= $(GO)
GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN ?= go1.25.7+auto
GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO ?= $(GO)
GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN ?= go1.25.7+auto
GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO ?= $(GO)
GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN ?= go1.25.7+auto
SWIFT ?= swift
NODE ?= node
NPM ?= npm

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
	ensure-go \
	service-go-test \
	guest-product-process-supervisor-test \
	host-edge-proxy-test \
	host-guest-acceptance \
	macos-provider-test \
	guest-artifact-compiler-test \
	guest-artifact-compilation-input-assembler-test \
	guest-linux-boot-artifact-extractor-test \
	guest-linux-boot-artifact-extractor-build \
	guest-linux-boot-artifact-extractor-cross-platform-build \
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
	macos-release-package-assembly-test \
	macos-release-package-assembly \
	macos-clean-host-release-evidence-runner-test \
	ensure-node \
	recorder-gateway-deps \
	recorder-gateway-check \
	recorder-gateway-acceptance \
	lab-archive-acceptance \
	external-time-observability-acceptance \
	portable-provider-test \
	source-inventory-check \
	delivery-proof-check \
	release-ready \
	cross-platform-delivery-acceptance \
	host-updater-test \
	release-composer-test \
	installation-update-acceptance \
	check

check: test-boundaries boundary-check test-reference-fixtures reference-fixture-check test-contracts contract-check service-go-test host-edge-proxy-test guest-product-process-supervisor-test host-guest-acceptance macos-provider-test guest-artifact-compiler-test guest-artifact-compilation-input-assembler-test guest-linux-boot-artifact-extractor-test guest-linux-boot-artifact-extractor-cross-platform-build guest-root-storage-partition-assembler-test guest-product-bootstrap-volume-composer-test guest-product-bootstrap-volume-composer-cross-platform-build guest-product-bootstrap-artifact-composer-test guest-product-bootstrap-artifact-composer-cross-platform-build guest-product-systemd-service-unit-composer-test macos-guest-artifact-manifest-composer-test macos-installer-component-cpio-test macos-host-package-composer-test macos-release-package-assembly-test macos-clean-host-release-evidence-runner-test recorder-gateway-check recorder-gateway-acceptance lab-archive-acceptance external-time-observability-acceptance portable-provider-test source-inventory-check delivery-proof-check cross-platform-delivery-acceptance host-updater-test release-composer-test installation-update-acceptance

bootstrap-contract-tools:
	$(SYSTEM_PYTHON) -m venv $(VENV)
	$(VENV)/bin/python -m pip install --disable-pip-version-check --requirement contracts/requirements-dev.txt

boundary-check:
	$(SYSTEM_PYTHON) tooling/verify_boundaries.py --root .

test-boundaries:
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_verify_boundaries

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

ensure-go:
	@$(GO) version >/dev/null 2>&1 || { printf '%s\n' 'Go is unavailable; install Go 1.23 or set GO'; exit 2; }

service-go-test: ensure-go
	cd services/guest-runtime && $(GO) test ./...
	cd services/host-agent && $(GO) test ./...

host-edge-proxy-test: ensure-go
	cd services/host-edge-proxy && $(GO) test ./...

guest-product-process-supervisor-test: ensure-go
	cd services/guest-product-process-supervisor && $(GO) test ./...

host-guest-acceptance: ensure-go
	RUNTIME_PLATFORM_GO="$(GO)" $(SYSTEM_PYTHON) -m unittest acceptance.harness.test_host_guest_control

macos-provider-test:
	@$(SWIFT) --version >/dev/null 2>&1 || { printf '%s\n' 'Swift is unavailable; install Xcode Command Line Tools or set SWIFT'; exit 2; }
	$(SWIFT) test --package-path providers/macos-virtualization
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_macos_virtual_machine_command_cli

guest-artifact-compiler-test:
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_guest_artifact_compiler

guest-artifact-compilation-input-assembler-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_guest_artifact_compilation_input_assembler

guest-linux-boot-artifact-extractor-test:
	cd tooling/guest-linux-boot-artifact-extractor && GOTOOLCHAIN="$(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN)" $(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO) test ./...

guest-linux-boot-artifact-extractor-build:
	cd tooling/guest-linux-boot-artifact-extractor && mkdir -p .build
	cd tooling/guest-linux-boot-artifact-extractor && GOTOOLCHAIN="$(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN)" GOOS=darwin GOARCH=arm64 $(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO) build -o .build/darwin-arm64-guest-linux-boot-artifact-extractor ./cmd/guest-linux-boot-artifact-extractor

guest-linux-boot-artifact-extractor-cross-platform-build: guest-linux-boot-artifact-extractor-build
	cd tooling/guest-linux-boot-artifact-extractor && mkdir -p .build
	cd tooling/guest-linux-boot-artifact-extractor && GOTOOLCHAIN="$(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN)" GOOS=linux GOARCH=arm64 $(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO) build -o .build/linux-arm64-guest-linux-boot-artifact-extractor ./cmd/guest-linux-boot-artifact-extractor
	cd tooling/guest-linux-boot-artifact-extractor && GOTOOLCHAIN="$(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GOTOOLCHAIN)" GOOS=windows GOARCH=amd64 $(GUEST_LINUX_BOOT_ARTIFACT_EXTRACTOR_GO) build -o .build/windows-amd64-guest-linux-boot-artifact-extractor.exe ./cmd/guest-linux-boot-artifact-extractor

guest-root-storage-partition-assembler-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_guest_root_storage_partition_assembler

guest-product-bootstrap-volume-composer-test:
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN)" $(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO) test ./...

guest-product-bootstrap-volume-composer-build:
	cd tooling/guest-product-bootstrap-volume-composer && mkdir -p .build
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN)" GOOS=darwin GOARCH=arm64 $(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO) build -o .build/darwin-arm64-guest-product-bootstrap-volume-composer ./cmd/guest-product-bootstrap-volume-composer

guest-product-bootstrap-volume-composer-cross-platform-build: guest-product-bootstrap-volume-composer-build
	cd tooling/guest-product-bootstrap-volume-composer && mkdir -p .build
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN)" GOOS=linux GOARCH=arm64 $(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO) build -o .build/linux-arm64-guest-product-bootstrap-volume-composer ./cmd/guest-product-bootstrap-volume-composer
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GOTOOLCHAIN)" GOOS=windows GOARCH=amd64 $(GUEST_PRODUCT_BOOTSTRAP_VOLUME_COMPOSER_GO) build -o .build/windows-amd64-guest-product-bootstrap-volume-composer.exe ./cmd/guest-product-bootstrap-volume-composer

guest-product-bootstrap-artifact-composer-test:
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN)" $(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO) test ./internal/guestproductbootstrapartifactcompositionapplication ./internal/guestproductbootstrapplancomposer ./internal/guestproductbootstrapvolumeapplication ./internal/nocloudguestproductbootstrapvolumeadapter

guest-product-bootstrap-artifact-composer-build:
	cd tooling/guest-product-bootstrap-volume-composer && mkdir -p .build
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN)" GOOS=darwin GOARCH=arm64 $(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO) build -o .build/darwin-arm64-guest-product-bootstrap-artifact-composer ./cmd/guest-product-bootstrap-artifact-composer

guest-product-bootstrap-artifact-composer-cross-platform-build: guest-product-bootstrap-artifact-composer-build
	cd tooling/guest-product-bootstrap-volume-composer && mkdir -p .build
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN)" GOOS=linux GOARCH=arm64 $(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO) build -o .build/linux-arm64-guest-product-bootstrap-artifact-composer ./cmd/guest-product-bootstrap-artifact-composer
	cd tooling/guest-product-bootstrap-volume-composer && GOTOOLCHAIN="$(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GOTOOLCHAIN)" GOOS=windows GOARCH=amd64 $(GUEST_PRODUCT_BOOTSTRAP_ARTIFACT_COMPOSER_GO) build -o .build/windows-amd64-guest-product-bootstrap-artifact-composer.exe ./cmd/guest-product-bootstrap-artifact-composer

guest-product-systemd-service-unit-composer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_guest_product_systemd_service_unit_composer

macos-guest-artifact-manifest-composer-test:
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_macos_guest_artifact_manifest_composer

macos-installer-component-cpio-test:
	$(SYSTEM_PYTHON) -m unittest tooling.tests.test_macos_installer_component_cpio

macos-host-package-composer-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_macos_host_package_composer

macos-release-package-assembly-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_macos_release_package_assembly

macos-release-package-assembly: ensure-contract-python
	@[ -n "$(MACOS_RELEASE_PACKAGE_ASSEMBLY_DECLARATION)" ] || { printf '%s\n' 'set MACOS_RELEASE_PACKAGE_ASSEMBLY_DECLARATION to an absolute C47 declaration path'; exit 2; }
	$(PYTHON) -m tooling.macos_release_package_assembly --assembly-declaration "$(MACOS_RELEASE_PACKAGE_ASSEMBLY_DECLARATION)"

macos-clean-host-release-evidence-runner-test: ensure-contract-python
	$(PYTHON) -m unittest tooling.tests.test_macos_clean_host_release_evidence_runner

ensure-node:
	@node_path="$$(command -v "$(NODE)")"; \
	[ -n "$$node_path" ] || { printf '%s\n' 'Node.js is unavailable; install Node 20.19+ LTS or set NODE'; exit 2; }; \
	node_version="$$($$node_path --version)"; \
	case "$$node_version" in v20.*) ;; *) printf '%s\n' "Recorder Gateway requires Node >=20.19.0 <21; selected NODE reports $$node_version"; exit 2;; esac; \
	node_minor="$${node_version#v20.}"; node_minor="$${node_minor%%.*}"; \
	case "$$node_minor" in ''|*[!0-9]*) printf '%s\n' "Recorder Gateway could not parse selected Node version $$node_version"; exit 2;; esac; \
	[ "$$node_minor" -ge 19 ] || { printf '%s\n' "Recorder Gateway requires Node >=20.19.0 <21; selected NODE reports $$node_version"; exit 2; }; \
	PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) --version >/dev/null 2>&1 || { printf '%s\n' 'npm is unavailable for the selected Node 20 runtime; set NPM from the same installation'; exit 2; }

recorder-gateway-deps: ensure-node
	@node_path="$$(command -v "$(NODE)")"; \
	cd services/recorder-gateway && PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) ci

recorder-gateway-check: recorder-gateway-deps
	@node_path="$$(command -v "$(NODE)")"; \
	cd services/recorder-gateway && PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) run check
	@node_path="$$(command -v "$(NODE)")"; \
	cd services/recorder-gateway && PATH="$$(dirname "$$node_path"):$$PATH" $(NPM) test

recorder-gateway-acceptance: recorder-gateway-deps ensure-contract-python
	@node_path="$$(command -v "$(NODE)")"; \
	PATH="$$(dirname "$$node_path"):$$PATH" RUNTIME_PLATFORM_GO="$(GO)" RUNTIME_PLATFORM_NODE="$(NODE)" RUNTIME_PLATFORM_NPM="$(NPM)" $(PYTHON) -m unittest acceptance.harness.test_bundled_capability acceptance.harness.test_recorder_gateway

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
	$(PYTHON) -m tooling.verify_delivery_proofs --root . --require-verified

cross-platform-delivery-acceptance: ensure-go ensure-contract-python
	RUNTIME_PLATFORM_GO="$(GO)" $(PYTHON) -m unittest acceptance.harness.test_cross_platform_delivery

host-updater-test: ensure-go
	cd services/host-updater && $(GO) test ./...

release-composer-test: ensure-go
	cd tooling/release-composer && $(GO) test ./...

installation-update-acceptance: ensure-go ensure-contract-python
	RUNTIME_PLATFORM_GO="$(GO)" $(PYTHON) -m unittest acceptance.harness.test_installation_update_foundation

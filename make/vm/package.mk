.PHONY: internal/vm/nginx/artifact internal/vm/nginx/bundle internal/vm/docker/images
.PHONY: internal/vm/require-release-branch
.PHONY: internal/vm/pkg internal/vm/pkg/dev internal/vm/pkg/dev/compile internal/vm/pkg/dev/runtime-smoke internal/vm/pkg/dev/verify internal/vm/pkg/release internal/vm/pkg/release/verify
.PHONY: internal/vm/troubleshooting internal/vm/troubleshooting/dev internal/vm/troubleshooting/release
.PHONY: internal/vm/app internal/vm/dmg internal/vm/dmg/dev internal/vm/dmg/dev/compile internal/vm/dmg/dev/runtime-smoke internal/vm/dmg/dev/verify internal/vm/dmg/release internal/vm/dmg/release/verify
.PHONY: internal/vm/pkg/clean internal/vm/pkg/install internal/vm/pkg/uninstall/dev
.PHONY: internal/vm/update internal/vm/update/dev internal/vm/update/release
.PHONY: internal/vm/image-update internal/vm/image-update/dev
.PHONY: internal/vm/image-update/release
.PHONY: internal/vm/update/verify internal/vm/update/verify/dev
.PHONY: internal/vm/update/verify/release
.PHONY: internal/vm/image-update/verify internal/vm/image-update/verify/dev
.PHONY: internal/vm/image-update/verify/release
.PHONY: internal/vm/airgap-rootfs internal/vm/golden-rootfs internal/vm/golden-rootfs/compile internal/vm/golden-rootfs/negative internal/vm/golden-rootfs/runtime-smoke

# Public update bundle knobs.
VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE ?= false
VM_UPDATE_BUNDLE_KIND ?= product-update
VM_UPDATE_TARGET_PLATFORM ?=
VM_UPDATE_ROOTFS_BASE ?=

# Public package artifact knobs.
VM_NGINX_SOURCE_BIN ?= /opt/homebrew/opt/nginx/bin/nginx
VM_NGINX_BIN ?=

# Internal package artifact paths.
VM_NGINX_ARTIFACT_BIN := .artifacts/nginx/macos/bin/nginx

# Internal package rootfs cache paths.
VM_PKG_BUILD_DIR ?= $(call VM_TOML_VALUE,workspace.build_dir)
VM_PKG_ROOTFS_CACHE ?= $(VM_PKG_BUILD_DIR)/rootfs-base.raw.gz
VM_PKG_ROOTFS_CONTRACT_STAMP ?= $(VM_PKG_BUILD_DIR)/rootfs-base.contract
VM_PKG_ROOTFS_CONTRACT_INPUTS := \
	config/vm-build.toml \
	$(VM_MACOS_RUNTIME_DIR)/Support/Guest/prepare-airgap-rootfs.sh \
	$(VM_MACOS_RUNTIME_DIR)/Support/Guest/bootstrap.sh \
	packages/vitalserver-guest-tools/pyproject.toml \
	packages/vitalserver-guest-tools/src/tirosh_guest_tools/contracts.py \
	packages/vitalserver-guest-tools/src/tirosh_guest_tools/application/bootstrap.py \
	packages/vitalserver-guest-tools/src/tirosh_guest_tools/infrastructure/bootstrap_operations.py \
	packages/vitalserver-guest-tools/src/tirosh_guest_tools/application/rootfs_smoke.py \
	packages/vitalserver-guest-tools/src/tirosh_guest_tools/application/runtime_boot_smoke.py
VM_PKG_ROOTFS_CONTRACT_FINGERPRINT := $(shell cksum $(VM_PKG_ROOTFS_CONTRACT_INPUTS) | cksum | awk '{print $$1 "-" $$2}')

# Internal golden rootfs workspaces.
VM_GOLDEN_HOME := .tmp/vitalserver-vm-golden
VM_GOLDEN_RUNTIME_DIR := $(VM_GOLDEN_HOME)/runtime

# Diagnostic/CI golden rootfs workspaces.
VM_GOLDEN_NEGATIVE_HOME ?= .tmp/vitalserver-vm-golden-negative
VM_GOLDEN_RUNTIME_SMOKE_HOME ?= .tmp/vitalserver-vm-golden-runtime-smoke
VM_AIRGAP_CLEANUP_WAIT_TIMEOUT ?= 30
VM_AIRGAP_FORCE_STOP_TIMEOUT ?= 5

# Public install/uninstall knobs.
VM_INSTALL_SETTINGS ?=
VM_UNINSTALL_ARGS ?=

internal/vm/airgap-rootfs:
	@$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		stop >/dev/null 2>&1 || true
	$(VM_BUILD_RUNNER) macos-runtime-require-no-running \
		--vm-home "$(VM_HOME)"
	$(MAKE) internal/vm/download \
		VM_HOME="$(VM_HOME)" \
		VM_RECREATE_ROOTFS="$(VM_RECREATE_ROOTFS)"
	$(MAKE) internal/vm/stage \
		VM_HOME="$(VM_HOME)" \
		VM_ROOTFS_RUN_ID="$(VM_ROOTFS_RUN_ID)" \
		VM_RUNTIME_BOOT_SMOKE="$(VM_RUNTIME_BOOT_SMOKE)" \
		VM_RUNTIME_BOOT_SMOKE_RUN_ID="$(VM_RUNTIME_BOOT_SMOKE_RUN_ID)"
	@$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		stop >/dev/null 2>&1 || true
	$(VM_BUILD_RUNNER) macos-runtime-require-no-running \
		--vm-home "$(VM_HOME)"
	@if [ -n "$(VM_ROOTFS_RUN_ID)" ]; then \
		$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-rootfs-begin \
			--vm-home "$(VM_HOME)" \
			--run-id "$(VM_ROOTFS_RUN_ID)"; \
	else \
		rm -f "$(VM_HOME)/data/run/rootfs-ready"; \
	fi
	@if [ -n "$(VM_ROOTFS_SMOKE_FAIL_STAGE)" ] || [ "$(VM_ROOTFS_SMOKE_FAIL_CLEANUP)" = "true" ]; then \
		python3 -c 'import json, sys; from pathlib import Path; path = Path(sys.argv[1]); document = json.loads(path.read_text(encoding="utf-8")); document["faultInjection"] = {"testMode": True, "failStage": sys.argv[2], "failCleanup": sys.argv[3] == "true"}; path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")' "$(VM_HOME)/data/deploy/build-metadata/rootfs-input.json" "$(VM_ROOTFS_SMOKE_FAIL_STAGE)" "$(VM_ROOTFS_SMOKE_FAIL_CLEANUP)"; \
	fi
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-preflight-golden-rootfs \
		--vm-home "$(VM_HOME)" \
		--expected-run-id "$(VM_ROOTFS_RUN_ID)"
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" cloud-init \
		--runtime-dir "$(VM_RUNTIME_DIR)" \
		--bootstrap-script "/mnt/tirosh/deploy/prepare-airgap-rootfs.sh"
	@set -e; \
	cleanup_airgap_rootfs() { \
		status="$$?"; \
		cleanup_status="$${status}"; \
		$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
			--vm-home "$(VM_HOME)" \
			stop >/dev/null 2>&1 || true; \
		if ! $(VM_BUILD_RUNNER) macos-runtime-wait-stopped \
			--vm-home "$(VM_HOME)" \
			--timeout "$(VM_AIRGAP_CLEANUP_WAIT_TIMEOUT)" >/dev/null 2>&1; then \
			$(VM_BUILD_RUNNER) macos-runtime-force-stop \
				--vm-home "$(VM_HOME)" \
				--timeout "$(VM_AIRGAP_FORCE_STOP_TIMEOUT)" || cleanup_status="1"; \
		fi; \
		if ! $(VM_BUILD_RUNNER) macos-runtime-require-no-running \
			--vm-home "$(VM_HOME)"; then \
			$(VM_BUILD_RUNNER) macos-runtime-force-stop \
				--vm-home "$(VM_HOME)" \
				--timeout "$(VM_AIRGAP_FORCE_STOP_TIMEOUT)" || cleanup_status="1"; \
		fi; \
		exit "$${cleanup_status}"; \
	}; \
	trap cleanup_airgap_rootfs EXIT; \
	$(MAKE) internal/vm/start/detached \
		VM_HOME="$(VM_HOME)"; \
	$(MAKE) internal/vm/wait/rootfs-ready \
		VM_HOME="$(VM_HOME)" \
		VM_ROOTFS_RUN_ID="$(VM_ROOTFS_RUN_ID)"; \
	$(MAKE) internal/vm/stop \
		VM_HOME="$(VM_HOME)"; \
	trap - EXIT; \
	$(VM_BUILD_RUNNER) macos-runtime-require-no-running \
		--vm-home "$(VM_HOME)"; \
	printf "Air-gapped rootfs is prepared: %s\n" "$(VM_RUNTIME_DIR)/vm-disk.img"

internal/vm/golden-rootfs:
	@set -e; \
	rootfs_contract_expected="$(VM_PKG_ROOTFS_CONTRACT_FINGERPRINT)"; \
	rootfs_contract_actual=""; \
	if [ -s "$(VM_PKG_ROOTFS_CONTRACT_STAMP)" ]; then \
		rootfs_contract_actual="$$(cat "$(VM_PKG_ROOTFS_CONTRACT_STAMP)")"; \
	fi; \
	if [ "$(VM_RECREATE_ROOTFS)" = "false" ] \
		&& [ -s "$(VM_PKG_ROOTFS_CACHE)" ] \
		&& [ -s "$(VM_GOLDEN_RUNTIME_DIR)/Image" ] \
		&& [ -s "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" ] \
		&& [ "$${rootfs_contract_actual}" = "$${rootfs_contract_expected}" ]; then \
		printf "Reusing golden rootfs cache: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
	else \
		rootfs_run_id="$$(uuidgen | tr '[:upper:]' '[:lower:]')"; \
		if [ "$(VM_RECREATE_ROOTFS)" != "false" ]; then \
			printf "Recreating golden rootfs cache: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
		elif [ -s "$(VM_PKG_ROOTFS_CACHE)" ]; then \
			if [ -z "$${rootfs_contract_actual}" ]; then \
				printf "Golden rootfs cache missing contract stamp; rebuilding: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
			else \
				printf "Golden rootfs cache contract changed; rebuilding: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
			fi; \
		fi; \
		$(MAKE) internal/vm/docker/images; \
		$(MAKE) internal/vm/airgap-rootfs \
			VM_HOME="$(abspath $(VM_GOLDEN_HOME))" \
			VM_RECREATE_ROOTFS="$(VM_RECREATE_ROOTFS)" \
			VM_ROOTFS_RUN_ID="$${rootfs_run_id}"; \
		test -s "$(VM_GOLDEN_HOME)/data/run/rootfs-ready" || { \
			printf "missing air-gapped rootfs marker after prepare: %s\n" "$(VM_GOLDEN_HOME)/data/run/rootfs-ready" >&2; \
			exit 1; \
		}; \
		$(VM_BUILD_RUNNER) rootfs-base \
			--source "$(VM_GOLDEN_RUNTIME_DIR)/vm-disk.img" \
			--output "$(VM_PKG_ROOTFS_CACHE)" \
			--compression-threads "$(VM_COMPRESSION_THREADS)" \
			--expected-run-id "$${rootfs_run_id}"; \
		mkdir -p "$(dir $(VM_PKG_ROOTFS_CONTRACT_STAMP))"; \
		printf "%s\n" "$${rootfs_contract_expected}" >"$(VM_PKG_ROOTFS_CONTRACT_STAMP)"; \
	fi

internal/vm/golden-rootfs/compile:
	$(MAKE) internal/vm/golden-rootfs VM_RECREATE_ROOTFS=true

internal/vm/golden-rootfs/negative:
	@set -e; \
	rootfs_run_id="$$(uuidgen | tr '[:upper:]' '[:lower:]')"; \
	printf "Running golden rootfs negative VM test: edge-ready fault runId=%s\n" "$${rootfs_run_id}"; \
	set +e; \
	$(MAKE) internal/vm/airgap-rootfs \
		VM_HOME="$(abspath $(VM_GOLDEN_NEGATIVE_HOME))" \
		VM_RECREATE_ROOTFS=true \
		VM_ROOTFS_RUN_ID="$${rootfs_run_id}" \
		VM_ROOTFS_SMOKE_FAIL_STAGE="edge-ready"; \
	status="$$?"; \
	set -e; \
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(abspath $(VM_GOLDEN_NEGATIVE_HOME))" \
		stop >/dev/null 2>&1 || true; \
	$(VM_BUILD_RUNNER) macos-runtime-wait-stopped \
		--vm-home "$(abspath $(VM_GOLDEN_NEGATIVE_HOME))" \
		--timeout "$(VM_WAIT_TIMEOUT)" >/dev/null 2>&1 || true; \
	$(VM_BUILD_RUNNER) macos-runtime-require-no-running \
		--vm-home "$(abspath $(VM_GOLDEN_NEGATIVE_HOME))"; \
	if [ "$${status}" -eq 0 ]; then \
		printf "error: negative golden rootfs VM test unexpectedly passed\n" >&2; \
		exit 1; \
	fi; \
	set +e; \
	$(VM_BUILD_RUNNER) rootfs-base \
		--source "$(VM_GOLDEN_NEGATIVE_HOME)/runtime/vm-disk.img" \
		--output "$(VM_GOLDEN_NEGATIVE_HOME)/rootfs-base.should-not-exist.raw.gz" \
		--compression-threads "1" \
		--expected-run-id "$${rootfs_run_id}" >/tmp/tirosh-golden-rootfs-negative-rootfs-base.log 2>&1; \
	rootfs_base_status="$$?"; \
	set -e; \
	if [ "$${rootfs_base_status}" -eq 0 ]; then \
		printf "error: negative rootfs-base gate unexpectedly passed\n" >&2; \
		exit 1; \
	fi; \
	printf "Golden rootfs negative VM test passed: edge-ready fault was rejected\n"

internal/vm/golden-rootfs/runtime-smoke: internal/vm/golden-rootfs
	@set -e; \
	runtime_smoke_run_id="$$(uuidgen | tr '[:upper:]' '[:lower:]')"; \
	runtime_smoke_home="$(abspath $(VM_GOLDEN_RUNTIME_SMOKE_HOME))"; \
	runtime_smoke_runtime_dir="$${runtime_smoke_home}/runtime"; \
	printf "Running golden disk runtime boot smoke: runId=%s\n" "$${runtime_smoke_run_id}"; \
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$${runtime_smoke_home}" \
		stop >/dev/null 2>&1 || true; \
	$(VM_BUILD_RUNNER) macos-runtime-wait-stopped \
		--vm-home "$${runtime_smoke_home}" \
		--timeout "$(VM_WAIT_TIMEOUT)" >/dev/null 2>&1 || true; \
	$(VM_BUILD_RUNNER) macos-runtime-require-no-running \
		--vm-home "$${runtime_smoke_home}"; \
	trap '$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control --vm-home "'"$${runtime_smoke_home}"'" stop >/dev/null 2>&1 || true; $(VM_BUILD_RUNNER) macos-runtime-wait-stopped --vm-home "'"$${runtime_smoke_home}"'" --timeout "$(VM_WAIT_TIMEOUT)" >/dev/null 2>&1 || true; $(VM_BUILD_RUNNER) macos-runtime-require-no-running --vm-home "'"$${runtime_smoke_home}"'" || true' EXIT; \
	$(MAKE) internal/vm/init \
		VM_HOME="$${runtime_smoke_home}"; \
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-prepare-runtime-data-disk \
		--vm-home "$${runtime_smoke_home}"; \
	mkdir -p "$${runtime_smoke_runtime_dir}"; \
	cp "$(VM_GOLDEN_RUNTIME_DIR)/Image" "$${runtime_smoke_runtime_dir}/Image"; \
	cp "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" "$${runtime_smoke_runtime_dir}/initrd.img"; \
	gzip -dc "$(VM_PKG_ROOTFS_CACHE)" > "$${runtime_smoke_runtime_dir}/vm-disk.img"; \
	$(MAKE) internal/vm/cloud-init \
		VM_HOME="$${runtime_smoke_home}"; \
	$(MAKE) internal/vm/stage \
		VM_HOME="$${runtime_smoke_home}" \
		VM_RUNTIME_BOOT_SMOKE=true \
		VM_RUNTIME_BOOT_SMOKE_RUN_ID="$${runtime_smoke_run_id}"; \
	$(VM_BUILD_RUNNER) macos-runtime-boot-smoke-begin \
		--vm-home "$${runtime_smoke_home}" \
		--run-id "$${runtime_smoke_run_id}"; \
	$(MAKE) internal/vm/start/detached \
		VM_HOME="$${runtime_smoke_home}"; \
	$(MAKE) internal/vm/wait/runtime-boot-smoke \
		VM_HOME="$${runtime_smoke_home}" \
		VM_RUNTIME_BOOT_SMOKE_RUN_ID="$${runtime_smoke_run_id}"; \
	printf "Cleaning up runtime smoke VM...\n"; \
	$(MAKE) internal/vm/stop \
		VM_HOME="$${runtime_smoke_home}"; \
	$(VM_BUILD_RUNNER) macos-runtime-require-no-running \
		--vm-home "$${runtime_smoke_home}"; \
	trap - EXIT; \
	printf "\nSUCCESS: golden disk runtime boot smoke passed\n"; \
	printf "  runId=%s\n" "$${runtime_smoke_run_id}"; \
	printf "  vmHome=%s\n" "$${runtime_smoke_home}"

internal/vm/nginx/artifact:
	@test -x "$(VM_NGINX_SOURCE_BIN)" || { \
		printf "missing nginx source binary: %s\n" "$(VM_NGINX_SOURCE_BIN)" >&2; \
		printf "Install nginx on the build machine, set VM_NGINX_SOURCE_BIN, or run with VM_NGINX_BIN=/path/to/nginx.\n" >&2; \
		exit 1; \
	}
	@mkdir -p "$(dir $(VM_NGINX_ARTIFACT_BIN))"
	install -m 0755 "$(VM_NGINX_SOURCE_BIN)" "$(VM_NGINX_ARTIFACT_BIN)"
	@"$(VM_NGINX_ARTIFACT_BIN)" -v
	@printf "nginx release artifact is ready: %s\n" "$(VM_NGINX_ARTIFACT_BIN)"

internal/vm/nginx/bundle: $(if $(VM_NGINX_BIN),,internal/vm/nginx/artifact)
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" nginx-bundle \
		--bundle-dir "$(VM_PKG_BUILD_DIR)/nginx-bundle" \
		--binary "$(VM_NGINX_BIN)" \
		--release-file "$(VM_RELEASE_FILE)"

internal/vm/docker/images:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" docker-images \
		--bundle-path "$(call VM_TOML_VALUE,guest.docker_images.bundle_path)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)"

internal/vm/require-release-branch:
	$(VM_BUILD_RUNNER) require-branch --branch "$(VM_RELEASE_BRANCH)"

internal/vm/app: pwa/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-app \
		--release-file "$(VM_RELEASE_FILE)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)"

internal/vm/pkg: internal/vm/golden-rootfs pwa/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-pkg \
		--release-file "$(VM_RELEASE_FILE)" \
		--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
		--golden-runtime-dir "$(VM_GOLDEN_RUNTIME_DIR)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)" \
		--nginx-binary "$(VM_NGINX_BIN)"

internal/vm/pkg/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/pkg/dev:
	$(MAKE) internal/vm/pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/pkg/dev/compile: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/pkg/dev/compile:
	$(MAKE) internal/vm/pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/pkg/dev/runtime-smoke:
	$(MAKE) internal/vm/golden-rootfs/runtime-smoke VM_RELEASE_FILE="$(VM_DEV_RELEASE_FILE)"

internal/vm/pkg/dev/verify:
	$(MAKE) internal/vm/pkg/dev/compile
	$(MAKE) internal/vm/pkg/dev/runtime-smoke

internal/vm/pkg/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/pkg/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/pkg/release/verify:
	$(MAKE) internal/vm/pkg/release
	$(MAKE) internal/vm/golden-rootfs/runtime-smoke VM_RELEASE_FILE="$(VM_STABLE_RELEASE_FILE)"

internal/vm/dmg: internal/vm/golden-rootfs pwa/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-dmg \
		--release-file "$(VM_RELEASE_FILE)" \
		--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
		--golden-runtime-dir "$(VM_GOLDEN_RUNTIME_DIR)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)" \
		--nginx-binary "$(VM_NGINX_BIN)"

internal/vm/dmg/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/dmg/dev:
	$(MAKE) internal/vm/dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/dmg/dev/compile: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/dmg/dev/compile:
	$(MAKE) internal/vm/dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/dmg/dev/runtime-smoke:
	$(MAKE) internal/vm/golden-rootfs/runtime-smoke VM_RELEASE_FILE="$(VM_DEV_RELEASE_FILE)"

internal/vm/dmg/dev/verify:
	$(MAKE) internal/vm/dmg/dev/compile
	$(MAKE) internal/vm/dmg/dev/runtime-smoke

internal/vm/dmg/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/dmg/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/dmg/release/verify:
	$(MAKE) internal/vm/dmg/release
	$(MAKE) internal/vm/golden-rootfs/runtime-smoke VM_RELEASE_FILE="$(VM_STABLE_RELEASE_FILE)"

internal/vm/troubleshooting:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-troubleshooting-tools \
		--release-file "$(VM_RELEASE_FILE)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)"

internal/vm/troubleshooting/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/troubleshooting/dev:
	$(MAKE) internal/vm/troubleshooting VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/troubleshooting/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/troubleshooting/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/troubleshooting VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update: pwa/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-update-bundle \
		--release-file "$(VM_RELEASE_FILE)" \
		--bundle-kind "$(VM_UPDATE_BUNDLE_KIND)" \
		--requires-two-phase-update "$(VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)" \
		--nginx-binary "$(VM_NGINX_BIN)" \
		--target-platform "$(VM_UPDATE_TARGET_PLATFORM)" \
		--rootfs-base "$(VM_UPDATE_ROOTFS_BASE)"

internal/vm/update/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/update/dev:
	$(MAKE) internal/vm/update VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/update/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/update VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update: VM_UPDATE_ROOTFS_BASE = $(VM_PKG_ROOTFS_CACHE)
internal/vm/image-update: VM_UPDATE_BUNDLE_KIND := vm-image-update
internal/vm/image-update: VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE := true
internal/vm/image-update:
	$(MAKE) internal/vm/golden-rootfs VM_RELEASE_FILE="$(VM_RELEASE_FILE)"
	$(MAKE) internal/vm/update \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_ROOTFS_BASE="$(VM_UPDATE_ROOTFS_BASE)" \
		VM_UPDATE_BUNDLE_KIND="$(VM_UPDATE_BUNDLE_KIND)" \
		VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE="$(VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE)"

internal/vm/image-update/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/image-update/dev:
	$(MAKE) internal/vm/image-update VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/image-update/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/image-update VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/update/verify:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-update-bundle-verify \
		--release-file "$(VM_RELEASE_FILE)" \
		--bundle-kind "$(VM_UPDATE_BUNDLE_KIND)"

internal/vm/update/verify/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/update/verify/dev:
	$(MAKE) internal/vm/update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update/verify/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/update/verify/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/verify: VM_UPDATE_BUNDLE_KIND := vm-image-update
internal/vm/image-update/verify: internal/vm/update/verify

internal/vm/image-update/verify/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/image-update/verify/dev:
	$(MAKE) internal/vm/image-update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/verify/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/image-update/verify/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/image-update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/pkg/clean:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-package-clean \
		--release-file "$(VM_RELEASE_FILE)"

internal/vm/pkg/install:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-package-install \
		--release-file "$(VM_RELEASE_FILE)" \
		--install-settings "$(VM_INSTALL_SETTINGS)"

internal/vm/pkg/uninstall/dev:
	sudo "$(VM_MACOS_RUNTIME_DIR)/Support/Packaging/uninstall-dev.sh" $(VM_UNINSTALL_ARGS)

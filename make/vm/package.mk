.PHONY: internal/vm/nginx/artifact internal/vm/nginx/bundle internal/vm/docker/images
.PHONY: internal/vm/require-release-branch
.PHONY: internal/vm/distribution/review internal/vm/pkg internal/vm/pkg/environment-preflight internal/vm/pkg/dev internal/vm/pkg/dev/compile internal/vm/pkg/dev/review internal/vm/pkg/dev/runtime-smoke internal/vm/pkg/dev/verify internal/vm/pkg/release internal/vm/pkg/release/review internal/vm/pkg/release/verify
.PHONY: internal/vm/troubleshooting internal/vm/troubleshooting/verify internal/vm/troubleshooting/dev internal/vm/troubleshooting/dev/verify internal/vm/troubleshooting/release internal/vm/troubleshooting/release/verify
.PHONY: internal/vm/app internal/vm/dmg internal/vm/dmg/artifact-verify internal/vm/dmg/environment-preflight internal/vm/dmg/dev internal/vm/dmg/dev/cached internal/vm/dmg/dev/artifact-verify internal/vm/dmg/dev/compile internal/vm/dmg/dev/review internal/vm/dmg/dev/runtime-smoke internal/vm/dmg/dev/verify internal/vm/dmg/release internal/vm/dmg/release/artifact-verify internal/vm/dmg/release/compile internal/vm/dmg/release/review internal/vm/dmg/release/runtime-smoke
.PHONY: internal/vm/pkg/clean internal/vm/pkg/install internal/vm/pkg/uninstall/dev
.PHONY: internal/vm/update internal/vm/update/dev internal/vm/update/release internal/vm/update/smoke internal/vm/update/smoke/dev internal/vm/update/smoke/release internal/vm/update/apply-smoke internal/vm/update/apply-smoke/dev internal/vm/update/apply-smoke/release
.PHONY: internal/vm/image-update internal/vm/image-update/dev
.PHONY: internal/vm/image-update/release
.PHONY: internal/vm/update/verify internal/vm/update/verify/dev
.PHONY: internal/vm/update/verify/release
.PHONY: internal/vm/image-update/verify internal/vm/image-update/verify/dev
.PHONY: internal/vm/image-update/verify/release
.PHONY: internal/vm/image-update/smoke internal/vm/image-update/smoke/dev internal/vm/image-update/smoke/release internal/vm/image-update/apply-smoke internal/vm/image-update/apply-smoke/dev internal/vm/image-update/apply-smoke/release
.PHONY: internal/vm/airgap-rootfs internal/vm/golden-rootfs internal/vm/golden-rootfs/compile internal/vm/golden-rootfs/negative internal/vm/golden-rootfs/require internal/vm/golden-rootfs/runtime-smoke

# Public update bundle knobs.
VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE ?= false
VM_UPDATE_BUNDLE_KIND ?= product-update
VM_UPDATE_TARGET_PLATFORM ?=
VM_UPDATE_ROOTFS_BASE ?=
VM_UPDATE_STATIC_SMOKE_HINT ?= make dist/update/dev/smoke

# Public package artifact knobs.
VM_NGINX_SOURCE_BIN ?= /opt/homebrew/opt/nginx/bin/nginx
VM_NGINX_BIN ?=

# Internal package artifact paths.
VM_NGINX_ARTIFACT_BIN := .artifacts/nginx/macos/bin/nginx

# Internal package rootfs cache paths.
VM_PKG_BUILD_DIR ?= $(call VM_TOML_VALUE,workspace.build_dir)
VM_PKG_ROOTFS_CACHE ?= $(VM_PKG_BUILD_DIR)/rootfs-base.raw.gz
VM_PKG_ROOTFS_CONTRACT_STAMP ?= $(VM_PKG_BUILD_DIR)/rootfs-base.contract
VM_PKG_APT_ROOTFS_CACHE ?= $(VM_PKG_BUILD_DIR)/apt-prepared-rootfs.raw.gz
VM_PKG_APT_ROOTFS_CONTRACT_STAMP ?= $(VM_PKG_BUILD_DIR)/apt-prepared-rootfs.contract
VM_PKG_APT_ROOTFS_SHA256 ?= $(VM_PKG_BUILD_DIR)/apt-prepared-rootfs.raw.gz.sha256
VM_PKG_APT_ROOTFS_CONTRACT_VERSION := 1
VM_PKG_APT_ROOTFS_CONTRACT_INPUTS := \
	$(VM_BUILD_CONFIG) \
	$(VM_MACOS_RUNTIME_DIR)/Support/Guest/rootfs-apt-cache-contract.txt \
	$(VM_MACOS_RUNTIME_DIR)/Support/Guest/rootfs-apt-packages.txt
VM_PKG_APT_ROOTFS_CONTRACT_FINGERPRINT = $(shell { \
	printf '%s\n' "vitalserver-apt-rootfs-contract-v$(VM_PKG_APT_ROOTFS_CONTRACT_VERSION)"; \
	printf '%s\n' "rootfs-size=$(VM_ROOTFS_SIZE)"; \
	cksum $(VM_PKG_APT_ROOTFS_CONTRACT_INPUTS); \
} | cksum | awk '{print $$1 "-" $$2}')
VM_PKG_ROOTFS_CONTRACT_VERSION := 6
VM_PKG_ROOTFS_CONTRACT_INPUT_ROOTS := \
	$(VM_BUILD_CONFIG) \
	make/vm \
	$(VM_MACOS_RUNTIME_DIR)/Support/Guest \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/adapters/guest_image \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/adapters/guest_services \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/application/guest_service_plans.py \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/application/usecases/guest_image.py \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/application/usecases/guest_services.py \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/config/guest_deploy.py \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/config/guest_image.py \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/config/docker_images.py \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/core/guest_image.py \
	packages/vitalserver-devtools/src/tirosh_vitalserver/devtools/core/guest_services.py \
	packages/vitalserver-guest-tools \
	apps/vitalserver/docker \
	apps/vitalserver/runtime \
	apps/vitalserver-recorder-ingress \
	apps/vitalserver-recorder-recovery \
	packages/vitalserver-core \
	packages/vitalserver-vitalfile \
	apps/vitaldb-observer \
	apps/vitalserver-redis-relay \
	apps/vitalserver-lab \
	vendor/vitalserver/vitalserver-old \
	docs/api \
	docs/runtime/runtime-control.openapi.json
VM_PKG_ROOTFS_CONTRACT_FINGERPRINT = $(shell { \
	printf '%s\n' "vitalserver-rootfs-contract-v$(VM_PKG_ROOTFS_CONTRACT_VERSION)"; \
	printf '%s\n' "build-config=$(abspath $(VM_BUILD_CONFIG))"; \
	printf '%s\n' "rootfs-size=$(VM_ROOTFS_SIZE)"; \
	find $(VM_PKG_ROOTFS_CONTRACT_INPUT_ROOTS) \
		\( -path packages/vitalserver-guest-tools/dist -o -name .DS_Store -o -name __pycache__ -o -name .pytest_cache -o -name .mypy_cache \) -prune \
		-o -type f -print | LC_ALL=C sort | xargs -n 64 cksum; \
} | cksum | awk '{print $$1 "-" $$2}')

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

internal/vm/airgap-rootfs: internal/vm/release-contract
	@$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		stop >/dev/null 2>&1 || true
	# `stop` only requests shutdown. Wait for the Host-owned lifecycle and
	# launcher process proofs before touching mutable runtime files.
	@set -e; \
	if ! $(VM_BUILD_RUNNER) macos-runtime-wait-stopped \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_AIRGAP_CLEANUP_WAIT_TIMEOUT)" >/dev/null 2>&1; then \
		$(VM_BUILD_RUNNER) macos-runtime-force-stop \
			--vm-home "$(VM_HOME)" \
			--timeout "$(VM_AIRGAP_FORCE_STOP_TIMEOUT)"; \
	fi
	$(VM_BUILD_RUNNER) macos-runtime-require-no-running \
		--vm-home "$(VM_HOME)"
	$(MAKE) internal/vm/download \
		VM_HOME="$(VM_HOME)" \
		VM_RECREATE_ROOTFS="$(VM_RECREATE_ROOTFS)"
	$(MAKE) internal/vm/stage \
		VM_HOME="$(VM_HOME)" \
		VM_ROOTFS_RUN_ID="$(VM_ROOTFS_RUN_ID)" \
		VM_GUEST_DEPLOY_SOURCE="$(VM_GUEST_DEPLOY_SOURCE)" \
		VM_GUEST_ROOTFS_ARTIFACT="$(VM_GUEST_ROOTFS_ARTIFACT)" \
		VM_RUNTIME_BOOT_SMOKE_RUN_ID="$(VM_RUNTIME_BOOT_SMOKE_RUN_ID)"
	@$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		stop >/dev/null 2>&1 || true
	@set -e; \
	if ! $(VM_BUILD_RUNNER) macos-runtime-wait-stopped \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_AIRGAP_CLEANUP_WAIT_TIMEOUT)" >/dev/null 2>&1; then \
		$(VM_BUILD_RUNNER) macos-runtime-force-stop \
			--vm-home "$(VM_HOME)" \
			--timeout "$(VM_AIRGAP_FORCE_STOP_TIMEOUT)"; \
	fi
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
	@set -e; \
	apt_source="network"; \
	if [ -n "$(VM_ROOTFS_SEED)" ]; then \
		apt_source="verified-cache"; \
	fi; \
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-preflight-golden-rootfs \
		--vm-home "$(VM_HOME)" \
		--expected-run-id "$(VM_ROOTFS_RUN_ID)" \
		--apt-source "$${apt_source}"
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

internal/vm/golden-rootfs: internal/vm/release-contract
	@set -e; \
	for input in $(VM_PKG_ROOTFS_CONTRACT_INPUT_ROOTS); do \
		test -e "$$input" || { \
			printf "missing golden rootfs contract input: %s\n" "$$input" >&2; \
			exit 1; \
		}; \
	done; \
	rootfs_contract_expected="$(VM_PKG_ROOTFS_CONTRACT_FINGERPRINT)"; \
	rootfs_contract_actual=""; \
	cache_reusable="false"; \
	if [ -s "$(VM_PKG_ROOTFS_CONTRACT_STAMP)" ]; then \
		rootfs_contract_actual="$$(cat "$(VM_PKG_ROOTFS_CONTRACT_STAMP)")"; \
	fi; \
	if [ "$(VM_RECREATE_ROOTFS)" = "false" ] \
		&& [ -s "$(VM_PKG_ROOTFS_CACHE)" ] \
		&& [ -s "$(VM_GOLDEN_RUNTIME_DIR)/Image" ] \
		&& [ -s "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" ] \
		&& [ "$${rootfs_contract_actual}" = "$${rootfs_contract_expected}" ]; then \
		if $(VM_BUILD_RUNNER) rootfs-artifact-verify-deploy \
			--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
			--deploy-dir "$(VM_GOLDEN_HOME)/data/deploy"; then \
			cache_reusable="true"; \
		else \
			printf "Golden rootfs cache receipt does not match staged Guest material; rebuilding: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
		fi; \
	fi; \
	if [ "$${cache_reusable}" = "true" ]; then \
		printf "Reusing golden rootfs cache: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
	else \
		rootfs_run_id="$$(uuidgen | tr '[:upper:]' '[:lower:]')"; \
		apt_rootfs_contract_expected="$(VM_PKG_APT_ROOTFS_CONTRACT_FINGERPRINT)"; \
		apt_rootfs_contract_actual=""; \
		apt_rootfs_seed=""; \
		if [ -s "$(VM_PKG_APT_ROOTFS_CONTRACT_STAMP)" ]; then \
			apt_rootfs_contract_actual="$$(cat "$(VM_PKG_APT_ROOTFS_CONTRACT_STAMP)")"; \
		fi; \
		if [ -s "$(VM_PKG_APT_ROOTFS_CACHE)" ] \
			&& [ -s "$(VM_PKG_APT_ROOTFS_SHA256)" ] \
			&& [ "$${apt_rootfs_contract_actual}" = "$${apt_rootfs_contract_expected}" ] \
			&& (cd "$(dir $(VM_PKG_APT_ROOTFS_CACHE))" && shasum -a 256 -c "$(notdir $(VM_PKG_APT_ROOTFS_SHA256))"); then \
			apt_rootfs_seed="$(abspath $(VM_PKG_APT_ROOTFS_CACHE))"; \
			printf "Reusing verified APT-prepared rootfs cache: %s\n" "$${apt_rootfs_seed}"; \
		elif [ -e "$(VM_PKG_APT_ROOTFS_CACHE)" ] || [ -e "$(VM_PKG_APT_ROOTFS_CONTRACT_STAMP)" ] || [ -e "$(VM_PKG_APT_ROOTFS_SHA256)" ]; then \
			printf "APT-prepared rootfs cache is incomplete, stale, or invalid; compiling from Ubuntu base\n"; \
		else \
			printf "APT-prepared rootfs cache is unavailable; compiling from Ubuntu base\n"; \
		fi; \
		if [ "$(VM_RECREATE_ROOTFS)" != "false" ]; then \
			printf "Recreating golden rootfs cache: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
		elif [ -s "$(VM_PKG_ROOTFS_CACHE)" ]; then \
			if [ -z "$${rootfs_contract_actual}" ]; then \
				printf "Golden rootfs cache missing contract stamp; rebuilding: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
			else \
				printf "Golden rootfs cache contract changed; rebuilding: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
			fi; \
		else \
			printf "Golden rootfs cache is unavailable; compiling from a fresh base: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
		fi; \
		$(MAKE) internal/vm/docker/images; \
		$(MAKE) internal/vm/airgap-rootfs \
			VM_HOME="$(abspath $(VM_GOLDEN_HOME))" \
			VM_RECREATE_ROOTFS=true \
			VM_ROOTFS_SEED="$${apt_rootfs_seed}" \
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
		if [ -z "$${apt_rootfs_seed}" ]; then \
			apt_rootfs_cache_tmp="$(abspath $(VM_PKG_APT_ROOTFS_CACHE)).tmp"; \
			cp "$(VM_PKG_ROOTFS_CACHE)" "$${apt_rootfs_cache_tmp}"; \
			mv "$${apt_rootfs_cache_tmp}" "$(VM_PKG_APT_ROOTFS_CACHE)"; \
			(cd "$(dir $(VM_PKG_APT_ROOTFS_CACHE))" && shasum -a 256 "$(notdir $(VM_PKG_APT_ROOTFS_CACHE))" >"$(notdir $(VM_PKG_APT_ROOTFS_SHA256)).tmp"); \
			mv "$(VM_PKG_APT_ROOTFS_SHA256).tmp" "$(VM_PKG_APT_ROOTFS_SHA256)"; \
			printf "%s\n" "$${apt_rootfs_contract_expected}" >"$(VM_PKG_APT_ROOTFS_CONTRACT_STAMP).tmp"; \
			mv "$(VM_PKG_APT_ROOTFS_CONTRACT_STAMP).tmp" "$(VM_PKG_APT_ROOTFS_CONTRACT_STAMP)"; \
			printf "Published verified APT-prepared rootfs cache: %s\n" "$(VM_PKG_APT_ROOTFS_CACHE)"; \
		fi; \
		mkdir -p "$(dir $(VM_PKG_ROOTFS_CONTRACT_STAMP))"; \
		printf "%s\n" "$${rootfs_contract_expected}" >"$(VM_PKG_ROOTFS_CONTRACT_STAMP)"; \
	fi

internal/vm/golden-rootfs/compile:
	$(MAKE) internal/vm/golden-rootfs VM_RECREATE_ROOTFS=true

# Diagnostic consumers must prove an already compiled cache. They must not
# silently take ownership of Docker export or rootfs compilation.
internal/vm/golden-rootfs/require: internal/vm/release-contract
	@set -e; \
	for input in $(VM_PKG_ROOTFS_CONTRACT_INPUT_ROOTS); do \
		test -e "$$input" || { \
			printf "missing golden rootfs contract input: %s\\n" "$$input" >&2; \
			exit 1; \
		}; \
	done; \
	test -s "$(VM_PKG_ROOTFS_CACHE)" || { \
		printf "error: golden rootfs cache is unavailable; run make dist/dmg/dev/compile first: %s\\n" "$(VM_PKG_ROOTFS_CACHE)" >&2; \
		exit 1; \
	}; \
	test -s "$(VM_GOLDEN_RUNTIME_DIR)/Image" || { \
		printf "error: golden rootfs runtime kernel is unavailable; run make dist/dmg/dev/compile first: %s\\n" "$(VM_GOLDEN_RUNTIME_DIR)/Image" >&2; \
		exit 1; \
	}; \
	test -s "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" || { \
		printf "error: golden rootfs runtime initrd is unavailable; run make dist/dmg/dev/compile first: %s\\n" "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" >&2; \
		exit 1; \
	}; \
	test -d "$(VM_GOLDEN_HOME)/data/deploy" || { \
		printf "error: compiled Guest deploy material is unavailable; run make dist/dmg/dev/compile first: %s\\n" "$(VM_GOLDEN_HOME)/data/deploy" >&2; \
		exit 1; \
	}; \
	test -s "$(VM_PKG_ROOTFS_CONTRACT_STAMP)" || { \
		printf "error: golden rootfs contract stamp is unavailable; run make dist/dmg/dev/compile first: %s\\n" "$(VM_PKG_ROOTFS_CONTRACT_STAMP)" >&2; \
		exit 1; \
	}; \
	rootfs_contract_actual="$$(cat "$(VM_PKG_ROOTFS_CONTRACT_STAMP)")"; \
	rootfs_contract_expected="$(VM_PKG_ROOTFS_CONTRACT_FINGERPRINT)"; \
	if [ "$${rootfs_contract_actual}" != "$${rootfs_contract_expected}" ]; then \
		printf "error: golden rootfs cache contract is stale; run make dist/dmg/dev/compile first: actual=%s expected=%s\\n" "$${rootfs_contract_actual}" "$${rootfs_contract_expected}" >&2; \
		exit 1; \
	fi; \
	$(VM_BUILD_RUNNER) rootfs-artifact-verify-deploy \
		--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
		--deploy-dir "$(VM_GOLDEN_HOME)/data/deploy"; \
	printf "Verified existing golden rootfs cache: %s\\n" "$(VM_PKG_ROOTFS_CACHE)"

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

internal/vm/golden-rootfs/runtime-smoke: internal/vm/golden-rootfs/require
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
		VM_GUEST_DEPLOY_SOURCE="$(abspath $(VM_GOLDEN_HOME)/data/deploy)" \
		VM_GUEST_ROOTFS_ARTIFACT="$(abspath $(VM_PKG_ROOTFS_CACHE))" \
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

internal/vm/docker/images: internal/vm/release-contract
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

internal/vm/pkg/environment-preflight:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-package-environment-preflight \
		--release-file "$(VM_RELEASE_FILE)" \
		--output-kind pkg

internal/vm/pkg: internal/vm/release-contract internal/vm/pkg/environment-preflight pwa/build internal/vm/golden-rootfs
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-pkg \
		--release-file "$(VM_RELEASE_FILE)" \
		--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
		--golden-runtime-dir "$(VM_GOLDEN_RUNTIME_DIR)" \
		--guest-deploy-source "$(abspath $(VM_GOLDEN_HOME)/data/deploy)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)" \
		--nginx-binary "$(VM_NGINX_BIN)"

internal/vm/pkg/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/pkg/dev:
	$(MAKE) internal/vm/pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/pkg/dev/compile: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/pkg/dev/compile:
	$(MAKE) internal/vm/pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/pkg/dev/runtime-smoke:
	$(MAKE) internal/vm/golden-rootfs/runtime-smoke VM_RELEASE_FILE="$(VM_DEV_RELEASE_FILE)"

internal/vm/distribution/review: repo/verify-submodule product/scenarios/check pwa/check pwa/test
	CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift test \
		--package-path "$(VM_SWIFT_PACKAGE_DIR)"
	$(DEVTOOLS_RUNNER) python-tool --uv "$(UV)" -- pytest \
		packages/vitalserver-devtools/tests/unit/test_delivery_makefile_contract.py \
		packages/vitalserver-devtools/tests/unit/test_docker_image_bundle.py \
		packages/vitalserver-devtools/tests/unit/test_guest_deploy_bundle.py \
		packages/vitalserver-devtools/tests/unit/test_macos_release_plans.py \
		packages/vitalserver-devtools/tests/unit/test_packaging_templates.py \
		packages/vitalserver-devtools/tests/unit/test_release_sync_contract.py \
		packages/vitalserver-devtools/tests/unit/test_upstream_vitalserver_contract.py
	$(UV) run --project packages/vitalserver-guest-tools pytest \
		packages/vitalserver-guest-tools/tests/test_redis_repair.py

internal/vm/pkg/dev/review:
	$(MAKE) internal/vm/distribution/review

internal/vm/pkg/dev/verify:
	$(MAKE) internal/vm/pkg/dev/review
	$(MAKE) internal/vm/pkg/dev/compile
	$(MAKE) internal/vm/pkg/dev/runtime-smoke

internal/vm/pkg/release/review:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/distribution/review

internal/vm/pkg/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/pkg/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/pkg/release/verify:
	$(MAKE) internal/vm/pkg/release/review
	$(MAKE) internal/vm/pkg/release
	$(MAKE) internal/vm/golden-rootfs/runtime-smoke VM_RELEASE_FILE="$(VM_STABLE_RELEASE_FILE)"

internal/vm/dmg/environment-preflight:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-package-environment-preflight \
		--release-file "$(VM_RELEASE_FILE)" \
		--output-kind dmg

internal/vm/dmg: internal/vm/release-contract internal/vm/dmg/environment-preflight pwa/build internal/vm/golden-rootfs
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-dmg \
		--release-file "$(VM_RELEASE_FILE)" \
		--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
		--golden-runtime-dir "$(VM_GOLDEN_RUNTIME_DIR)" \
		--guest-deploy-source "$(abspath $(VM_GOLDEN_HOME)/data/deploy)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)" \
		--nginx-binary "$(VM_NGINX_BIN)"

internal/vm/dmg/artifact-verify:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-dmg-verify \
		--release-file "$(VM_RELEASE_FILE)"

internal/vm/dmg/dev:
	$(MAKE) internal/vm/dmg/dev/review
	$(MAKE) internal/vm/dmg/dev/compile
	$(MAKE) internal/vm/dmg/dev/artifact-verify
	$(MAKE) internal/vm/dmg/dev/runtime-smoke

internal/vm/dmg/dev/cached: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/dmg/dev/cached:
	$(MAKE) internal/vm/dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/dmg/dev/review:
	$(MAKE) internal/vm/distribution/review

internal/vm/dmg/dev/compile: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/dmg/dev/compile:
	$(MAKE) internal/vm/dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/dmg/dev/artifact-verify: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/dmg/dev/artifact-verify:
	$(MAKE) internal/vm/dmg/artifact-verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/dmg/dev/runtime-smoke:
	$(MAKE) internal/vm/golden-rootfs/runtime-smoke VM_RELEASE_FILE="$(VM_DEV_RELEASE_FILE)"

internal/vm/dmg/dev/verify:
	$(MAKE) internal/vm/dmg/dev/artifact-verify
	$(MAKE) internal/vm/dmg/dev/runtime-smoke

internal/vm/dmg/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/dmg/release:
	$(MAKE) internal/vm/dmg/release/review
	$(MAKE) internal/vm/dmg/release/compile
	$(MAKE) internal/vm/dmg/release/artifact-verify
	$(MAKE) internal/vm/dmg/release/runtime-smoke

internal/vm/dmg/release/artifact-verify: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/dmg/release/artifact-verify:
	$(MAKE) internal/vm/dmg/artifact-verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/dmg/release/compile: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/dmg/release/compile:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/dmg/release/review:
	$(MAKE) internal/vm/pkg/release/review

internal/vm/dmg/release/runtime-smoke:
	$(MAKE) internal/vm/golden-rootfs/runtime-smoke VM_RELEASE_FILE="$(VM_STABLE_RELEASE_FILE)"

internal/vm/troubleshooting:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-troubleshooting-tools \
		--release-file "$(VM_RELEASE_FILE)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)"

internal/vm/troubleshooting/verify:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-troubleshooting-tools-verify \
		--release-file "$(VM_RELEASE_FILE)"

internal/vm/troubleshooting/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/troubleshooting/dev:
	$(MAKE) internal/vm/troubleshooting VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/troubleshooting/dev/verify: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/troubleshooting/dev/verify:
	$(MAKE) internal/vm/troubleshooting/dev VM_RELEASE_FILE="$(VM_RELEASE_FILE)"
	$(MAKE) internal/vm/troubleshooting/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/troubleshooting/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/troubleshooting/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/troubleshooting VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/troubleshooting/release/verify: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/troubleshooting/release/verify:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/troubleshooting/release VM_RELEASE_FILE="$(VM_RELEASE_FILE)"
	$(MAKE) internal/vm/troubleshooting/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update: internal/vm/release-contract pwa/build
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

internal/vm/update/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/update/dev:
	$(MAKE) internal/vm/update VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
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

internal/vm/image-update/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/image-update/dev:
	$(MAKE) internal/vm/image-update VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/image-update/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/image-update VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_ROOTFS=true

internal/vm/update/verify:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-update-bundle-verify \
		--release-file "$(VM_RELEASE_FILE)" \
		--bundle-kind "$(VM_UPDATE_BUNDLE_KIND)"

internal/vm/update/verify/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/update/verify/dev:
	$(MAKE) internal/vm/update/verify \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_BUNDLE_KIND="$(VM_UPDATE_BUNDLE_KIND)"

internal/vm/update/verify/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/update/verify/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/update/verify \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_BUNDLE_KIND="$(VM_UPDATE_BUNDLE_KIND)"

internal/vm/update/smoke: internal/vm/update/verify

internal/vm/update/smoke/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/update/smoke/dev:
	$(MAKE) internal/vm/update/verify/dev VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update/smoke/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/update/smoke/release:
	$(MAKE) internal/vm/update/verify/release VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update/apply-smoke:
	@if [ "$(VM_UPDATE_APPLY_SMOKE_CONFIRM)" != "YES" ]; then \
		printf "update apply smoke is destructive and requires VM_UPDATE_APPLY_SMOKE_CONFIRM=YES\n"; \
		printf "build and static smoke first: $(VM_UPDATE_STATIC_SMOKE_HINT)\n"; \
		exit 2; \
	fi
	$(MAKE) internal/vm/update/verify \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_BUNDLE_KIND="$(VM_UPDATE_BUNDLE_KIND)"
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-update-bundle-apply-smoke \
		--release-file "$(VM_RELEASE_FILE)" \
		--bundle-kind "$(VM_UPDATE_BUNDLE_KIND)"

internal/vm/update/apply-smoke/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/update/apply-smoke/dev:
	$(MAKE) internal/vm/update/apply-smoke \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_STATIC_SMOKE_HINT="make dist/update/dev/smoke"

internal/vm/update/apply-smoke/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/update/apply-smoke/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/update/apply-smoke \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_STATIC_SMOKE_HINT="make dist/update/release/smoke"

internal/vm/image-update/verify: VM_UPDATE_BUNDLE_KIND := vm-image-update
internal/vm/image-update/verify: internal/vm/update/verify

internal/vm/image-update/verify/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/image-update/verify/dev:
	$(MAKE) internal/vm/image-update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/verify/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/image-update/verify/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/image-update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/smoke: VM_UPDATE_BUNDLE_KIND := vm-image-update
internal/vm/image-update/smoke: internal/vm/update/smoke

internal/vm/image-update/smoke/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/image-update/smoke/dev:
	$(MAKE) internal/vm/image-update/verify/dev VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/smoke/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/image-update/smoke/release:
	$(MAKE) internal/vm/image-update/verify/release VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/apply-smoke: VM_UPDATE_BUNDLE_KIND := vm-image-update
internal/vm/image-update/apply-smoke: internal/vm/update/apply-smoke

internal/vm/image-update/apply-smoke/dev: override VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/image-update/apply-smoke/dev:
	$(MAKE) internal/vm/image-update/apply-smoke \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_STATIC_SMOKE_HINT="make dist/image-update/dev/smoke"

internal/vm/image-update/apply-smoke/release: override VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/image-update/apply-smoke/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/image-update/apply-smoke \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_STATIC_SMOKE_HINT="make dist/image-update/release/smoke"

internal/vm/pkg/clean:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-package-clean \
		--release-file "$(VM_RELEASE_FILE)"

internal/vm/pkg/install:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-package-install \
		--release-file "$(VM_RELEASE_FILE)" \
		--install-settings "$(VM_INSTALL_SETTINGS)"

internal/vm/pkg/uninstall/dev:
	sudo "$(VM_MACOS_RUNTIME_DIR)/Support/Packaging/uninstall-dev.sh" $(VM_UNINSTALL_ARGS)

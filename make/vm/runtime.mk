.PHONY: internal/vm/up internal/vm/up-bridged internal/vm/down internal/vm/prepare internal/vm/start internal/vm/start/detached internal/vm/start/bridged internal/vm/stop internal/vm/status internal/vm/clean internal/vm/ip internal/vm/wait/ip internal/vm/wait/http internal/vm/wait/rootfs-ready internal/vm/wait/runtime-boot-smoke internal/vm/wait/stopped internal/vm/proxy/start internal/vm/health internal/vm/e2e/smoke internal/vm/coverage
.PHONY: internal/vm/version-source internal/vm/build internal/vm/sign internal/vm/sign/bridged internal/vm/bridged/preflight internal/vm/init internal/vm/download internal/vm/cloud-init internal/vm/stage internal/vm/interfaces internal/vm/network/shared internal/vm/network/bridged

# Public runtime/devtools knobs.
VM_ROOTFS_SIZE ?= 8G

# Internal orchestration: package targets pass this from the golden rootfs compile policy.
VM_RECREATE_ROOTFS ?= false

# Diagnostic/CI wait knobs.
VM_WAIT_TIMEOUT ?= 300
VM_HTTP_WAIT_TIMEOUT ?= 600
VM_ROOTFS_READY_TIMEOUT ?= 600

# Internal orchestration: generated per golden rootfs compile run.
VM_ROOTFS_RUN_ID ?=

# Diagnostic/CI fault injection knobs.
VM_ROOTFS_SMOKE_FAIL_STAGE ?=
VM_ROOTFS_SMOKE_FAIL_CLEANUP ?= false

# Diagnostic/CI runtime boot smoke knobs.
VM_RUNTIME_BOOT_SMOKE ?= false
VM_RUNTIME_BOOT_SMOKE_RUN_ID ?=

VM_RUNTIME_DIR := $(VM_HOME)/runtime

internal/vm/version-source:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-sync-release \
		--release-file "$(VM_RELEASE_FILE)"

internal/vm/build:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-build \
		--release-file "$(VM_RELEASE_FILE)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--sdkroot "$(VM_SDKROOT)"

internal/vm/sign: internal/vm/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-sign \
		--identity "$(VM_CODESIGN_IDENTITY)" \
		--entitlements "Entitlements.shared.plist"

internal/vm/bridged/preflight:
	$(VM_BUILD_RUNNER) macos-runtime-require-bridged-identity \
		--identity "$(VM_BRIDGED_CODESIGN_IDENTITY)"

internal/vm/sign/bridged: internal/vm/build internal/vm/bridged/preflight
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-sign \
		--identity "$(VM_BRIDGED_CODESIGN_IDENTITY)" \
		--entitlements "Entitlements.plist"

internal/vm/init: internal/vm/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		init

internal/vm/download:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" ubuntu \
		--runtime-dir "$(VM_RUNTIME_DIR)" \
		--rootfs-size "$(VM_ROOTFS_SIZE)" \
		--recreate-rootfs "$(VM_RECREATE_ROOTFS)"

internal/vm/cloud-init:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" cloud-init \
		--runtime-dir "$(VM_RUNTIME_DIR)"

internal/vm/prepare: internal/vm/download internal/vm/cloud-init internal/vm/stage
	@printf "VM runtime is prepared under %s\n" "$(VM_HOME)"
	@printf "Start it with: make devtools/start\n"

internal/vm/up: internal/vm/prepare internal/vm/start/detached internal/vm/wait/ip internal/vm/wait/http internal/vm/proxy/start

internal/vm/up-bridged: internal/vm/bridged/preflight internal/vm/prepare internal/vm/network/bridged internal/vm/start/bridged

internal/vm/down: internal/vm/stop

internal/vm/stage: internal/vm/init
	@set -e; \
	rootfs_run_args=""; \
	if [ -n "$(VM_ROOTFS_RUN_ID)" ]; then \
		rootfs_run_args="--rootfs-run-id $(VM_ROOTFS_RUN_ID)"; \
	fi; \
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" guest-deploy \
		--vm-home "$(VM_HOME)" \
		--runtime-dir "$(VM_MACOS_RUNTIME_DIR)" \
		--docker-bundle "$(call VM_TOML_VALUE,guest.docker_images.bundle_path)" \
		$$rootfs_run_args; \
	if [ "$(VM_RUNTIME_BOOT_SMOKE)" = "true" ]; then \
		python3 -c 'import json, sys; from pathlib import Path; path = Path(sys.argv[1]); document = json.loads(path.read_text(encoding="utf-8")); document["runtimeBootSmoke"] = {"enabled": True, "runId": sys.argv[2]}; path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")' "$(VM_HOME)/data/deploy/build-metadata/rootfs-input.json" "$(VM_RUNTIME_BOOT_SMOKE_RUN_ID)"; \
	fi

internal/vm/start: internal/vm/sign
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		start

internal/vm/start/detached: internal/vm/sign
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-start-detached \
		--vm-home "$(VM_HOME)"

internal/vm/start/bridged: internal/vm/sign/bridged
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		start

internal/vm/stop:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		stop
	$(MAKE) internal/vm/wait/stopped

internal/vm/status:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		status

internal/vm/ip:
	$(VM_BUILD_RUNNER) macos-runtime-ip --vm-home "$(VM_HOME)"

internal/vm/wait/ip:
	$(VM_BUILD_RUNNER) macos-runtime-wait-ip \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_WAIT_TIMEOUT)"

internal/vm/wait/http:
	$(VM_BUILD_RUNNER) macos-runtime-wait-http \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_HTTP_WAIT_TIMEOUT)"

internal/vm/wait/rootfs-ready:
	@set -e; \
	run_args=""; \
	if [ -n "$(VM_ROOTFS_RUN_ID)" ]; then \
		run_args="--expected-run-id $(VM_ROOTFS_RUN_ID)"; \
	fi; \
	$(VM_BUILD_RUNNER) macos-runtime-wait-rootfs-ready \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_ROOTFS_READY_TIMEOUT)" \
		$$run_args

internal/vm/wait/runtime-boot-smoke:
	@set -e; \
	run_args=""; \
	if [ -n "$(VM_RUNTIME_BOOT_SMOKE_RUN_ID)" ]; then \
		run_args="--expected-run-id $(VM_RUNTIME_BOOT_SMOKE_RUN_ID)"; \
	fi; \
	$(VM_BUILD_RUNNER) macos-runtime-wait-runtime-boot-smoke \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_HTTP_WAIT_TIMEOUT)" \
		$$run_args

internal/vm/wait/stopped:
	$(VM_BUILD_RUNNER) macos-runtime-wait-stopped \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_WAIT_TIMEOUT)"

internal/vm/proxy/start:
	@upstream="$(VM_PROXY_UPSTREAM)"; \
	if [ -z "$$upstream" ]; then \
		if ! upstream="$$( \
			$(VM_BUILD_RUNNER) macos-runtime-guest-address-proxy-upstream \
				--vm-home "$(VM_HOME)" \
				--runtime-control-api-base-url "$${VITALSERVER_RUNTIME_CONTROL_API_BASE_URL:-http://127.0.0.1:18321}" \
				--runtime-control-api-token "$${VITALSERVER_RUNTIME_CONTROL_API_TOKEN:?VITALSERVER_RUNTIME_CONTROL_API_TOKEN is required}" \
				--runtime-control-api-token-header "$${VITALSERVER_RUNTIME_CONTROL_API_TOKEN_HEADER:-X-Runtime-Control-Token}" \
				--runtime-control-api-timeout "$${VITALSERVER_RUNTIME_CONTROL_API_TIMEOUT_SECONDS:-2}" \
		)"; then \
			printf "Runtime Control Guest address owner is unavailable; cannot derive proxy upstream.\n" >&2; \
			exit 1; \
		fi; \
	fi; \
		PROXY_UPSTREAM="$$upstream" $(MAKE) proxy/start

internal/vm/health:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-health \
		--vm-home "$(VM_HOME)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)"

internal/vm/e2e/smoke:
	CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift test --package-path "$(VM_SWIFT_PACKAGE_DIR)" --filter RuntimeControlAPITests/testRuntimeControlE2ESmokeServesCoreReadEndpointsOverHTTP

internal/vm/coverage:
	CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift test --enable-code-coverage --package-path "$(VM_SWIFT_PACKAGE_DIR)"
	$(VM_LLVM_COV) report "$(VM_SWIFT_TEST_BINARY)" \
		-instr-profile "$(VM_SWIFT_COVERAGE_PROFILE)" \
		-ignore-filename-regex='$(VM_SWIFT_COVERAGE_IGNORE)' | tee "$(VM_SWIFT_COVERAGE_REPORT)"
	@awk -v min="$(VM_SWIFT_COVERAGE_MIN)" '/^TOTAL/ { pct=$$10; gsub("%", "", pct); if (pct + 0 < min + 0) { printf "Swift line coverage %.2f%% is below %.2f%%\n", pct, min; exit 1 } printf "Swift line coverage %.2f%% >= %.2f%%\n", pct, min }' "$(VM_SWIFT_COVERAGE_REPORT)"

internal/vm/interfaces: internal/vm/sign/bridged
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		interfaces

internal/vm/network/shared: internal/vm/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		network shared

internal/vm/network/bridged: internal/vm/sign/bridged
	@test -n "$(VM_BRIDGED_INTERFACE)" || { printf "Set VM_BRIDGED_INTERFACE. Run: make runtime/interfaces\n" >&2; exit 1; }
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		network bridged "$(VM_BRIDGED_INTERFACE)"

internal/vm/clean: internal/vm/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		clean

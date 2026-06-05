.PHONY: internal/vm/up internal/vm/up-bridged internal/vm/down internal/vm/prepare internal/vm/start internal/vm/start/detached internal/vm/start/bridged internal/vm/stop internal/vm/status internal/vm/clean internal/vm/ip internal/vm/wait/ip internal/vm/wait/http internal/vm/wait/rootfs-ready internal/vm/wait/stopped internal/vm/proxy/start internal/vm/health internal/vm/e2e/smoke internal/vm/coverage
.PHONY: internal/vm/version-source internal/vm/build internal/vm/sign internal/vm/sign/bridged internal/vm/bridged/preflight internal/vm/init internal/vm/download internal/vm/cloud-init internal/vm/stage internal/vm/interfaces internal/vm/network/shared internal/vm/network/bridged

VM_ROOTFS_SIZE ?= 4G
VM_RECREATE_ROOTFS ?= false
VM_WAIT_TIMEOUT ?= 300
VM_HTTP_WAIT_TIMEOUT ?= 600

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
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" guest-deploy \
		--vm-home "$(VM_HOME)" \
		--runtime-dir "$(VM_MACOS_RUNTIME_DIR)"

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
	$(VM_BUILD_RUNNER) macos-runtime-wait-rootfs-ready \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_HTTP_WAIT_TIMEOUT)"

internal/vm/wait/stopped:
	$(VM_BUILD_RUNNER) macos-runtime-wait-stopped \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_WAIT_TIMEOUT)"

internal/vm/proxy/start:
	@upstream="$(VM_PROXY_UPSTREAM)"; \
	if [ -z "$$upstream" ]; then \
		if [ ! -s "$(VM_HOME)/data/run/vm-ip" ]; then \
			printf "Set VM_PROXY_UPSTREAM or run make devtools/wait/ip first.\n" >&2; \
			printf "  VM_PROXY_UPSTREAM=192.168.64.3:80 make runtime/proxy/start\n" >&2; \
			exit 1; \
		fi; \
		upstream="$$(cat "$(VM_HOME)/data/run/vm-ip"):80"; \
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

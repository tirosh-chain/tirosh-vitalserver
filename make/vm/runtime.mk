.PHONY: vm-up vm-up-bridged vm-down vm-prepare vm-start vm-start-detached vm-start-bridged vm-stop vm-status vm-clean vm-ip vm-wait-ip vm-wait-http vm-wait-rootfs-ready vm-proxy-start vm-health vm-coverage
.PHONY: vm-version-source vm-build vm-sign vm-sign-bridged vm-bridged-preflight vm-init vm-download vm-cloud-init vm-stage vm-interfaces vm-network-shared vm-network-bridged

VM_ROOTFS_SIZE ?= 4G
VM_RECREATE_ROOTFS ?= false
VM_WAIT_TIMEOUT ?= 300
VM_HTTP_WAIT_TIMEOUT ?= 600

VM_RUNTIME_DIR := $(VM_HOME)/runtime

vm-version-source:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-sync-release \
		--release-file "$(VM_RELEASE_FILE)"

vm-build:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-build \
		--release-file "$(VM_RELEASE_FILE)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--sdkroot "$(VM_SDKROOT)"

vm-sign: vm-build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-sign \
		--identity "$(VM_CODESIGN_IDENTITY)" \
		--entitlements "Entitlements.shared.plist"

vm-bridged-preflight:
	$(VM_BUILD_RUNNER) macos-runtime-require-bridged-identity \
		--identity "$(VM_BRIDGED_CODESIGN_IDENTITY)"

vm-sign-bridged: vm-build vm-bridged-preflight
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-sign \
		--identity "$(VM_BRIDGED_CODESIGN_IDENTITY)" \
		--entitlements "Entitlements.plist"

vm-init: vm-build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		init

vm-download:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" ubuntu \
		--runtime-dir "$(VM_RUNTIME_DIR)" \
		--rootfs-size "$(VM_ROOTFS_SIZE)" \
		--recreate-rootfs "$(VM_RECREATE_ROOTFS)"

vm-cloud-init:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" cloud-init \
		--runtime-dir "$(VM_RUNTIME_DIR)"

vm-prepare: vm-download vm-cloud-init vm-stage
	@printf "VM runtime is prepared under %s\n" "$(VM_HOME)"
	@printf "Start it with: make vm-start\n"

vm-up: vm-prepare vm-start-detached vm-wait-ip vm-wait-http vm-proxy-start

vm-up-bridged: vm-bridged-preflight vm-prepare vm-network-bridged vm-start-bridged

vm-down: vm-stop

vm-stage: vm-init
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" guest-deploy \
		--vm-home "$(VM_HOME)" \
		--runtime-dir "$(VM_MACOS_RUNTIME_DIR)"

vm-start: vm-sign
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		start

vm-start-detached: vm-sign
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-start-detached \
		--vm-home "$(VM_HOME)"

vm-start-bridged: vm-sign-bridged
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		start

vm-stop:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		stop

vm-status:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		status

vm-ip:
	$(VM_BUILD_RUNNER) macos-runtime-ip --vm-home "$(VM_HOME)"

vm-wait-ip:
	$(VM_BUILD_RUNNER) macos-runtime-wait-ip \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_WAIT_TIMEOUT)"

vm-wait-http:
	$(VM_BUILD_RUNNER) macos-runtime-wait-http \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_HTTP_WAIT_TIMEOUT)"

vm-wait-rootfs-ready:
	$(VM_BUILD_RUNNER) macos-runtime-wait-rootfs-ready \
		--vm-home "$(VM_HOME)" \
		--timeout "$(VM_HTTP_WAIT_TIMEOUT)"

vm-proxy-start:
	@upstream="$(VM_PROXY_UPSTREAM)"; \
	if [ -z "$$upstream" ]; then \
		if [ ! -s "$(VM_HOME)/data/run/vm-ip" ]; then \
			printf "Set VM_PROXY_UPSTREAM or run make vm-wait-ip first.\n" >&2; \
			printf "  VM_PROXY_UPSTREAM=192.168.64.3:80 make vm-proxy-start\n" >&2; \
			exit 1; \
		fi; \
		upstream="$$(cat "$(VM_HOME)/data/run/vm-ip"):80"; \
	fi; \
	PROXY_UPSTREAM="$$upstream" $(MAKE) proxy-start

vm-health:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-health \
		--vm-home "$(VM_HOME)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)"

vm-coverage:
	CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift test --enable-code-coverage --package-path "$(VM_SWIFT_PACKAGE_DIR)"
	$(VM_LLVM_COV) report "$(VM_SWIFT_TEST_BINARY)" \
		-instr-profile "$(VM_SWIFT_COVERAGE_PROFILE)" \
		-ignore-filename-regex='$(VM_SWIFT_COVERAGE_IGNORE)'

vm-interfaces: vm-sign-bridged
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		interfaces

vm-network-shared: vm-build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		network shared

vm-network-bridged: vm-sign-bridged
	@test -n "$(VM_BRIDGED_INTERFACE)" || { printf "Set VM_BRIDGED_INTERFACE. Run: make vm-interfaces\n" >&2; exit 1; }
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		network bridged "$(VM_BRIDGED_INTERFACE)"

vm-clean: vm-build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		clean

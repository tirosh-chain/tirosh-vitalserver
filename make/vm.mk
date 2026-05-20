VM_LAUNCHER_DIR ?= apps/vitalserver-vm-launcher
VM_LAUNCHER_BIN ?= $(VM_LAUNCHER_DIR)/.build/release/vitalserver-vm
VM_LAUNCHER_ENTITLEMENTS ?= $(VM_LAUNCHER_DIR)/Entitlements.shared.plist
VM_LAUNCHER_BRIDGED_ENTITLEMENTS ?= $(VM_LAUNCHER_DIR)/Entitlements.plist
VM_CODESIGN_IDENTITY ?= -
VM_BRIDGED_CODESIGN_IDENTITY ?= $(VM_CODESIGN_IDENTITY)
VM_SDKROOT ?= $(firstword $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk) $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null))
VM_CLANG_MODULE_CACHE ?= $(CURDIR)/.tmp/clang-module-cache
VM_HOME ?= $(HOME)/.tirosh/vitalserver-vm
VM_SUPPORT_DIR ?= $(VM_LAUNCHER_DIR)/Support
VM_BUILD_SUPPORT_DIR ?= $(VM_SUPPORT_DIR)/Build
VM_GUEST_DIR ?= $(VM_SUPPORT_DIR)/Guest
VM_IMAGE_DIR ?= $(VM_HOME)/images
VM_DEPLOY_DIR ?= $(VM_HOME)/data/deploy
VM_RUN_DIR ?= $(VM_HOME)/data/run
VM_IP_FILE ?= $(VM_RUN_DIR)/vm-ip
VM_UBUNTU_CONFIG ?= $(VM_BUILD_SUPPORT_DIR)/ubuntu-cloud-image.env
VM_RSYNC_EXCLUDES ?= --exclude .DS_Store --exclude __pycache__
VM_WAIT_TIMEOUT ?= 300

.PHONY: vm-up vm-up-bridged vm-down vm-prepare vm-start vm-start-detached vm-start-bridged vm-stop vm-status vm-clean vm-ip vm-wait-ip vm-proxy-start vm-health
.PHONY: vm-build vm-sign vm-sign-bridged vm-bridged-preflight vm-init vm-download vm-cloud-init vm-stage vm-interfaces vm-network-shared vm-network-bridged

vm-build:
	cd "$(VM_LAUNCHER_DIR)" && env SDKROOT="$(VM_SDKROOT)" CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift build -c release

vm-sign: vm-build
	codesign --force --sign "$(VM_CODESIGN_IDENTITY)" --entitlements "$(VM_LAUNCHER_ENTITLEMENTS)" "$(VM_LAUNCHER_BIN)"

vm-bridged-preflight:
	@if [ "$(VM_BRIDGED_CODESIGN_IDENTITY)" = "-" ]; then \
		printf "bridged mode requires a real codesign identity with the bridged networking entitlement.\n" >&2; \
		printf "ad-hoc signing can be used for shared/NAT mode only.\n" >&2; \
		printf "Set VM_BRIDGED_CODESIGN_IDENTITY, for example:\n" >&2; \
		printf "  VM_BRIDGED_CODESIGN_IDENTITY='Developer ID Application: ...' make vm-up-bridged\n" >&2; \
		exit 1; \
	fi

vm-sign-bridged: vm-build vm-bridged-preflight
	codesign --force --sign "$(VM_BRIDGED_CODESIGN_IDENTITY)" --entitlements "$(VM_LAUNCHER_BRIDGED_ENTITLEMENTS)" "$(VM_LAUNCHER_BIN)"

vm-init: vm-build
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" init

vm-download:
	VM_IMAGE_DIR="$(VM_IMAGE_DIR)" \
	VM_UBUNTU_CONFIG="$(VM_UBUNTU_CONFIG)" \
	"$(VM_BUILD_SUPPORT_DIR)/download-ubuntu.sh"

vm-cloud-init:
	VM_IMAGE_DIR="$(VM_IMAGE_DIR)" \
	"$(VM_BUILD_SUPPORT_DIR)/create-cloud-init.sh"

vm-prepare: vm-download vm-cloud-init vm-stage
	@printf "VM runtime is prepared under %s\n" "$(VM_HOME)"
	@printf "Start it with: make vm-start\n"

vm-up: vm-prepare vm-start-detached vm-wait-ip vm-proxy-start

vm-up-bridged: vm-bridged-preflight vm-prepare vm-network-bridged vm-start-bridged

vm-down: vm-stop

vm-stage: vm-init
	@printf "Staging Linux guest deployment bundle into %s\n" "$(VM_DEPLOY_DIR)"
	@mkdir -p "$(VM_DEPLOY_DIR)" "$(VM_HOME)/data/vital-files" "$(VM_HOME)/data/vr-release" "$(VM_RUN_DIR)"
	rsync -a $(VM_RSYNC_EXCLUDES) "$(VM_GUEST_DIR)/" "$(VM_DEPLOY_DIR)/"
	@mkdir -p "$(VM_DEPLOY_DIR)/apps/vitalserver" "$(VM_DEPLOY_DIR)/vendor/vitalserver"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/docker "$(VM_DEPLOY_DIR)/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/runtime "$(VM_DEPLOY_DIR)/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) vendor/vitalserver/vitalserver-old "$(VM_DEPLOY_DIR)/vendor/vitalserver/"
	@if [ ! -f "$(VM_DEPLOY_DIR)/.env" ]; then \
		cp "$(VM_DEPLOY_DIR)/vitalserver.env" "$(VM_DEPLOY_DIR)/.env"; \
		printf "created %s\n" "$(VM_DEPLOY_DIR)/.env"; \
	else \
		printf "exists %s\n" "$(VM_DEPLOY_DIR)/.env"; \
	fi
	@printf "cloud-init will run /mnt/tirosh/deploy/bootstrap.sh on first boot\n"

vm-start: vm-sign
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" start

vm-start-detached: vm-sign
	@mkdir -p "$(VM_HOME)/logs" "$(VM_RUN_DIR)"
	@if [ -f "$(VM_HOME)/run/vitalserver-vm.pid" ] && kill -0 "$$(cat "$(VM_HOME)/run/vitalserver-vm.pid")" >/dev/null 2>&1; then \
		printf "VM is already running: pid %s\n" "$$(cat "$(VM_HOME)/run/vitalserver-vm.pid")"; \
	else \
		VITALSERVER_VM_HOME="$(VM_HOME)" VITALSERVER_VM_DETACHED=1 nohup "$(VM_LAUNCHER_BIN)" start >"$(VM_HOME)/logs/launcher.log" 2>&1 & \
		printf "VM launcher started in background. Logs: %s\n" "$(VM_HOME)/logs/launcher.log"; \
	fi

vm-start-bridged: vm-sign-bridged
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" start

vm-stop:
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" stop

vm-status:
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" status

vm-ip:
	@if [ -s "$(VM_IP_FILE)" ]; then \
		cat "$(VM_IP_FILE)"; \
	else \
		printf "VM IP is not available yet: %s\n" "$(VM_IP_FILE)" >&2; \
		exit 1; \
	fi

vm-wait-ip:
	@printf "Waiting for VM IP file: %s\n" "$(VM_IP_FILE)"
	@deadline=$$(( $$(date +%s) + $(VM_WAIT_TIMEOUT) )); \
	while [ $$(date +%s) -lt $$deadline ]; do \
		if [ -s "$(VM_IP_FILE)" ]; then \
			printf "VM IP: %s\n" "$$(cat "$(VM_IP_FILE)")"; \
			exit 0; \
		fi; \
		sleep 2; \
	done; \
	printf "error: timed out waiting for VM IP. Check %s\n" "$(VM_HOME)/logs/launcher.log" >&2; \
	exit 1

vm-proxy-start:
	@upstream="$(VM_PROXY_UPSTREAM)"; \
	if [ -z "$$upstream" ]; then \
		if [ ! -s "$(VM_IP_FILE)" ]; then \
			printf "Set VM_PROXY_UPSTREAM or run make vm-wait-ip first.\n" >&2; \
			printf "  VM_PROXY_UPSTREAM=192.168.64.3:80 make vm-proxy-start\n" >&2; \
			exit 1; \
		fi; \
		upstream="$$(cat "$(VM_IP_FILE)"):80"; \
	fi; \
	PROXY_UPSTREAM="$$upstream" $(MAKE) proxy-start

vm-health:
	@status=0; \
	vm_ip=""; \
	printf "VM health\n"; \
	printf "  home: %s\n" "$(VM_HOME)"; \
	if [ -x "$(VM_LAUNCHER_BIN)" ]; then \
		printf "\nVM process:\n"; \
		if ! VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" status; then \
			status=1; \
		fi; \
	else \
		printf "\nVM process:\n"; \
		printf "  missing launcher binary: %s\n" "$(VM_LAUNCHER_BIN)" >&2; \
		printf "  run: make vm-build\n" >&2; \
		status=1; \
	fi; \
	printf "\nVM IP:\n"; \
	if [ -s "$(VM_IP_FILE)" ]; then \
		vm_ip="$$(cat "$(VM_IP_FILE)")"; \
		printf "  %s\n" "$$vm_ip"; \
	else \
		printf "  missing %s\n" "$(VM_IP_FILE)" >&2; \
		status=1; \
	fi; \
	printf "\nGuest HTTP:\n"; \
	if [ -n "$$vm_ip" ]; then \
		if command -v curl >/dev/null 2>&1; then \
			code="$$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://$$vm_ip/" 2>/dev/null)" && http_status=0 || http_status=$$?; \
			if [ "$$http_status" -eq 0 ] && [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ]; then \
				printf "  ok http://%s/ -> %s\n" "$$vm_ip" "$$code"; \
			else \
				printf "  failed http://%s/ -> %s\n" "$$vm_ip" "$${code:-curl-error}" >&2; \
				status=1; \
			fi; \
		else \
			printf "  curl is not installed\n" >&2; \
			status=1; \
		fi; \
	else \
		printf "  skipped because VM IP is unavailable\n" >&2; \
	fi; \
	printf "\nHost proxy:\n"; \
	$(MAKE) --no-print-directory proxy-status || status=1; \
	if command -v lsof >/dev/null 2>&1; then \
		printf "  listeners on port %s:\n" "$(VITALSERVER_PROXY_PORT)"; \
		lsof -nP -iTCP:"$(VITALSERVER_PROXY_PORT)" -sTCP:LISTEN 2>/dev/null | sed 's/^/    /' || true; \
	fi; \
	if command -v curl >/dev/null 2>&1; then \
		code="$$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$(VITALSERVER_PROXY_PORT)/" 2>/dev/null)" && http_status=0 || http_status=$$?; \
		if [ "$$http_status" -eq 0 ] && [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ]; then \
			printf "  ok http://127.0.0.1:%s/ -> %s\n" "$(VITALSERVER_PROXY_PORT)" "$$code"; \
		else \
			printf "  failed http://127.0.0.1:%s/ -> %s\n" "$(VITALSERVER_PROXY_PORT)" "$${code:-curl-error}" >&2; \
			status=1; \
		fi; \
	fi; \
	exit $$status

vm-interfaces: vm-sign-bridged
	"$(VM_LAUNCHER_BIN)" interfaces

vm-network-shared: vm-build
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" network shared

vm-network-bridged: vm-sign-bridged
	@test -n "$(VM_BRIDGED_INTERFACE)" || { printf "Set VM_BRIDGED_INTERFACE. Run: make vm-interfaces\n" >&2; exit 1; }
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" network bridged "$(VM_BRIDGED_INTERFACE)"

vm-clean: vm-build
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" clean

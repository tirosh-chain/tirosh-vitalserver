VM_LAUNCHER_DIR ?= apps/vitalserver-vm-launcher
VM_LAUNCHER_BIN ?= $(VM_LAUNCHER_DIR)/.build/release/vitalserver-vm
VM_LAUNCHER_ENTITLEMENTS ?= $(VM_LAUNCHER_DIR)/Entitlements.shared.plist
VM_LAUNCHER_BRIDGED_ENTITLEMENTS ?= $(VM_LAUNCHER_DIR)/Entitlements.plist
VM_SDKROOT ?= $(firstword $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk) $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null))
VM_CLANG_MODULE_CACHE ?= $(CURDIR)/.tmp/clang-module-cache
VM_HOME ?= $(HOME)/.tirosh/vitalserver-vm
VM_SUPPORT_DIR ?= $(VM_LAUNCHER_DIR)/Support
VM_BUILD_SUPPORT_DIR ?= $(VM_SUPPORT_DIR)/Build
VM_GUEST_DIR ?= $(VM_SUPPORT_DIR)/Guest
VM_IMAGE_DIR ?= $(VM_HOME)/images
VM_DEPLOY_DIR ?= $(VM_HOME)/data/deploy
VM_UBUNTU_CONFIG ?= $(VM_BUILD_SUPPORT_DIR)/ubuntu-cloud-image.env
VM_RSYNC_EXCLUDES ?= --exclude .DS_Store --exclude __pycache__

.PHONY: vm-up vm-down vm-prepare vm-start vm-stop vm-status vm-clean
.PHONY: vm-build vm-sign vm-sign-bridged vm-init vm-download vm-cloud-init vm-stage vm-interfaces

vm-build:
	cd "$(VM_LAUNCHER_DIR)" && env SDKROOT="$(VM_SDKROOT)" CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift build -c release

vm-sign: vm-build
	codesign --force --sign - --entitlements "$(VM_LAUNCHER_ENTITLEMENTS)" "$(VM_LAUNCHER_BIN)"

vm-sign-bridged: vm-build
	codesign --force --sign - --entitlements "$(VM_LAUNCHER_BRIDGED_ENTITLEMENTS)" "$(VM_LAUNCHER_BIN)"

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

vm-up: vm-prepare vm-start

vm-down: vm-stop

vm-stage: vm-init
	@printf "Staging Linux guest deployment bundle into %s\n" "$(VM_DEPLOY_DIR)"
	@mkdir -p "$(VM_DEPLOY_DIR)" "$(VM_HOME)/data/vital-files" "$(VM_HOME)/data/vr-release"
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

vm-stop:
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" stop

vm-status:
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" status

vm-interfaces: vm-sign-bridged
	"$(VM_LAUNCHER_BIN)" interfaces

vm-clean: vm-build
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" clean

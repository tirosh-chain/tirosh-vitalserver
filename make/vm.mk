VM_LAUNCHER_DIR ?= apps/vitalserver-vm-launcher
VM_LAUNCHER_BIN ?= $(VM_LAUNCHER_DIR)/.build/release/vitalserver-vm
VM_LAUNCHER_ENTITLEMENTS ?= $(VM_LAUNCHER_DIR)/Entitlements.shared.plist
VM_LAUNCHER_BRIDGED_ENTITLEMENTS ?= $(VM_LAUNCHER_DIR)/Entitlements.plist
VM_SDKROOT ?= $(firstword $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk) $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null))
VM_CLANG_MODULE_CACHE ?= $(CURDIR)/.tmp/clang-module-cache

.PHONY: vm-build vm-sign vm-sign-bridged vm-init vm-start vm-stop vm-status vm-interfaces vm-clean

vm-build:
	cd "$(VM_LAUNCHER_DIR)" && env SDKROOT="$(VM_SDKROOT)" CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift build -c release

vm-sign: vm-build
	codesign --force --sign - --entitlements "$(VM_LAUNCHER_ENTITLEMENTS)" "$(VM_LAUNCHER_BIN)"

vm-sign-bridged: vm-build
	codesign --force --sign - --entitlements "$(VM_LAUNCHER_BRIDGED_ENTITLEMENTS)" "$(VM_LAUNCHER_BIN)"

vm-init: vm-build
	"$(VM_LAUNCHER_BIN)" init

vm-start: vm-sign
	"$(VM_LAUNCHER_BIN)" start

vm-stop:
	"$(VM_LAUNCHER_BIN)" stop

vm-status:
	"$(VM_LAUNCHER_BIN)" status

vm-interfaces: vm-sign-bridged
	"$(VM_LAUNCHER_BIN)" interfaces

vm-clean: vm-build
	"$(VM_LAUNCHER_BIN)" clean

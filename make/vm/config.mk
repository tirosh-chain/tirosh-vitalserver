# User-facing knobs.
VM_HOME ?= $(HOME)/.tirosh/vitalserver-vm
VM_ROOTFS_SIZE ?= 8G
VM_RECREATE_ROOTFS ?= false
VM_RECREATE_GOLDEN_ROOTFS ?= true
VM_WAIT_TIMEOUT ?= 300
VM_HTTP_WAIT_TIMEOUT ?= 600
VM_PKG_VERSION ?= 0.1.0
VM_UPDATE_BUNDLE_VERSION ?= $(VM_PKG_VERSION)
VM_UPDATE_MIGRATIONS ?=
VM_NGINX_BIN ?=
VM_NGINX_EXPECTED_VERSION ?=
VM_CODESIGN_IDENTITY ?= -
VM_BRIDGED_CODESIGN_IDENTITY ?= $(VM_CODESIGN_IDENTITY)

# Build toolchain.
VM_LAUNCHER_DIR := apps/vitalserver-vm-launcher
VM_LAUNCHER_BIN := $(VM_LAUNCHER_DIR)/.build/release/vitalserver-vm
VM_APP_BIN := $(VM_LAUNCHER_DIR)/.build/release/TiroshVitalServerApp
VM_LAUNCHER_ENTITLEMENTS := $(VM_LAUNCHER_DIR)/Entitlements.shared.plist
VM_LAUNCHER_BRIDGED_ENTITLEMENTS := $(VM_LAUNCHER_DIR)/Entitlements.plist
VM_SDKROOT := $(firstword $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk) $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null))
VM_CLANG_MODULE_CACHE := $(CURDIR)/.tmp/clang-module-cache
VM_BUILD_RUNNER := $(UV) run --project packages/vm-build vitalserver-vm-build
VM_BUILD_CONFIG := $(VM_LAUNCHER_DIR)/Support/Build/vm-build.toml

# Local runtime paths.
VM_RUNTIME_DIR := $(VM_HOME)/runtime
VM_DISK_IMAGE := $(VM_RUNTIME_DIR)/vm-disk.img
VM_DEPLOY_DIR := $(VM_HOME)/data/deploy
VM_RUN_DIR := $(VM_HOME)/data/run
VM_IP_FILE := $(VM_RUN_DIR)/vm-ip
VM_ROOTFS_READY_FILE := $(VM_RUN_DIR)/rootfs-ready

# Source directories.
VM_GUEST_DIR := $(VM_LAUNCHER_DIR)/Support/Guest
VM_PACKAGING_DIR := $(VM_LAUNCHER_DIR)/Support/Packaging
VM_RSYNC_EXCLUDES := --exclude .DS_Store --exclude __pycache__

# Product/install constants.
VM_PKG_IDENTIFIER := com.tirosh.vitalserver.vm
VM_INSTALL_PREFIX := /Library/Application Support/TiroshVitalServer
VM_INSTALL_HOME := $(VM_INSTALL_PREFIX)/vm
VM_INSTALL_APPLICATIONS_DIR := /Applications
VM_INSTALL_APP_BUNDLE := $(VM_INSTALL_APPLICATIONS_DIR)/Tirosh VitalServer Manager.app
VM_INSTALL_BIN := /usr/local/bin/vitalserver-vm
VM_INSTALL_PROXY_RUN := /usr/local/bin/vitalserver-proxy-run
VM_INSTALL_UNINSTALL := /usr/local/bin/tirosh-vitalserver-uninstall
VM_INSTALL_NGINX_PREFIX := $(VM_INSTALL_PREFIX)/nginx
VM_INSTALL_NGINX_BIN := $(VM_INSTALL_NGINX_PREFIX)/sbin/nginx

# Package artifacts.
VM_DIST_DIR := dist
VM_PKG_BUILD_DIR := .tmp/vitalserver-vm-pkg
VM_PKG_ROOT := $(VM_PKG_BUILD_DIR)/root
VM_PKG_SCRIPTS := $(VM_PKG_BUILD_DIR)/scripts
VM_PKG_OUTPUT := $(VM_DIST_DIR)/TiroshVitalServerVM-$(VM_PKG_VERSION).pkg
VM_PKG_NGINX_BUNDLE_DIR := $(VM_PKG_BUILD_DIR)/nginx-bundle
VM_PKG_ROOTFS_CACHE := $(VM_PKG_BUILD_DIR)/rootfs-base.raw.gz
VM_DOCKER_IMAGE_BUNDLE := $(VM_PKG_BUILD_DIR)/docker-images/vitalserver-images.tar.gz
VM_UPDATE_BUNDLE_DIR := $(VM_DIST_DIR)/update-bundles
VM_UPDATE_BUNDLE_PATH := $(VM_UPDATE_BUNDLE_DIR)/update-bundle-$(VM_UPDATE_BUNDLE_VERSION)

# App artifacts.
VM_APP_NAME := Tirosh VitalServer Manager
VM_APP_BUNDLE := .tmp/$(VM_APP_NAME).app
VM_DMG_STAGING := .tmp/vitalserver-vm-dmg
VM_DMG_OUTPUT := $(VM_DIST_DIR)/TiroshVitalServer-$(VM_PKG_VERSION).dmg
VM_INSTALLED_IP_FILE := $(VM_INSTALL_HOME)/data/run/vm-ip

# Golden rootfs build paths. Keep these separate from the developer VM home so
# mutable local VM state never becomes the package base artifact by accident.
VM_GOLDEN_HOME := .tmp/vitalserver-vm-golden
VM_GOLDEN_RUNTIME_DIR := $(VM_GOLDEN_HOME)/runtime
VM_GOLDEN_DISK_IMAGE := $(VM_GOLDEN_RUNTIME_DIR)/vm-disk.img

# User-facing knobs.
VM_MACOS_RUNTIME_DIR := apps/vitalserver-macos-runtime
VM_HOME ?= $(HOME)/.tirosh/vitalserver-vm
VM_ROOTFS_SIZE ?= 4G
VM_RECREATE_ROOTFS ?= false
VM_RECREATE_GOLDEN_ROOTFS ?= false
VM_COMPRESSION_THREADS ?= $(shell sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
VM_WAIT_TIMEOUT ?= 300
VM_HTTP_WAIT_TIMEOUT ?= 600
VM_RELEASE_FILE := $(VM_MACOS_RUNTIME_DIR)/release.json
VM_RELEASE_JSON = import json; data=json.load(open("$(VM_RELEASE_FILE)"))
VM_RELEASE_VALUE = $(strip $(shell python3 -c '$(VM_RELEASE_JSON); print($(1))' 2>/dev/null))
VM_PRODUCT_VERSION := $(call VM_RELEASE_VALUE,data["helperVersion"])
VM_RELEASE_MIN_UPDATER_VERSION := $(call VM_RELEASE_VALUE,data["minUpdaterVersion"])
VM_RELEASE_VITALSERVER_VERSION := $(call VM_RELEASE_VALUE,data["vitalServerVersion"])
VM_RELEASE_VITALSERVER_IMAGE := $(call VM_RELEASE_VALUE,data["services"]["vitalServer"]["image"])
VM_RELEASE_REDIS_IMAGE := $(call VM_RELEASE_VALUE,data["services"]["redis"]["image"])
VM_RELEASE_REDIS_UI_IMAGE := $(call VM_RELEASE_VALUE,data["services"]["redisUI"]["image"])
VM_RELEASE_SWAGGER_UI_IMAGE := $(call VM_RELEASE_VALUE,data["services"]["swaggerUI"]["image"])
VM_RELEASE_GUEST_EDGE_IMAGE := $(call VM_RELEASE_VALUE,data["services"]["guestEdge"]["image"])
VM_RELEASE_HOST_PROXY_IMAGE := $(call VM_RELEASE_VALUE,data["services"]["hostProxy"]["image"])
VM_RELEASE_REDIS_VERSION := $(call VM_RELEASE_VALUE,data["services"]["redis"]["version"])
VM_RELEASE_REDIS_UI_VERSION := $(call VM_RELEASE_VALUE,data["services"]["redisUI"]["version"])
VM_RELEASE_SWAGGER_UI_VERSION := $(call VM_RELEASE_VALUE,data["services"]["swaggerUI"]["version"])
VM_RELEASE_GUEST_EDGE_VERSION := $(call VM_RELEASE_VALUE,data["services"]["guestEdge"]["version"])
VM_RELEASE_HOST_PROXY_VERSION := $(call VM_RELEASE_VALUE,data["services"]["hostProxy"]["version"])
VM_GENERATED_VERSION_SWIFT := $(VM_MACOS_RUNTIME_DIR)/Sources/HostCLI/Runtime/GeneratedVersion.swift
VM_GENERATED_RELEASE_SWIFT := $(VM_MACOS_RUNTIME_DIR)/Sources/MacRuntimeControlApp/GeneratedRelease.swift
VM_PKG_VERSION ?= $(VM_PRODUCT_VERSION)
VM_UPDATE_BUNDLE_VERSION ?= $(VM_PKG_VERSION)
VM_UPDATE_MIN_UPDATER_VERSION ?= $(VM_RELEASE_MIN_UPDATER_VERSION)
VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE ?= false
VM_UPDATE_MIGRATIONS ?= \
	$(VM_MACOS_RUNTIME_DIR)/Support/Build/migrations/001-refresh-cloud-init-seed \
	$(VM_MACOS_RUNTIME_DIR)/Support/Build/migrations/002-migrate-runtime-logs
VM_NGINX_SOURCE_BIN ?= /opt/homebrew/opt/nginx/bin/nginx
VM_NGINX_BIN ?=
VM_NGINX_EXPECTED_VERSION ?= $(VM_RELEASE_HOST_PROXY_IMAGE)
VM_INSTALL_SETTINGS ?=
VM_CODESIGN_IDENTITY ?= -
VM_BRIDGED_CODESIGN_IDENTITY ?= $(VM_CODESIGN_IDENTITY)

# Build toolchain.
VM_RUNTIME_CLI_BIN := $(VM_MACOS_RUNTIME_DIR)/.build/release/vitalserver-vm
VM_APP_BIN := $(VM_MACOS_RUNTIME_DIR)/.build/release/VitalServerHelper
VM_RUNTIME_CLI_ENTITLEMENTS := $(VM_MACOS_RUNTIME_DIR)/Entitlements.shared.plist
VM_RUNTIME_CLI_BRIDGED_ENTITLEMENTS := $(VM_MACOS_RUNTIME_DIR)/Entitlements.plist
VM_APP_INFO_PLIST = $(VM_APP_BUNDLE)/Contents/Info.plist
VM_SDKROOT := $(firstword $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk) $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null))
VM_CLANG_MODULE_CACHE := $(CURDIR)/.tmp/clang-module-cache
VM_BUILD_RUNNER := $(UV) run --project packages/vm-build vitalserver-vm-build
VM_BUILD_CONFIG := $(VM_MACOS_RUNTIME_DIR)/Support/Build/vm-build.toml
VM_NGINX_ARTIFACT_BIN := .artifacts/nginx/macos/bin/nginx

# Local runtime paths.
VM_RUNTIME_DIR := $(VM_HOME)/runtime
VM_DISK_IMAGE := $(VM_RUNTIME_DIR)/vm-disk.img
VM_DEPLOY_DIR := $(VM_HOME)/data/deploy
VM_RUN_DIR := $(VM_HOME)/data/run
VM_IP_FILE := $(VM_RUN_DIR)/vm-ip
VM_ROOTFS_READY_FILE := $(VM_RUN_DIR)/rootfs-ready

# Source directories.
VM_GUEST_DIR := $(VM_MACOS_RUNTIME_DIR)/Support/Guest
VM_PACKAGING_DIR := $(VM_MACOS_RUNTIME_DIR)/Support/Packaging
VM_RSYNC_EXCLUDES := --exclude .DS_Store --exclude '._*' --exclude __pycache__

# Product/install constants.
VM_PKG_IDENTIFIER := com.tirosh.vitalserver.vm
VM_INSTALL_PREFIX := /Library/Application Support/TiroshVitalServer
VM_INSTALL_HOME := $(VM_INSTALL_PREFIX)/vm
VM_INSTALL_RUNTIME_LOGS := $(VM_INSTALL_PREFIX)/logs/runtime
VM_INSTALL_APPLICATIONS_DIR := /Applications
VM_INSTALL_APP_BUNDLE := $(VM_INSTALL_APPLICATIONS_DIR)/VitalServer Helper.app
VM_INSTALL_BIN := /usr/local/bin/vitalserver-vm
VM_INSTALL_PROXY_RUN := /usr/local/bin/vitalserver-proxy-run
VM_INSTALL_UNINSTALL := /usr/local/bin/tirosh-vitalserver-uninstall
VM_INSTALL_NGINX_PREFIX := $(VM_INSTALL_PREFIX)/nginx
VM_INSTALL_NGINX_BIN := $(VM_INSTALL_NGINX_PREFIX)/sbin/nginx
VM_INSTALL_SETTINGS_PATH := /private/tmp/tirosh-vitalserver-install.json

# Package artifacts.
VM_DIST_DIR := dist
VM_PKG_BUILD_DIR := .tmp/vitalserver-vm-pkg
VM_PKG_ROOT := $(VM_PKG_BUILD_DIR)/root
VM_PKG_SCRIPTS := $(VM_PKG_BUILD_DIR)/scripts
VM_PKG_COMPONENT_PLIST := $(VM_PACKAGING_DIR)/components.plist
VM_PKG_OUTPUT := $(VM_DIST_DIR)/TiroshVitalServerVM-$(VM_PKG_VERSION).pkg
VM_PKG_NGINX_BUNDLE_DIR := $(VM_PKG_BUILD_DIR)/nginx-bundle
VM_PKG_ROOTFS_CACHE := $(VM_PKG_BUILD_DIR)/rootfs-base.raw.gz
VM_DOCKER_IMAGE_BUNDLE := $(VM_PKG_BUILD_DIR)/docker-images/vitalserver-images.tar.gz
VM_UPDATE_BUNDLE_DIR := $(VM_DIST_DIR)/update-bundles
VM_UPDATE_BUNDLE_PATH := $(VM_UPDATE_BUNDLE_DIR)/update-bundle-$(VM_UPDATE_BUNDLE_VERSION).tar.gz
VM_UPDATE_BUNDLE_KIND ?= product-update
VM_UPDATE_TARGET_PLATFORM ?= macos-arm64
VM_UPDATE_ARTIFACT_DIR := $(VM_PKG_BUILD_DIR)/update-artifacts
VM_UPDATE_APP_BUNDLE_ARCHIVE := $(VM_UPDATE_ARTIFACT_DIR)/app-bundle.tar.gz
VM_UPDATE_RUNTIME_TOOLS_ARCHIVE := $(VM_UPDATE_ARTIFACT_DIR)/runtime-tools.tar.gz
VM_UPDATE_NGINX_BUNDLE_ARCHIVE := $(VM_UPDATE_ARTIFACT_DIR)/nginx-bundle.tar.gz
VM_UPDATE_GUEST_DEPLOY_ARCHIVE := $(VM_UPDATE_ARTIFACT_DIR)/guest-deploy.tar.gz
VM_UPDATE_ROOTFS_BASE ?=
VM_UPDATE_APP_BUNDLE ?= $(VM_UPDATE_APP_BUNDLE_ARCHIVE)
VM_UPDATE_RUNTIME_TOOLS ?= $(VM_UPDATE_RUNTIME_TOOLS_ARCHIVE)
VM_UPDATE_NGINX_BUNDLE ?= $(VM_UPDATE_NGINX_BUNDLE_ARCHIVE)
VM_UPDATE_GUEST_DEPLOY ?= $(VM_UPDATE_GUEST_DEPLOY_ARCHIVE)

# App artifacts.
VM_APP_NAME := VitalServer Helper
VM_APP_BUNDLE := .tmp/$(VM_APP_NAME).app
VM_DMG_STAGING := .tmp/vitalserver-vm-dmg
VM_DMG_OUTPUT := $(VM_DIST_DIR)/TiroshVitalServer-$(VM_PKG_VERSION).dmg
VM_INSTALLED_IP_FILE := $(VM_INSTALL_HOME)/data/run/vm-ip

# Golden rootfs build paths. Keep these separate from the developer VM home so
# mutable local VM state never becomes the package base artifact by accident.
VM_GOLDEN_HOME := .tmp/vitalserver-vm-golden
VM_GOLDEN_RUNTIME_DIR := $(VM_GOLDEN_HOME)/runtime
VM_GOLDEN_DISK_IMAGE := $(VM_GOLDEN_RUNTIME_DIR)/vm-disk.img

# User-facing knobs.
VM_MACOS_RUNTIME_DIR := apps/vitalserver-macos-runtime
VM_HOME ?= $(HOME)/.tirosh/vitalserver-vm
VM_ROOTFS_SIZE ?= 4G
VM_RECREATE_ROOTFS ?= false
VM_RECREATE_GOLDEN_ROOTFS ?= false
VM_COMPRESSION_THREADS ?= $(shell sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
VM_WAIT_TIMEOUT ?= 300
VM_HTTP_WAIT_TIMEOUT ?= 600
VM_RELEASE_FILE ?= $(VM_MACOS_RUNTIME_DIR)/release.json
VM_RELEASE_JSON = import json; data=json.load(open("$(VM_RELEASE_FILE)"))
VM_RELEASE_VALUE = $(strip $(shell python3 -c '$(VM_RELEASE_JSON); print($(1))'))
VM_PRODUCT_VERSION = $(call VM_RELEASE_VALUE,data["helperVersion"])
VM_RELEASE_CHANNEL = $(call VM_RELEASE_VALUE,data["channel"])
VM_RELEASE_LABEL = $(call VM_RELEASE_VALUE,data["releaseLabel"])
VM_RELEASE_OPTIONAL_CONTAINER_SERVICES = $(call VM_RELEASE_VALUE," ".join(data["bundle"]["optionalContainerServices"]))
VM_RELEASE_INCLUDES_TESTKIT = $(call VM_RELEASE_VALUE,"true" if "testkit" in data["bundle"]["optionalContainerServices"] else "false")
VM_RELEASE_MIN_UPDATER_VERSION = $(call VM_RELEASE_VALUE,data["minUpdaterVersion"])
VM_RELEASE_VITALSERVER_VERSION = $(call VM_RELEASE_VALUE,data["vitalServerVersion"])
VM_RELEASE_VITALSERVER_IMAGE = $(call VM_RELEASE_VALUE,data["services"]["vitalServer"]["image"])
VM_RELEASE_REDIS_IMAGE = $(call VM_RELEASE_VALUE,data["services"]["redis"]["image"])
VM_RELEASE_REDIS_UI_IMAGE = $(call VM_RELEASE_VALUE,data["services"]["redisUI"]["image"])
VM_RELEASE_SWAGGER_UI_IMAGE = $(call VM_RELEASE_VALUE,data["services"]["swaggerUI"]["image"])
VM_RELEASE_GUEST_EDGE_IMAGE = $(call VM_RELEASE_VALUE,data["services"]["guestEdge"]["image"])
VM_RELEASE_HOST_PROXY_IMAGE = $(call VM_RELEASE_VALUE,data["services"]["hostProxy"]["image"])
VM_RELEASE_REDIS_VERSION = $(call VM_RELEASE_VALUE,data["services"]["redis"]["version"])
VM_RELEASE_REDIS_UI_VERSION = $(call VM_RELEASE_VALUE,data["services"]["redisUI"]["version"])
VM_RELEASE_SWAGGER_UI_VERSION = $(call VM_RELEASE_VALUE,data["services"]["swaggerUI"]["version"])
VM_RELEASE_GUEST_EDGE_VERSION = $(call VM_RELEASE_VALUE,data["services"]["guestEdge"]["version"])
VM_RELEASE_HOST_PROXY_VERSION = $(call VM_RELEASE_VALUE,data["services"]["hostProxy"]["version"])
VM_GENERATED_VERSION_SWIFT := $(VM_MACOS_RUNTIME_DIR)/Sources/HostCLI/Runtime/GeneratedVersion.swift
VM_GENERATED_RELEASE_SWIFT := $(VM_MACOS_RUNTIME_DIR)/Sources/MacRuntimeControlApp/GeneratedRelease.swift
VM_PKG_VERSION ?= $(VM_PRODUCT_VERSION)
VM_ARTIFACT_VERSION ?= $(VM_RELEASE_LABEL)
VM_UPDATE_BUNDLE_VERSION ?= $(VM_ARTIFACT_VERSION)
VM_UPDATE_CHANNEL ?= $(VM_RELEASE_CHANNEL)
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
VM_BUILD_RUNNER := $(UV) run --project packages/vm-build vitalserver-vm-build
VM_BUILD_CONFIG ?= config/vm-build.toml
VM_CONFIG_PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,$(UV) run --project packages/vm-build python)
VM_TOML_VALUE = $(strip $(shell $(VM_CONFIG_PYTHON) -c 'import tomllib; value=tomllib.load(open("$(VM_BUILD_CONFIG)","rb"))$(foreach key,$(subst ., ,$(1)),["$(key)"]); print(value)'))
VM_CLANG_MODULE_CACHE := $(CURDIR)/$(call VM_TOML_VALUE,workspace.clang_module_cache)
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
VM_PKG_IDENTIFIER := $(call VM_TOML_VALUE,package.identifier)
VM_INSTALL_PREFIX := $(call VM_TOML_VALUE,package.install.prefix)
VM_INSTALL_HOME := $(VM_INSTALL_PREFIX)/vm
VM_INSTALL_RUNTIME_LOGS := $(VM_INSTALL_PREFIX)/logs/runtime
VM_INSTALL_APPLICATIONS_DIR := $(call VM_TOML_VALUE,package.install.applications_dir)
VM_INSTALL_LAUNCH_DAEMONS_DIR := $(call VM_TOML_VALUE,package.install.launch_daemons_dir)
VM_INSTALL_APP_BUNDLE := $(VM_INSTALL_APPLICATIONS_DIR)/$(call VM_TOML_VALUE,app.name).app
VM_INSTALL_BIN := $(call VM_TOML_VALUE,package.install.bin)
VM_INSTALL_PROXY_RUN := $(call VM_TOML_VALUE,package.install.proxy_run)
VM_INSTALL_UNINSTALL := $(call VM_TOML_VALUE,package.install.uninstall)
VM_INSTALL_NGINX_PREFIX := $(VM_INSTALL_PREFIX)/nginx
VM_INSTALL_NGINX_BIN := $(VM_INSTALL_NGINX_PREFIX)/sbin/nginx
VM_INSTALL_SETTINGS_PATH := $(call VM_TOML_VALUE,package.install.settings_path)

# Package artifacts.
VM_DIST_DIR := $(call VM_TOML_VALUE,workspace.dist_dir)
VM_PKG_BUILD_DIR := $(call VM_TOML_VALUE,workspace.build_dir)
VM_PKG_ROOT := $(VM_PKG_BUILD_DIR)/root
VM_PKG_SCRIPTS := $(VM_PKG_BUILD_DIR)/scripts
VM_PKG_COMPONENT_PLIST := $(VM_PKG_BUILD_DIR)/components.plist
VM_PKG_OUTPUT = $(VM_DIST_DIR)/$(subst {releaseLabel},$(VM_ARTIFACT_VERSION),$(call VM_TOML_VALUE,package.outputs.pkg_name_template))
VM_PKG_NGINX_BUNDLE_DIR := $(VM_PKG_BUILD_DIR)/nginx-bundle
VM_PKG_ROOTFS_CACHE := $(VM_PKG_BUILD_DIR)/rootfs-base.raw.gz
VM_DOCKER_IMAGE_BUNDLE := $(call VM_TOML_VALUE,docker_images.bundle_path)
VM_UPDATE_BUNDLE_DIR := $(VM_DIST_DIR)/update-bundles
VM_UPDATE_BUNDLE_KIND ?= product-update
VM_UPDATE_TARGET_PLATFORM ?=
VM_UPDATE_BUNDLE_NAME ?= update-bundle-$(VM_UPDATE_CHANNEL)-$(VM_UPDATE_BUNDLE_KIND)-$(VM_UPDATE_BUNDLE_VERSION)
VM_UPDATE_BUNDLE_PATH = $(VM_UPDATE_BUNDLE_DIR)/$(VM_UPDATE_BUNDLE_NAME).tar.gz
VM_UPDATE_ROOTFS_BASE ?=

# App artifacts.
VM_APP_NAME := $(call VM_TOML_VALUE,app.name)
VM_APP_BUNDLE := $(call VM_TOML_VALUE,app.bundle_dir)
VM_DMG_STAGING := $(call VM_TOML_VALUE,package.outputs.dmg_staging_dir)
VM_DMG_OUTPUT = $(VM_DIST_DIR)/$(subst {releaseLabel},$(VM_ARTIFACT_VERSION),$(call VM_TOML_VALUE,package.outputs.dmg_name_template))
VM_INSTALLED_IP_FILE := $(VM_INSTALL_HOME)/data/run/vm-ip

# Golden rootfs build paths. Keep these separate from the developer VM home so
# mutable local VM state never becomes the package base artifact by accident.
VM_GOLDEN_HOME := .tmp/vitalserver-vm-golden
VM_GOLDEN_RUNTIME_DIR := $(VM_GOLDEN_HOME)/runtime
VM_GOLDEN_DISK_IMAGE := $(VM_GOLDEN_RUNTIME_DIR)/vm-disk.img

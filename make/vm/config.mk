# Runtime workspace.
VM_MACOS_RUNTIME_DIR := apps/vitalserver-macos-runtime
VM_HOME ?= $(HOME)/.tirosh/vitalserver-vm

# Release channel selection.
VM_DEV_RELEASE_FILE ?= $(VM_MACOS_RUNTIME_DIR)/release-dev.json
VM_STABLE_RELEASE_FILE ?= $(VM_MACOS_RUNTIME_DIR)/release.json
VM_RELEASE_FILE ?= $(VM_STABLE_RELEASE_FILE)

# Release guard.
VM_RELEASE_BRANCH ?= main

# Build options.
VM_COMPRESSION_THREADS ?= $(shell sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
VM_CODESIGN_IDENTITY ?= -
VM_BRIDGED_CODESIGN_IDENTITY ?= $(VM_CODESIGN_IDENTITY)

# Host toolchain.
VM_SDKROOT ?= $(firstword $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk) $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null))
VM_BUILD_RUNNER := $(DEVTOOLS_RUNNER)
VM_LLVM_COV ?= xcrun llvm-cov

# Build config access.
VM_BUILD_CONFIG ?= config/vm-build.toml
VM_TOML_VALUE = $(strip $(shell $(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" config-value "$(1)"))
VM_CLANG_MODULE_CACHE ?= $(CURDIR)/$(call VM_TOML_VALUE,workspace.clang_module_cache)

# Swift package test coverage.
VM_SWIFT_PACKAGE_DIR ?= $(VM_MACOS_RUNTIME_DIR)
VM_SWIFT_DEBUG_DIR ?= $(VM_SWIFT_PACKAGE_DIR)/.build/debug
VM_SWIFT_TEST_BINARY ?= $(VM_SWIFT_DEBUG_DIR)/TiroshVitalServerHelperPackageTests.xctest/Contents/MacOS/TiroshVitalServerHelperPackageTests
VM_SWIFT_COVERAGE_PROFILE ?= $(VM_SWIFT_DEBUG_DIR)/codecov/default.profdata
VM_SWIFT_COVERAGE_REPORT ?= $(VM_SWIFT_DEBUG_DIR)/codecov/coverage-report.txt
VM_SWIFT_COVERAGE_MIN ?= 85
VM_SWIFT_COVERAGE_IGNORE ?= /.build/|/Tests/|/Sources/(Contracts|HostCLI|MacRuntimeControlApp)/

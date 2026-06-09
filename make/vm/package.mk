.PHONY: internal/vm/nginx/artifact internal/vm/nginx/bundle internal/vm/docker/images
.PHONY: internal/vm/require-release-branch
.PHONY: internal/vm/pkg internal/vm/pkg/dev internal/vm/pkg/release
.PHONY: internal/vm/reset-installer internal/vm/reset-installer/dev internal/vm/reset-installer/release
.PHONY: internal/vm/app internal/vm/dmg internal/vm/dmg/dev internal/vm/dmg/release
.PHONY: internal/vm/pkg/clean internal/vm/pkg/install internal/vm/pkg/uninstall/dev
.PHONY: internal/vm/update internal/vm/update/dev internal/vm/update/release
.PHONY: internal/vm/image-update internal/vm/image-update/dev
.PHONY: internal/vm/image-update/release
.PHONY: internal/vm/update/verify internal/vm/update/verify/dev
.PHONY: internal/vm/update/verify/release
.PHONY: internal/vm/image-update/verify internal/vm/image-update/verify/dev
.PHONY: internal/vm/image-update/verify/release
.PHONY: internal/vm/airgap-rootfs internal/vm/golden-rootfs

VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE ?= false
VM_UPDATE_BUNDLE_KIND ?= product-update
VM_UPDATE_TARGET_PLATFORM ?=
VM_UPDATE_ROOTFS_BASE ?=

VM_NGINX_SOURCE_BIN ?= /opt/homebrew/opt/nginx/bin/nginx
VM_NGINX_BIN ?=
VM_NGINX_ARTIFACT_BIN := .artifacts/nginx/macos/bin/nginx

VM_PKG_BUILD_DIR ?= $(call VM_TOML_VALUE,workspace.build_dir)
VM_PKG_ROOTFS_CACHE ?= $(VM_PKG_BUILD_DIR)/rootfs-base.raw.gz
VM_PKG_ROOTFS_CONTRACT_STAMP ?= $(VM_PKG_BUILD_DIR)/rootfs-base.contract
VM_PKG_ROOTFS_CONTRACT_INPUTS := \
	$(VM_MACOS_RUNTIME_DIR)/Support/Guest/prepare-airgap-rootfs.sh \
	$(VM_MACOS_RUNTIME_DIR)/Support/Guest/bootstrap.sh
VM_PKG_ROOTFS_CONTRACT_FINGERPRINT := $(shell cksum $(VM_PKG_ROOTFS_CONTRACT_INPUTS) | cksum | awk '{print $$1 "-" $$2}')

VM_RECREATE_GOLDEN_ROOTFS ?= false
VM_GOLDEN_HOME := .tmp/vitalserver-vm-golden
VM_GOLDEN_RUNTIME_DIR := $(VM_GOLDEN_HOME)/runtime

VM_INSTALL_SETTINGS ?=
VM_UNINSTALL_ARGS ?=

internal/vm/airgap-rootfs: internal/vm/download internal/vm/stage
	@rm -f "$(VM_HOME)/data/run/rootfs-ready"
	@$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		stop >/dev/null 2>&1 || true
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" cloud-init \
		--runtime-dir "$(VM_RUNTIME_DIR)" \
		--bootstrap-script "/mnt/tirosh/deploy/prepare-airgap-rootfs.sh"
	$(MAKE) internal/vm/start/detached
	$(MAKE) internal/vm/wait/rootfs-ready
	$(MAKE) internal/vm/stop
	@printf "Air-gapped rootfs is prepared: %s\n" "$(VM_RUNTIME_DIR)/vm-disk.img"

internal/vm/golden-rootfs:
	@set -e; \
	rootfs_contract_expected="$(VM_PKG_ROOTFS_CONTRACT_FINGERPRINT)"; \
	rootfs_contract_actual=""; \
	if [ -s "$(VM_PKG_ROOTFS_CONTRACT_STAMP)" ]; then \
		rootfs_contract_actual="$$(cat "$(VM_PKG_ROOTFS_CONTRACT_STAMP)")"; \
	fi; \
	if [ "$(VM_RECREATE_GOLDEN_ROOTFS)" = "false" ] \
		&& [ -s "$(VM_PKG_ROOTFS_CACHE)" ] \
		&& [ -s "$(VM_GOLDEN_RUNTIME_DIR)/Image" ] \
		&& [ -s "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" ] \
		&& [ "$${rootfs_contract_actual}" = "$${rootfs_contract_expected}" ]; then \
		printf "Reusing golden rootfs cache: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
	else \
		if [ "$(VM_RECREATE_GOLDEN_ROOTFS)" != "false" ]; then \
			printf "Recreating golden rootfs cache: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
		elif [ -s "$(VM_PKG_ROOTFS_CACHE)" ]; then \
			if [ -z "$${rootfs_contract_actual}" ]; then \
				printf "Golden rootfs cache missing contract stamp; rebuilding: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
			else \
				printf "Golden rootfs cache contract changed; rebuilding: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
			fi; \
		fi; \
		$(MAKE) internal/vm/airgap-rootfs \
			VM_HOME="$(abspath $(VM_GOLDEN_HOME))" \
			VM_RECREATE_ROOTFS="$(VM_RECREATE_GOLDEN_ROOTFS)"; \
		test -s "$(VM_GOLDEN_HOME)/data/run/rootfs-ready" || { \
			printf "missing air-gapped rootfs marker after prepare: %s\n" "$(VM_GOLDEN_HOME)/data/run/rootfs-ready" >&2; \
			exit 1; \
		}; \
		$(VM_BUILD_RUNNER) rootfs-base \
			--source "$(VM_GOLDEN_RUNTIME_DIR)/vm-disk.img" \
			--output "$(VM_PKG_ROOTFS_CACHE)" \
			--compression-threads "$(VM_COMPRESSION_THREADS)"; \
		mkdir -p "$(dir $(VM_PKG_ROOTFS_CONTRACT_STAMP))"; \
		printf "%s\n" "$${rootfs_contract_expected}" >"$(VM_PKG_ROOTFS_CONTRACT_STAMP)"; \
	fi

internal/vm/nginx/artifact:
	@test -x "$(VM_NGINX_SOURCE_BIN)" || { \
		printf "missing nginx source binary: %s\n" "$(VM_NGINX_SOURCE_BIN)" >&2; \
		printf "Install nginx on the build machine, set VM_NGINX_SOURCE_BIN, or run with VM_NGINX_BIN=/path/to/nginx.\n" >&2; \
		exit 1; \
	}
	@mkdir -p "$(dir $(VM_NGINX_ARTIFACT_BIN))"
	install -m 0755 "$(VM_NGINX_SOURCE_BIN)" "$(VM_NGINX_ARTIFACT_BIN)"
	@"$(VM_NGINX_ARTIFACT_BIN)" -v
	@printf "nginx release artifact is ready: %s\n" "$(VM_NGINX_ARTIFACT_BIN)"

internal/vm/nginx/bundle: $(if $(VM_NGINX_BIN),,internal/vm/nginx/artifact)
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" nginx-bundle \
		--bundle-dir "$(VM_PKG_BUILD_DIR)/nginx-bundle" \
		--binary "$(VM_NGINX_BIN)" \
		--release-file "$(VM_RELEASE_FILE)"

internal/vm/docker/images:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" docker-images \
		--bundle-path "$(call VM_TOML_VALUE,guest.docker_images.bundle_path)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)"

internal/vm/require-release-branch:
	$(VM_BUILD_RUNNER) require-branch --branch "$(VM_RELEASE_BRANCH)"

internal/vm/app: pwa/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-app \
		--release-file "$(VM_RELEASE_FILE)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)"

internal/vm/pkg: internal/vm/golden-rootfs pwa/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-pkg \
		--release-file "$(VM_RELEASE_FILE)" \
		--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
		--golden-runtime-dir "$(VM_GOLDEN_RUNTIME_DIR)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)" \
		--nginx-binary "$(VM_NGINX_BIN)"

internal/vm/pkg/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/pkg/dev:
	$(MAKE) internal/vm/pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/pkg/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/pkg/release: VM_RECREATE_GOLDEN_ROOTFS := true
internal/vm/pkg/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_GOLDEN_ROOTFS="$(VM_RECREATE_GOLDEN_ROOTFS)"

internal/vm/dmg: internal/vm/golden-rootfs pwa/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-dmg \
		--release-file "$(VM_RELEASE_FILE)" \
		--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
		--golden-runtime-dir "$(VM_GOLDEN_RUNTIME_DIR)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)" \
		--nginx-binary "$(VM_NGINX_BIN)"

internal/vm/dmg/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/dmg/dev:
	$(MAKE) internal/vm/dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/dmg/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/dmg/release: VM_RECREATE_GOLDEN_ROOTFS := true
internal/vm/dmg/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_GOLDEN_ROOTFS="$(VM_RECREATE_GOLDEN_ROOTFS)"

internal/vm/reset-installer:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-reset-installer-pkg \
		--release-file "$(VM_RELEASE_FILE)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)"

internal/vm/reset-installer/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/reset-installer/dev:
	$(MAKE) internal/vm/reset-installer VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/reset-installer/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/reset-installer/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/reset-installer VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update: pwa/build
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-update-bundle \
		--release-file "$(VM_RELEASE_FILE)" \
		--bundle-kind "$(VM_UPDATE_BUNDLE_KIND)" \
		--requires-two-phase-update "$(VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)" \
		--nginx-binary "$(VM_NGINX_BIN)" \
		--target-platform "$(VM_UPDATE_TARGET_PLATFORM)" \
		--rootfs-base "$(VM_UPDATE_ROOTFS_BASE)"

internal/vm/update/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/update/dev:
	$(MAKE) internal/vm/update VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/update/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/update VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update: VM_UPDATE_ROOTFS_BASE = $(VM_PKG_ROOTFS_CACHE)
internal/vm/image-update: VM_UPDATE_BUNDLE_KIND := vm-image-update
internal/vm/image-update: VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE := true
internal/vm/image-update:
	$(MAKE) internal/vm/golden-rootfs VM_RELEASE_FILE="$(VM_RELEASE_FILE)"
	$(MAKE) internal/vm/update \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_ROOTFS_BASE="$(VM_UPDATE_ROOTFS_BASE)" \
		VM_UPDATE_BUNDLE_KIND="$(VM_UPDATE_BUNDLE_KIND)" \
		VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE="$(VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE)"

internal/vm/image-update/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/image-update/dev:
	$(MAKE) internal/vm/image-update VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/image-update/release: VM_RECREATE_GOLDEN_ROOTFS := true
internal/vm/image-update/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/image-update VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_GOLDEN_ROOTFS="$(VM_RECREATE_GOLDEN_ROOTFS)"

internal/vm/update/verify:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-update-bundle-verify \
		--release-file "$(VM_RELEASE_FILE)" \
		--bundle-kind "$(VM_UPDATE_BUNDLE_KIND)"

internal/vm/update/verify/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/update/verify/dev:
	$(MAKE) internal/vm/update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/update/verify/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/update/verify/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/verify: VM_UPDATE_BUNDLE_KIND := vm-image-update
internal/vm/image-update/verify: internal/vm/update/verify

internal/vm/image-update/verify/dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
internal/vm/image-update/verify/dev:
	$(MAKE) internal/vm/image-update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/image-update/verify/release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
internal/vm/image-update/verify/release:
	$(MAKE) internal/vm/require-release-branch
	$(MAKE) internal/vm/image-update/verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

internal/vm/pkg/clean:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-package-clean \
		--release-file "$(VM_RELEASE_FILE)"

internal/vm/pkg/install:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-package-install \
		--release-file "$(VM_RELEASE_FILE)" \
		--install-settings "$(VM_INSTALL_SETTINGS)"

internal/vm/pkg/uninstall/dev:
	sudo "$(VM_MACOS_RUNTIME_DIR)/Support/Packaging/uninstall-dev.sh" $(VM_UNINSTALL_ARGS)

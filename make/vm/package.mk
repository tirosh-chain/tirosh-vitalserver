.PHONY: vm-nginx-artifact vm-nginx-bundle vm-docker-images
.PHONY: vm-require-release-branch
.PHONY: vm-pkg vm-pkg-dev vm-pkg-release
.PHONY: vm-app vm-dmg vm-dmg-dev vm-dmg-release
.PHONY: vm-pkg-clean vm-pkg-install vm-pkg-uninstall-dev
.PHONY: vm-update-bundle vm-update-bundle-dev vm-update-bundle-release
.PHONY: vm-rootfs-update-bundle vm-rootfs-update-bundle-dev
.PHONY: vm-rootfs-update-bundle-release
.PHONY: vm-update-bundle-verify vm-update-bundle-verify-dev
.PHONY: vm-update-bundle-verify-release
.PHONY: vm-rootfs-update-bundle-verify vm-rootfs-update-bundle-verify-dev
.PHONY: vm-rootfs-update-bundle-verify-release
.PHONY: vm-airgap-rootfs vm-golden-rootfs

VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE ?= false
VM_UPDATE_BUNDLE_KIND ?= product-update
VM_UPDATE_TARGET_PLATFORM ?=
VM_UPDATE_ROOTFS_BASE ?=

VM_NGINX_SOURCE_BIN ?= /opt/homebrew/opt/nginx/bin/nginx
VM_NGINX_BIN ?=
VM_NGINX_ARTIFACT_BIN := .artifacts/nginx/macos/bin/nginx

VM_PKG_BUILD_DIR ?= $(call VM_TOML_VALUE,workspace.build_dir)
VM_PKG_ROOTFS_CACHE ?= $(VM_PKG_BUILD_DIR)/rootfs-base.raw.gz

VM_RECREATE_GOLDEN_ROOTFS ?= false
VM_GOLDEN_HOME := .tmp/vitalserver-vm-golden
VM_GOLDEN_RUNTIME_DIR := $(VM_GOLDEN_HOME)/runtime

VM_INSTALL_SETTINGS ?=

vm-airgap-rootfs: vm-download vm-stage
	@rm -f "$(VM_HOME)/data/run/rootfs-ready"
	@$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-runtime-control \
		--vm-home "$(VM_HOME)" \
		stop >/dev/null 2>&1 || true
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" cloud-init \
		--runtime-dir "$(VM_RUNTIME_DIR)" \
		--bootstrap-script "/mnt/tirosh/deploy/prepare-airgap-rootfs.sh"
	$(MAKE) vm-start-detached
	$(MAKE) vm-wait-rootfs-ready
	$(MAKE) vm-stop
	@printf "Air-gapped rootfs is prepared: %s\n" "$(VM_RUNTIME_DIR)/vm-disk.img"

vm-golden-rootfs:
	@set -e; \
	if [ "$(VM_RECREATE_GOLDEN_ROOTFS)" = "false" ] \
		&& [ -s "$(VM_PKG_ROOTFS_CACHE)" ] \
		&& [ -s "$(VM_GOLDEN_RUNTIME_DIR)/Image" ] \
		&& [ -s "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" ]; then \
		printf "Reusing golden rootfs cache: %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
	else \
		$(MAKE) vm-airgap-rootfs \
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
	fi

vm-nginx-artifact:
	@test -x "$(VM_NGINX_SOURCE_BIN)" || { \
		printf "missing nginx source binary: %s\n" "$(VM_NGINX_SOURCE_BIN)" >&2; \
		printf "Install nginx on the build machine, set VM_NGINX_SOURCE_BIN, or run with VM_NGINX_BIN=/path/to/nginx.\n" >&2; \
		exit 1; \
	}
	@mkdir -p "$(dir $(VM_NGINX_ARTIFACT_BIN))"
	install -m 0755 "$(VM_NGINX_SOURCE_BIN)" "$(VM_NGINX_ARTIFACT_BIN)"
	@"$(VM_NGINX_ARTIFACT_BIN)" -v
	@printf "nginx release artifact is ready: %s\n" "$(VM_NGINX_ARTIFACT_BIN)"

vm-nginx-bundle: $(if $(VM_NGINX_BIN),,vm-nginx-artifact)
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" nginx-bundle \
		--bundle-dir "$(VM_PKG_BUILD_DIR)/nginx-bundle" \
		--binary "$(VM_NGINX_BIN)"

vm-docker-images:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" docker-images \
		--bundle-path "$(call VM_TOML_VALUE,guest.docker_images.bundle_path)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)"

vm-require-release-branch:
	$(VM_BUILD_RUNNER) require-branch --branch "$(VM_RELEASE_BRANCH)"

vm-app:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-app \
		--release-file "$(VM_RELEASE_FILE)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		--sdkroot "$(VM_SDKROOT)"

vm-pkg: vm-golden-rootfs
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

vm-pkg-dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
vm-pkg-dev:
	$(MAKE) vm-pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

vm-pkg-release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
vm-pkg-release: VM_RECREATE_GOLDEN_ROOTFS := true
vm-pkg-release:
	$(MAKE) vm-require-release-branch
	$(MAKE) vm-pkg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_GOLDEN_ROOTFS="$(VM_RECREATE_GOLDEN_ROOTFS)"

vm-dmg: vm-golden-rootfs
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

vm-dmg-dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
vm-dmg-dev:
	$(MAKE) vm-dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

vm-dmg-release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
vm-dmg-release: VM_RECREATE_GOLDEN_ROOTFS := true
vm-dmg-release:
	$(MAKE) vm-require-release-branch
	$(MAKE) vm-dmg VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_GOLDEN_ROOTFS="$(VM_RECREATE_GOLDEN_ROOTFS)"

vm-update-bundle:
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

vm-update-bundle-dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
vm-update-bundle-dev:
	$(MAKE) vm-update-bundle VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

vm-update-bundle-release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
vm-update-bundle-release:
	$(MAKE) vm-require-release-branch
	$(MAKE) vm-update-bundle VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

vm-rootfs-update-bundle: VM_UPDATE_ROOTFS_BASE = $(VM_PKG_ROOTFS_CACHE)
vm-rootfs-update-bundle: VM_UPDATE_BUNDLE_KIND := vm-image-update
vm-rootfs-update-bundle: VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE := true
vm-rootfs-update-bundle:
	$(MAKE) vm-golden-rootfs VM_RELEASE_FILE="$(VM_RELEASE_FILE)"
	$(MAKE) vm-update-bundle \
		VM_RELEASE_FILE="$(VM_RELEASE_FILE)" \
		VM_UPDATE_ROOTFS_BASE="$(VM_UPDATE_ROOTFS_BASE)" \
		VM_UPDATE_BUNDLE_KIND="$(VM_UPDATE_BUNDLE_KIND)" \
		VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE="$(VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE)"

vm-rootfs-update-bundle-dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
vm-rootfs-update-bundle-dev:
	$(MAKE) vm-rootfs-update-bundle VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

vm-rootfs-update-bundle-release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
vm-rootfs-update-bundle-release: VM_RECREATE_GOLDEN_ROOTFS := true
vm-rootfs-update-bundle-release:
	$(MAKE) vm-require-release-branch
	$(MAKE) vm-rootfs-update-bundle VM_RELEASE_FILE="$(VM_RELEASE_FILE)" VM_RECREATE_GOLDEN_ROOTFS="$(VM_RECREATE_GOLDEN_ROOTFS)"

vm-update-bundle-verify:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-update-bundle-verify \
		--release-file "$(VM_RELEASE_FILE)" \
		--bundle-kind "$(VM_UPDATE_BUNDLE_KIND)"

vm-update-bundle-verify-dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
vm-update-bundle-verify-dev:
	$(MAKE) vm-update-bundle-verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

vm-update-bundle-verify-release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
vm-update-bundle-verify-release:
	$(MAKE) vm-require-release-branch
	$(MAKE) vm-update-bundle-verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

vm-rootfs-update-bundle-verify: VM_UPDATE_BUNDLE_KIND := vm-image-update
vm-rootfs-update-bundle-verify: vm-update-bundle-verify

vm-rootfs-update-bundle-verify-dev: VM_RELEASE_FILE := $(VM_DEV_RELEASE_FILE)
vm-rootfs-update-bundle-verify-dev:
	$(MAKE) vm-rootfs-update-bundle-verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

vm-rootfs-update-bundle-verify-release: VM_RELEASE_FILE := $(VM_STABLE_RELEASE_FILE)
vm-rootfs-update-bundle-verify-release:
	$(MAKE) vm-require-release-branch
	$(MAKE) vm-rootfs-update-bundle-verify VM_RELEASE_FILE="$(VM_RELEASE_FILE)"

vm-pkg-clean:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-package-clean \
		--release-file "$(VM_RELEASE_FILE)"

vm-pkg-install:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" macos-package-install \
		--release-file "$(VM_RELEASE_FILE)" \
		--install-settings "$(VM_INSTALL_SETTINGS)"

vm-pkg-uninstall-dev:
	sudo "$(VM_MACOS_RUNTIME_DIR)/Support/Packaging/uninstall-dev.sh"

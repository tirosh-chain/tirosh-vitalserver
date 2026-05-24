.PHONY: vm-nginx-artifact vm-nginx-bundle vm-docker-images vm-pkg vm-pkg-release vm-app vm-dmg vm-dmg-release vm-pkg-clean vm-pkg-install vm-pkg-uninstall-dev vm-update-bundle vm-rootfs-update-bundle vm-update-bundle-verify vm-rootfs-update-bundle-verify
.PHONY: vm-airgap-rootfs vm-golden-rootfs

vm-airgap-rootfs: vm-download vm-stage
	@rm -f "$(VM_ROOTFS_READY_FILE)"
	@VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_RUNTIME_CLI_BIN)" stop >/dev/null 2>&1 || true
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" cloud-init \
		--runtime-dir "$(VM_RUNTIME_DIR)" \
		--bootstrap-script "/mnt/tirosh/deploy/prepare-airgap-rootfs.sh"
	$(MAKE) vm-start-detached
	$(MAKE) vm-wait-rootfs-ready
	$(MAKE) vm-stop
	@printf "Air-gapped rootfs is prepared: %s\n" "$(VM_DISK_IMAGE)"

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
			--source "$(VM_GOLDEN_DISK_IMAGE)" \
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
		--bundle-dir "$(VM_PKG_NGINX_BUNDLE_DIR)" \
		$(if $(VM_NGINX_BIN),--binary "$(VM_NGINX_BIN)") \
		$(if $(VM_NGINX_EXPECTED_VERSION),--expected-version "$(VM_NGINX_EXPECTED_VERSION)")

vm-docker-images:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" docker-images \
		--bundle-path "$(VM_DOCKER_IMAGE_BUNDLE)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)"

vm-app: vm-version-source
	cd "$(VM_MACOS_RUNTIME_DIR)" && env SDKROOT="$(VM_SDKROOT)" CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift build -c release --product VitalServerHelper
	rm -rf "$(VM_APP_BUNDLE)"
	@mkdir -p "$(VM_APP_BUNDLE)/Contents/MacOS" "$(VM_APP_BUNDLE)/Contents/Resources"
	install -m 0755 "$(VM_APP_BIN)" "$(VM_APP_BUNDLE)/Contents/MacOS/$(VM_APP_NAME)"
	install -m 0644 "$(VM_MACOS_RUNTIME_DIR)/Support/App/Info.plist" "$(VM_APP_INFO_PLIST)"
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VM_PRODUCT_VERSION)" "$(VM_APP_INFO_PLIST)"
	install -m 0644 "$(VM_MACOS_RUNTIME_DIR)/Support/App/AppIcon.icns" "$(VM_APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	codesign --force --sign "$(VM_CODESIGN_IDENTITY)" "$(VM_APP_BUNDLE)"
	@printf "VM control app is ready: %s\n" "$(VM_APP_BUNDLE)"

vm-pkg: vm-golden-rootfs
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-pkg \
		--release-file "$(VM_RELEASE_FILE)" \
		--output "$(VM_PKG_OUTPUT)" \
		--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
		--golden-runtime-dir "$(VM_GOLDEN_RUNTIME_DIR)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		$(if $(VM_SDKROOT),--sdkroot "$(VM_SDKROOT)") \
		$(if $(VM_NGINX_BIN),--nginx-binary "$(VM_NGINX_BIN)") \
		$(if $(VM_NGINX_EXPECTED_VERSION),--nginx-expected-version "$(VM_NGINX_EXPECTED_VERSION)")
	@printf "VM package is ready: %s\n" "$(VM_PKG_OUTPUT)"

vm-pkg-release: VM_RECREATE_GOLDEN_ROOTFS := true
vm-pkg-release: vm-pkg

vm-dmg: vm-golden-rootfs
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-dmg \
		--release-file "$(VM_RELEASE_FILE)" \
		--output "$(VM_DMG_OUTPUT)" \
		--rootfs-base "$(VM_PKG_ROOTFS_CACHE)" \
		--golden-runtime-dir "$(VM_GOLDEN_RUNTIME_DIR)" \
		--proxy-port "$(VITALSERVER_PROXY_PORT)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		$(if $(VM_SDKROOT),--sdkroot "$(VM_SDKROOT)") \
		$(if $(VM_NGINX_BIN),--nginx-binary "$(VM_NGINX_BIN)") \
		$(if $(VM_NGINX_EXPECTED_VERSION),--nginx-expected-version "$(VM_NGINX_EXPECTED_VERSION)")
	@printf "VM control app dmg is ready: %s\n" "$(VM_DMG_OUTPUT)"

vm-dmg-release: VM_RECREATE_GOLDEN_ROOTFS := true
vm-dmg-release: vm-dmg

vm-update-bundle:
	$(VM_BUILD_RUNNER) --config "$(VM_BUILD_CONFIG)" release-update-bundle \
		--release-file "$(VM_RELEASE_FILE)" \
		--bundle-name "$(VM_UPDATE_BUNDLE_NAME)" \
		--bundle-kind "$(VM_UPDATE_BUNDLE_KIND)" \
		--target-platform "$(VM_UPDATE_TARGET_PLATFORM)" \
		--requires-two-phase-update "$(VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE)" \
		--output-dir "$(VM_UPDATE_BUNDLE_DIR)" \
		--compression-threads "$(VM_COMPRESSION_THREADS)" \
		--clang-module-cache "$(VM_CLANG_MODULE_CACHE)" \
		--codesign-identity "$(VM_CODESIGN_IDENTITY)" \
		$(if $(VM_SDKROOT),--sdkroot "$(VM_SDKROOT)") \
		$(if $(VM_NGINX_BIN),--nginx-binary "$(VM_NGINX_BIN)") \
		$(if $(VM_NGINX_EXPECTED_VERSION),--nginx-expected-version "$(VM_NGINX_EXPECTED_VERSION)") \
		$(if $(VM_UPDATE_ROOTFS_BASE),--rootfs-base "$(VM_UPDATE_ROOTFS_BASE)") \
		$(foreach migration,$(VM_UPDATE_MIGRATIONS),--migration "$(migration)")
	@printf "VM update bundle is ready: %s\n" "$(VM_UPDATE_BUNDLE_PATH)"

vm-rootfs-update-bundle: VM_UPDATE_ROOTFS_BASE := $(VM_PKG_ROOTFS_CACHE)
vm-rootfs-update-bundle: VM_UPDATE_BUNDLE_KIND := vm-image-update
vm-rootfs-update-bundle: VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE := true
vm-rootfs-update-bundle: vm-golden-rootfs vm-update-bundle

vm-update-bundle-verify:
	$(VM_BUILD_RUNNER) verify-update-bundle "$(VM_UPDATE_BUNDLE_PATH)"

vm-rootfs-update-bundle-verify: VM_UPDATE_BUNDLE_KIND := vm-image-update
vm-rootfs-update-bundle-verify: vm-update-bundle-verify

vm-pkg-clean:
	rm -rf "$(VM_PKG_BUILD_DIR)" "$(VM_PKG_OUTPUT)" "$(VM_APP_BUNDLE)" "$(VM_DMG_OUTPUT)"

vm-pkg-install:
	@test -s "$(VM_PKG_OUTPUT)" || { printf "missing %s. Run: make vm-pkg\n" "$(VM_PKG_OUTPUT)" >&2; exit 1; }
	@if [ -n "$(VM_INSTALL_SETTINGS)" ]; then \
		test -s "$(VM_INSTALL_SETTINGS)" || { printf "missing %s\n" "$(VM_INSTALL_SETTINGS)" >&2; exit 1; }; \
		sudo install -m 0600 "$(VM_INSTALL_SETTINGS)" "$(VM_INSTALL_SETTINGS_PATH)"; \
		printf "installed runtime settings: %s\n" "$(VM_INSTALL_SETTINGS_PATH)"; \
	fi
	sudo installer -pkg "$(VM_PKG_OUTPUT)" -target /

vm-pkg-uninstall-dev:
	sudo "$(VM_PACKAGING_DIR)/uninstall-dev.sh"

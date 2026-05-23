.PHONY: vm-nginx-artifact vm-nginx-bundle vm-docker-images vm-pkg-stage vm-pkg vm-pkg-release vm-app vm-dmg vm-dmg-release vm-pkg-clean vm-pkg-install vm-pkg-uninstall-dev vm-update-artifacts vm-update-bundle vm-rootfs-update-bundle vm-update-bundle-verify
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

vm-pkg-stage: vm-sign vm-app vm-golden-rootfs vm-nginx-bundle vm-docker-images
	@test -s "$(VM_GOLDEN_RUNTIME_DIR)/Image" || { printf "missing %s\n" "$(VM_GOLDEN_RUNTIME_DIR)/Image" >&2; exit 1; }
	@test -s "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" || { printf "missing %s\n" "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" >&2; exit 1; }
	@test -s "$(VM_PKG_ROOTFS_CACHE)" || { printf "missing %s\n" "$(VM_PKG_ROOTFS_CACHE)" >&2; exit 1; }
	rm -rf "$(VM_PKG_ROOT)" "$(VM_PKG_SCRIPTS)"
	@mkdir -p \
		"$(VM_PKG_ROOT)$(VM_INSTALL_APPLICATIONS_DIR)" \
		"$(VM_PKG_ROOT)/usr/local/bin" \
		"$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/runtime" \
		"$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy" \
		"$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/Support/Proxy" \
		"$(VM_PKG_ROOT)$(VM_INSTALL_NGINX_PREFIX)" \
		"$(VM_PKG_ROOT)/Library/LaunchDaemons" \
		"$(VM_PKG_SCRIPTS)"
	codesign --force --sign "$(VM_CODESIGN_IDENTITY)" --entitlements "$(VM_RUNTIME_CLI_ENTITLEMENTS)" "$(VM_RUNTIME_CLI_BIN)"
	install -m 0755 "$(VM_RUNTIME_CLI_BIN)" "$(VM_PKG_ROOT)$(VM_INSTALL_BIN)"
	@codesign -d --entitlements :- "$(VM_PKG_ROOT)$(VM_INSTALL_BIN)" 2>&1 | grep -q "com.apple.security.virtualization" || { \
		printf "packaged vitalserver-vm is missing virtualization entitlement: %s\n" "$(VM_PKG_ROOT)$(VM_INSTALL_BIN)" >&2; \
		exit 1; \
	}
	install -m 0755 "$(VM_PACKAGING_DIR)/proxy-run" "$(VM_PKG_ROOT)$(VM_INSTALL_PROXY_RUN)"
	install -m 0755 "$(VM_PACKAGING_DIR)/uninstall" "$(VM_PKG_ROOT)$(VM_INSTALL_UNINSTALL)"
	rsync -a --delete "$(VM_APP_BUNDLE)/" "$(VM_PKG_ROOT)$(VM_INSTALL_APP_BUNDLE)/"
	rsync -a "$(VM_PKG_NGINX_BUNDLE_DIR)/" "$(VM_PKG_ROOT)$(VM_INSTALL_NGINX_PREFIX)/"
	install -m 0644 "$(VM_GOLDEN_RUNTIME_DIR)/Image" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/runtime/Image"
	install -m 0644 "$(VM_GOLDEN_RUNTIME_DIR)/initrd.img" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/runtime/initrd.img"
	install -m 0644 "$(VM_PKG_ROOTFS_CACHE)" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/runtime/rootfs-base.raw.gz"
	install -m 0644 "infra/macos-nginx/vitalserver.conf.template" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/Support/Proxy/vitalserver.conf.template"
	rsync -a $(VM_RSYNC_EXCLUDES) "$(VM_GUEST_DIR)/" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/"
	@mkdir -p "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/apps/vitalserver" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/vendor/vitalserver" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/docs" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/docker-images"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/docker "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/runtime "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) vendor/vitalserver/vitalserver-old "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/vendor/vitalserver/"
	install -m 0644 docs/openapi.yaml "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/docs/openapi.yaml"
	install -m 0644 "$(VM_DOCKER_IMAGE_BUNDLE)" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/docker-images/vitalserver-images.tar.gz"
	$(VM_BUILD_RUNNER) render-template \
		--template "$(VM_MACOS_RUNTIME_DIR)/launchd/com.tirosh.vitalserver-vm.plist.template" \
		--output "$(VM_PKG_ROOT)/Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist" \
		--var "VITALSERVER_VM_BIN=$(VM_INSTALL_BIN)" \
		--var "VITALSERVER_VM_HOME=$(VM_INSTALL_HOME)" \
		--var "VITALSERVER_RUNTIME_LOGS=$(VM_INSTALL_RUNTIME_LOGS)"
	$(VM_BUILD_RUNNER) render-template \
		--template "$(VM_MACOS_RUNTIME_DIR)/launchd/com.tirosh.vitalserver-proxy.plist.template" \
		--output "$(VM_PKG_ROOT)/Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist" \
		--var "VITALSERVER_PROXY_RUN=$(VM_INSTALL_PROXY_RUN)" \
		--var "VITALSERVER_VM_HOME=$(VM_INSTALL_HOME)" \
		--var "VITALSERVER_RUNTIME_LOGS=$(VM_INSTALL_RUNTIME_LOGS)" \
		--var "VITALSERVER_NGINX_PREFIX=$(VM_INSTALL_NGINX_PREFIX)" \
		--var "VITALSERVER_NGINX_BIN=$(VM_INSTALL_NGINX_BIN)" \
		--var "VITALSERVER_PROXY_PORT=$(VITALSERVER_PROXY_PORT)"
	$(VM_BUILD_RUNNER) render-template \
		--template "$(VM_MACOS_RUNTIME_DIR)/launchd/com.tirosh.vitalserver-watchdog.plist.template" \
		--output "$(VM_PKG_ROOT)/Library/LaunchDaemons/com.tirosh.vitalserver-watchdog.plist" \
		--var "VITALSERVER_VM_BIN=$(VM_INSTALL_BIN)" \
		--var "VITALSERVER_VM_HOME=$(VM_INSTALL_HOME)" \
		--var "VITALSERVER_RUNTIME_LOGS=$(VM_INSTALL_RUNTIME_LOGS)"
	install -m 0755 "$(VM_PACKAGING_DIR)/preinstall" "$(VM_PKG_SCRIPTS)/preinstall"
	install -m 0755 "$(VM_PACKAGING_DIR)/postinstall" "$(VM_PKG_SCRIPTS)/postinstall"
	find "$(VM_PKG_ROOT)" "$(VM_PKG_SCRIPTS)" -name '._*' -delete
	@xattr -rc "$(VM_PKG_ROOT)" 2>/dev/null || true
	@printf "VM package staging root is ready: %s\n" "$(VM_PKG_ROOT)"

vm-pkg: vm-pkg-stage
	@mkdir -p "$(dir $(VM_PKG_OUTPUT))"
	COPYFILE_DISABLE=1 pkgbuild \
		--root "$(VM_PKG_ROOT)" \
		--component-plist "$(VM_PKG_COMPONENT_PLIST)" \
		--scripts "$(VM_PKG_SCRIPTS)" \
		--filter '\.DS_Store$$' \
		--filter '/CVS$$' \
		--filter '/\.svn$$' \
		--filter '.*\._.*' \
		--identifier "$(VM_PKG_IDENTIFIER)" \
		--version "$(VM_PKG_VERSION)" \
		--install-location "/" \
		"$(VM_PKG_OUTPUT)"
	@printf "VM package is ready: %s\n" "$(VM_PKG_OUTPUT)"

vm-pkg-release: VM_RECREATE_GOLDEN_ROOTFS := true
vm-pkg-release: vm-pkg

vm-dmg: vm-pkg
	rm -rf "$(VM_DMG_STAGING)"
	@mkdir -p "$(VM_DMG_STAGING)"
	install -m 0644 "$(VM_PKG_OUTPUT)" "$(VM_DMG_STAGING)/Install Tirosh VitalServer.pkg"
	rm -f "$(VM_DMG_OUTPUT)"
	@mkdir -p "$(dir $(VM_DMG_OUTPUT))"
	hdiutil create \
		-volname "$(VM_APP_NAME)" \
		-srcfolder "$(VM_DMG_STAGING)" \
		-ov \
		-format UDZO \
		"$(VM_DMG_OUTPUT)"
	@printf "VM control app dmg is ready: %s\n" "$(VM_DMG_OUTPUT)"

vm-dmg-release: VM_RECREATE_GOLDEN_ROOTFS := true
vm-dmg-release: vm-dmg

vm-update-artifacts: vm-sign vm-app vm-nginx-bundle vm-docker-images
	rm -rf "$(VM_UPDATE_ARTIFACT_DIR)"
	@mkdir -p "$(VM_UPDATE_ARTIFACT_DIR)/runtime-tools" "$(VM_UPDATE_ARTIFACT_DIR)/deploy"
	tar -czf "$(VM_UPDATE_APP_BUNDLE_ARCHIVE)" -C ".tmp" "$(VM_APP_NAME).app"
	install -m 0755 "$(VM_RUNTIME_CLI_BIN)" "$(VM_UPDATE_ARTIFACT_DIR)/runtime-tools/vitalserver-vm"
	install -m 0755 "$(VM_PACKAGING_DIR)/proxy-run" "$(VM_UPDATE_ARTIFACT_DIR)/runtime-tools/vitalserver-proxy-run"
	install -m 0755 "$(VM_PACKAGING_DIR)/uninstall" "$(VM_UPDATE_ARTIFACT_DIR)/runtime-tools/tirosh-vitalserver-uninstall"
	tar -czf "$(VM_UPDATE_RUNTIME_TOOLS_ARCHIVE)" -C "$(VM_UPDATE_ARTIFACT_DIR)/runtime-tools" vitalserver-vm vitalserver-proxy-run tirosh-vitalserver-uninstall
	@mkdir -p "$(VM_UPDATE_ARTIFACT_DIR)/nginx"
	rsync -a --delete "$(VM_PKG_NGINX_BUNDLE_DIR)/" "$(VM_UPDATE_ARTIFACT_DIR)/nginx/"
	tar -czf "$(VM_UPDATE_NGINX_BUNDLE_ARCHIVE)" -C "$(VM_UPDATE_ARTIFACT_DIR)" nginx
	rsync -a $(VM_RSYNC_EXCLUDES) "$(VM_GUEST_DIR)/" "$(VM_UPDATE_ARTIFACT_DIR)/deploy/"
	@mkdir -p "$(VM_UPDATE_ARTIFACT_DIR)/deploy/apps/vitalserver" "$(VM_UPDATE_ARTIFACT_DIR)/deploy/vendor/vitalserver" "$(VM_UPDATE_ARTIFACT_DIR)/deploy/docs" "$(VM_UPDATE_ARTIFACT_DIR)/deploy/docker-images"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/docker "$(VM_UPDATE_ARTIFACT_DIR)/deploy/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/runtime "$(VM_UPDATE_ARTIFACT_DIR)/deploy/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) vendor/vitalserver/vitalserver-old "$(VM_UPDATE_ARTIFACT_DIR)/deploy/vendor/vitalserver/"
	install -m 0644 docs/openapi.yaml "$(VM_UPDATE_ARTIFACT_DIR)/deploy/docs/openapi.yaml"
	install -m 0644 "$(VM_DOCKER_IMAGE_BUNDLE)" "$(VM_UPDATE_ARTIFACT_DIR)/deploy/docker-images/vitalserver-images.tar.gz"
	tar -czf "$(VM_UPDATE_GUEST_DEPLOY_ARCHIVE)" -C "$(VM_UPDATE_ARTIFACT_DIR)" deploy
	@printf "VM update artifacts are ready: %s\n" "$(VM_UPDATE_ARTIFACT_DIR)"

vm-update-bundle: vm-update-artifacts
	$(VM_BUILD_RUNNER) update-bundle \
		--version "$(VM_UPDATE_BUNDLE_VERSION)" \
		--helper-version "$(VM_PKG_VERSION)" \
		--bundle-kind "$(VM_UPDATE_BUNDLE_KIND)" \
		--target-platform "$(VM_UPDATE_TARGET_PLATFORM)" \
		--min-updater-version "$(VM_UPDATE_MIN_UPDATER_VERSION)" \
		--component "helperUI=$(VM_PKG_VERSION)+macos.1" \
		--component "updater=$(VM_PKG_VERSION)" \
		--component "supervisor=$(VM_PKG_VERSION)" \
		--component "vmDriver=$(VM_PKG_VERSION)+macos.1" \
		--component "serviceStack=$(VM_RELEASE_VITALSERVER_VERSION)-stack.1" \
		--component "vitalServer=$(VM_RELEASE_VITALSERVER_VERSION)" \
		--requires-guest-activation "$(if $(VM_UPDATE_GUEST_DEPLOY),true,false)" \
		--requires-two-phase-update "$(VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE)" \
		--output-dir "$(VM_UPDATE_BUNDLE_DIR)" \
		$(if $(VM_UPDATE_ROOTFS_BASE),--rootfs-base "$(VM_UPDATE_ROOTFS_BASE)") \
		$(if $(VM_UPDATE_APP_BUNDLE),--app-bundle "$(VM_UPDATE_APP_BUNDLE)") \
		$(if $(VM_UPDATE_RUNTIME_TOOLS),--runtime-tools "$(VM_UPDATE_RUNTIME_TOOLS)") \
		$(if $(VM_UPDATE_NGINX_BUNDLE),--nginx-bundle "$(VM_UPDATE_NGINX_BUNDLE)") \
		$(if $(VM_UPDATE_GUEST_DEPLOY),--guest-deploy "$(VM_UPDATE_GUEST_DEPLOY)") \
		$(foreach migration,$(VM_UPDATE_MIGRATIONS),--migration "$(migration)")
	@printf "VM update bundle is ready: %s\n" "$(VM_UPDATE_BUNDLE_PATH)"

vm-rootfs-update-bundle: VM_UPDATE_ROOTFS_BASE := $(VM_PKG_ROOTFS_CACHE)
vm-rootfs-update-bundle: VM_UPDATE_BUNDLE_KIND := vm-image-update
vm-rootfs-update-bundle: VM_UPDATE_REQUIRES_TWO_PHASE_UPDATE := true
vm-rootfs-update-bundle: vm-golden-rootfs vm-update-bundle

vm-update-bundle-verify:
	$(VM_BUILD_RUNNER) verify-update-bundle "$(VM_UPDATE_BUNDLE_PATH)"

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

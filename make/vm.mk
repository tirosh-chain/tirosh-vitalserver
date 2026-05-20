VM_LAUNCHER_DIR ?= apps/vitalserver-vm-launcher
VM_LAUNCHER_BIN ?= $(VM_LAUNCHER_DIR)/.build/release/vitalserver-vm
VM_LAUNCHER_ENTITLEMENTS ?= $(VM_LAUNCHER_DIR)/Entitlements.shared.plist
VM_LAUNCHER_BRIDGED_ENTITLEMENTS ?= $(VM_LAUNCHER_DIR)/Entitlements.plist
VM_CODESIGN_IDENTITY ?= -
VM_BRIDGED_CODESIGN_IDENTITY ?= $(VM_CODESIGN_IDENTITY)
VM_SDKROOT ?= $(firstword $(wildcard /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk) $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null))
VM_CLANG_MODULE_CACHE ?= $(CURDIR)/.tmp/clang-module-cache
VM_HOME ?= $(HOME)/.tirosh/vitalserver-vm
VM_SUPPORT_DIR ?= $(VM_LAUNCHER_DIR)/Support
VM_BUILD_SUPPORT_DIR ?= $(VM_SUPPORT_DIR)/Build
VM_GUEST_DIR ?= $(VM_SUPPORT_DIR)/Guest
VM_PACKAGING_DIR ?= $(VM_SUPPORT_DIR)/Packaging
VM_IMAGE_DIR ?= $(VM_HOME)/images
VM_ROOTFS_SIZE ?= 8G
VM_RECREATE_ROOTFS ?= false
VM_DEPLOY_DIR ?= $(VM_HOME)/data/deploy
VM_RUN_DIR ?= $(VM_HOME)/data/run
VM_IP_FILE ?= $(VM_RUN_DIR)/vm-ip
VM_ROOTFS_READY_FILE ?= $(VM_RUN_DIR)/rootfs-ready
VM_UBUNTU_CONFIG ?= $(VM_BUILD_SUPPORT_DIR)/ubuntu-cloud-image.env
VM_RSYNC_EXCLUDES ?= --exclude .DS_Store --exclude __pycache__
VM_WAIT_TIMEOUT ?= 300
VM_HTTP_WAIT_TIMEOUT ?= 600
VM_PKG_VERSION ?= 0.1.0
VM_PKG_IDENTIFIER ?= com.tirosh.vitalserver.vm
VM_PKG_BUILD_DIR ?= .tmp/vitalserver-vm-pkg
VM_PKG_ROOT ?= $(VM_PKG_BUILD_DIR)/root
VM_PKG_SCRIPTS ?= $(VM_PKG_BUILD_DIR)/scripts
VM_PKG_OUTPUT ?= .tmp/TiroshVitalServerVM-$(VM_PKG_VERSION).pkg
VM_INSTALL_PREFIX ?= /Library/Application Support/TiroshVitalServer
VM_INSTALL_HOME ?= $(VM_INSTALL_PREFIX)/vm
VM_INSTALL_BIN ?= /usr/local/bin/vitalserver-vm
VM_INSTALL_PROXY_RUN ?= /usr/local/bin/vitalserver-proxy-run
VM_INSTALL_UNINSTALL ?= /usr/local/bin/tirosh-vitalserver-uninstall
VM_INSTALL_NGINX_PREFIX ?= $(VM_INSTALL_PREFIX)/nginx
VM_INSTALL_NGINX_BIN ?= $(VM_INSTALL_NGINX_PREFIX)/sbin/nginx
VM_PKG_NGINX_BIN_SOURCE ?= $(NGINX_BIN)
VM_PKG_NGINX_BUNDLE_DIR ?= $(VM_PKG_BUILD_DIR)/nginx-bundle
VM_PKG_ROOTFS_ARCHIVE ?= rootfs.raw.gz
VM_PKG_ROOTFS_CACHE ?= $(VM_PKG_BUILD_DIR)/$(VM_PKG_ROOTFS_ARCHIVE)
VM_DOCKER_IMAGE_BUNDLE ?= $(VM_PKG_BUILD_DIR)/docker-images/vitalserver-images.tar.gz
VM_INSTALLED_IP_FILE ?= $(VM_INSTALL_HOME)/data/run/vm-ip
VM_APP_NAME ?= Tirosh VitalServer Manager
VM_APP_BIN ?= $(VM_LAUNCHER_DIR)/.build/release/TiroshVitalServerApp
VM_APP_BUNDLE ?= .tmp/$(VM_APP_NAME).app
VM_APP_CONTENTS ?= $(VM_APP_BUNDLE)/Contents
VM_APP_RESOURCES ?= $(VM_APP_CONTENTS)/Resources
VM_DMG_OUTPUT ?= .tmp/$(VM_APP_NAME)-$(VM_PKG_VERSION).dmg

.PHONY: vm-up vm-up-bridged vm-down vm-prepare vm-start vm-start-detached vm-start-bridged vm-stop vm-status vm-clean vm-ip vm-wait-ip vm-wait-http vm-wait-rootfs-ready vm-proxy-start vm-health
.PHONY: vm-build vm-sign vm-sign-bridged vm-bridged-preflight vm-init vm-download vm-cloud-init vm-stage vm-interfaces vm-network-shared vm-network-bridged vm-nginx-bundle vm-docker-images vm-pkg-stage vm-pkg vm-app vm-dmg vm-pkg-clean vm-pkg-install vm-pkg-uninstall-dev vm-installed-status vm-installed-health
.PHONY: vm-airgap-rootfs

vm-build:
	cd "$(VM_LAUNCHER_DIR)" && env SDKROOT="$(VM_SDKROOT)" CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift build -c release

vm-sign: vm-build
	codesign --force --sign "$(VM_CODESIGN_IDENTITY)" --entitlements "$(VM_LAUNCHER_ENTITLEMENTS)" "$(VM_LAUNCHER_BIN)"

vm-bridged-preflight:
	@if [ "$(VM_BRIDGED_CODESIGN_IDENTITY)" = "-" ]; then \
		printf "bridged mode requires a real codesign identity with the bridged networking entitlement.\n" >&2; \
		printf "ad-hoc signing can be used for shared/NAT mode only.\n" >&2; \
		printf "Set VM_BRIDGED_CODESIGN_IDENTITY, for example:\n" >&2; \
		printf "  VM_BRIDGED_CODESIGN_IDENTITY='Developer ID Application: ...' make vm-up-bridged\n" >&2; \
		exit 1; \
	fi

vm-sign-bridged: vm-build vm-bridged-preflight
	codesign --force --sign "$(VM_BRIDGED_CODESIGN_IDENTITY)" --entitlements "$(VM_LAUNCHER_BRIDGED_ENTITLEMENTS)" "$(VM_LAUNCHER_BIN)"

vm-init: vm-build
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" init

vm-download:
	VM_IMAGE_DIR="$(VM_IMAGE_DIR)" \
	VM_ROOTFS_SIZE="$(VM_ROOTFS_SIZE)" \
	VM_RECREATE_ROOTFS="$(VM_RECREATE_ROOTFS)" \
	VM_UBUNTU_CONFIG="$(VM_UBUNTU_CONFIG)" \
	"$(VM_BUILD_SUPPORT_DIR)/download-ubuntu.sh"

vm-cloud-init:
	VM_IMAGE_DIR="$(VM_IMAGE_DIR)" \
	"$(VM_BUILD_SUPPORT_DIR)/create-cloud-init.sh"

vm-prepare: vm-download vm-cloud-init vm-stage
	@printf "VM runtime is prepared under %s\n" "$(VM_HOME)"
	@printf "Start it with: make vm-start\n"

vm-up: vm-prepare vm-start-detached vm-wait-ip vm-wait-http vm-proxy-start

vm-up-bridged: vm-bridged-preflight vm-prepare vm-network-bridged vm-start-bridged

vm-down: vm-stop

vm-stage: vm-init
	@printf "Staging Linux guest deployment bundle into %s\n" "$(VM_DEPLOY_DIR)"
	@mkdir -p "$(VM_DEPLOY_DIR)" "$(VM_HOME)/data/vital-files" "$(VM_HOME)/data/vr-release" "$(VM_RUN_DIR)"
	rsync -a $(VM_RSYNC_EXCLUDES) "$(VM_GUEST_DIR)/" "$(VM_DEPLOY_DIR)/"
	@mkdir -p "$(VM_DEPLOY_DIR)/apps/vitalserver" "$(VM_DEPLOY_DIR)/vendor/vitalserver" "$(VM_DEPLOY_DIR)/docs"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/docker "$(VM_DEPLOY_DIR)/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/runtime "$(VM_DEPLOY_DIR)/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) vendor/vitalserver/vitalserver-old "$(VM_DEPLOY_DIR)/vendor/vitalserver/"
	install -m 0644 docs/openapi.yaml "$(VM_DEPLOY_DIR)/docs/openapi.yaml"
	@if [ ! -f "$(VM_DEPLOY_DIR)/.env" ]; then \
		cp "$(VM_DEPLOY_DIR)/vitalserver.env" "$(VM_DEPLOY_DIR)/.env"; \
		printf "created %s\n" "$(VM_DEPLOY_DIR)/.env"; \
	else \
		printf "exists %s\n" "$(VM_DEPLOY_DIR)/.env"; \
	fi
	@printf "cloud-init will run /mnt/tirosh/deploy/bootstrap.sh on first boot\n"

vm-start: vm-sign
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" start

vm-start-detached: vm-sign
	@mkdir -p "$(VM_HOME)/logs" "$(VM_RUN_DIR)"
	@if [ -f "$(VM_HOME)/run/vitalserver-vm.pid" ] && kill -0 "$$(cat "$(VM_HOME)/run/vitalserver-vm.pid")" >/dev/null 2>&1; then \
		printf "VM is already running: pid %s\n" "$$(cat "$(VM_HOME)/run/vitalserver-vm.pid")"; \
	else \
		VITALSERVER_VM_HOME="$(VM_HOME)" VITALSERVER_VM_DETACHED=1 nohup "$(VM_LAUNCHER_BIN)" start >"$(VM_HOME)/logs/launcher.log" 2>&1 & \
		printf "VM launcher started in background. Logs: %s\n" "$(VM_HOME)/logs/launcher.log"; \
	fi

vm-start-bridged: vm-sign-bridged
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" start

vm-stop:
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" stop

vm-status:
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" status

vm-ip:
	@if [ -s "$(VM_IP_FILE)" ]; then \
		cat "$(VM_IP_FILE)"; \
	else \
		printf "VM IP is not available yet: %s\n" "$(VM_IP_FILE)" >&2; \
		exit 1; \
	fi

vm-wait-ip:
	@printf "Waiting for VM IP file: %s\n" "$(VM_IP_FILE)"
	@deadline=$$(( $$(date +%s) + $(VM_WAIT_TIMEOUT) )); \
	while [ $$(date +%s) -lt $$deadline ]; do \
		if [ -s "$(VM_IP_FILE)" ]; then \
			printf "VM IP: %s\n" "$$(cat "$(VM_IP_FILE)")"; \
			exit 0; \
		fi; \
		sleep 2; \
	done; \
	printf "error: timed out waiting for VM IP. Check %s\n" "$(VM_HOME)/logs/launcher.log" >&2; \
	exit 1

vm-wait-http:
	@if [ ! -s "$(VM_IP_FILE)" ]; then \
		printf "VM IP is not available yet: %s\n" "$(VM_IP_FILE)" >&2; \
		exit 1; \
	fi
	@vm_ip="$$(cat "$(VM_IP_FILE)")"; \
	printf "Waiting for VM HTTP: http://%s/\n" "$$vm_ip"; \
	deadline=$$(( $$(date +%s) + $(VM_HTTP_WAIT_TIMEOUT) )); \
	last_code=""; \
	while [ $$(date +%s) -lt $$deadline ]; do \
		code="$$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://$$vm_ip/" 2>/dev/null)" && http_status=0 || http_status=$$?; \
		if [ "$$http_status" -eq 0 ] && [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ]; then \
			printf "VM HTTP ready: http://%s/ -> %s\n" "$$vm_ip" "$$code"; \
			exit 0; \
		fi; \
		last_code="$${code:-curl-error}"; \
		sleep 2; \
	done; \
	printf "error: timed out waiting for VM HTTP: http://%s/ last=%s\n" "$$vm_ip" "$$last_code" >&2; \
	printf "Check guest bootstrap in %s\n" "$(VM_HOME)/logs/launcher.log" >&2; \
	exit 1

vm-wait-rootfs-ready:
	@printf "Waiting for air-gapped rootfs marker: %s\n" "$(VM_ROOTFS_READY_FILE)"
	@deadline=$$(( $$(date +%s) + $(VM_HTTP_WAIT_TIMEOUT) )); \
	while [ $$(date +%s) -lt $$deadline ]; do \
		if [ -s "$(VM_ROOTFS_READY_FILE)" ]; then \
			printf "Air-gapped rootfs marker is ready:\n"; \
			sed 's/^/  /' "$(VM_ROOTFS_READY_FILE)"; \
			exit 0; \
		fi; \
		sleep 3; \
	done; \
	printf "error: timed out waiting for %s\n" "$(VM_ROOTFS_READY_FILE)" >&2; \
	printf "Check VM launcher log: %s\n" "$(VM_HOME)/logs/launcher.log" >&2; \
	exit 1

vm-proxy-start:
	@upstream="$(VM_PROXY_UPSTREAM)"; \
	if [ -z "$$upstream" ]; then \
		if [ ! -s "$(VM_IP_FILE)" ]; then \
			printf "Set VM_PROXY_UPSTREAM or run make vm-wait-ip first.\n" >&2; \
			printf "  VM_PROXY_UPSTREAM=192.168.64.3:80 make vm-proxy-start\n" >&2; \
			exit 1; \
		fi; \
		upstream="$$(cat "$(VM_IP_FILE)"):80"; \
	fi; \
	PROXY_UPSTREAM="$$upstream" $(MAKE) proxy-start

vm-health:
	@status=0; \
	vm_ip=""; \
	printf "VM health\n"; \
	printf "  home: %s\n" "$(VM_HOME)"; \
	if [ -x "$(VM_LAUNCHER_BIN)" ]; then \
		printf "\nVM process:\n"; \
		if ! VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" status; then \
			status=1; \
		fi; \
	else \
		printf "\nVM process:\n"; \
		printf "  missing launcher binary: %s\n" "$(VM_LAUNCHER_BIN)" >&2; \
		printf "  run: make vm-build\n" >&2; \
		status=1; \
	fi; \
	printf "\nVM IP:\n"; \
	if [ -s "$(VM_IP_FILE)" ]; then \
		vm_ip="$$(cat "$(VM_IP_FILE)")"; \
		printf "  %s\n" "$$vm_ip"; \
	else \
		printf "  missing %s\n" "$(VM_IP_FILE)" >&2; \
		status=1; \
	fi; \
	printf "\nGuest HTTP:\n"; \
	if [ -n "$$vm_ip" ]; then \
		if command -v curl >/dev/null 2>&1; then \
			code="$$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://$$vm_ip/" 2>/dev/null)" && http_status=0 || http_status=$$?; \
			if [ "$$http_status" -eq 0 ] && [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ]; then \
				printf "  ok http://%s/ -> %s\n" "$$vm_ip" "$$code"; \
			else \
				printf "  failed http://%s/ -> %s\n" "$$vm_ip" "$${code:-curl-error}" >&2; \
				status=1; \
			fi; \
		else \
			printf "  curl is not installed\n" >&2; \
			status=1; \
		fi; \
	else \
		printf "  skipped because VM IP is unavailable\n" >&2; \
	fi; \
	printf "\nHost proxy:\n"; \
	$(MAKE) --no-print-directory proxy-status || status=1; \
	if command -v lsof >/dev/null 2>&1; then \
		printf "  listeners on port %s:\n" "$(VITALSERVER_PROXY_PORT)"; \
		lsof -nP -iTCP:"$(VITALSERVER_PROXY_PORT)" -sTCP:LISTEN 2>/dev/null | sed 's/^/    /' || true; \
	fi; \
	if command -v curl >/dev/null 2>&1; then \
		code="$$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$(VITALSERVER_PROXY_PORT)/" 2>/dev/null)" && http_status=0 || http_status=$$?; \
		if [ "$$http_status" -eq 0 ] && [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ]; then \
			printf "  ok http://127.0.0.1:%s/ -> %s\n" "$(VITALSERVER_PROXY_PORT)" "$$code"; \
		else \
			printf "  failed http://127.0.0.1:%s/ -> %s\n" "$(VITALSERVER_PROXY_PORT)" "$${code:-curl-error}" >&2; \
			status=1; \
		fi; \
	fi; \
	exit $$status

vm-interfaces: vm-sign-bridged
	"$(VM_LAUNCHER_BIN)" interfaces

vm-network-shared: vm-build
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" network shared

vm-network-bridged: vm-sign-bridged
	@test -n "$(VM_BRIDGED_INTERFACE)" || { printf "Set VM_BRIDGED_INTERFACE. Run: make vm-interfaces\n" >&2; exit 1; }
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" network bridged "$(VM_BRIDGED_INTERFACE)"

vm-clean: vm-build
	VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" clean

vm-airgap-rootfs: vm-download vm-stage
	@rm -f "$(VM_ROOTFS_READY_FILE)"
	@VITALSERVER_VM_HOME="$(VM_HOME)" "$(VM_LAUNCHER_BIN)" stop >/dev/null 2>&1 || true
	VM_IMAGE_DIR="$(VM_IMAGE_DIR)" \
	VM_CLOUD_INIT_BOOTSTRAP_SCRIPT="/mnt/tirosh/deploy/prepare-airgap-rootfs.sh" \
	"$(VM_BUILD_SUPPORT_DIR)/create-cloud-init.sh"
	$(MAKE) vm-start-detached
	$(MAKE) vm-wait-rootfs-ready
	$(MAKE) vm-stop
	@printf "Air-gapped rootfs is prepared: %s\n" "$(VM_IMAGE_DIR)/rootfs.raw"

vm-nginx-bundle:
	@test -x "$(VM_PKG_NGINX_BIN_SOURCE)" || { printf "missing nginx binary for bundle: %s\n" "$(VM_PKG_NGINX_BIN_SOURCE)" >&2; exit 1; }
	"$(VM_PACKAGING_DIR)/bundle-nginx.sh" "$(VM_PKG_NGINX_BIN_SOURCE)" "$(VM_PKG_NGINX_BUNDLE_DIR)"

vm-docker-images:
	VM_DOCKER_IMAGE_BUNDLE="$(VM_DOCKER_IMAGE_BUNDLE)" \
	"$(VM_BUILD_SUPPORT_DIR)/create-docker-image-bundle.sh"

vm-pkg-stage: vm-sign vm-download vm-nginx-bundle vm-docker-images
	@test -s "$(VM_IMAGE_DIR)/Image" || { printf "missing %s\n" "$(VM_IMAGE_DIR)/Image" >&2; exit 1; }
	@test -s "$(VM_IMAGE_DIR)/initrd.img" || { printf "missing %s\n" "$(VM_IMAGE_DIR)/initrd.img" >&2; exit 1; }
	@test -s "$(VM_IMAGE_DIR)/rootfs.raw" || { printf "missing %s\n" "$(VM_IMAGE_DIR)/rootfs.raw" >&2; exit 1; }
	rm -rf "$(VM_PKG_ROOT)" "$(VM_PKG_SCRIPTS)"
	@mkdir -p \
		"$(VM_PKG_ROOT)/usr/local/bin" \
		"$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/images" \
		"$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy" \
		"$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/Support/Build" \
		"$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/Support/Proxy" \
		"$(VM_PKG_ROOT)$(VM_INSTALL_NGINX_PREFIX)" \
		"$(VM_PKG_ROOT)/Library/LaunchDaemons" \
		"$(VM_PKG_SCRIPTS)"
	install -m 0755 "$(VM_LAUNCHER_BIN)" "$(VM_PKG_ROOT)$(VM_INSTALL_BIN)"
	install -m 0755 "$(VM_PACKAGING_DIR)/proxy-run" "$(VM_PKG_ROOT)$(VM_INSTALL_PROXY_RUN)"
	install -m 0755 "$(VM_PACKAGING_DIR)/uninstall" "$(VM_PKG_ROOT)$(VM_INSTALL_UNINSTALL)"
	rsync -a "$(VM_PKG_NGINX_BUNDLE_DIR)/" "$(VM_PKG_ROOT)$(VM_INSTALL_NGINX_PREFIX)/"
	install -m 0644 "$(VM_IMAGE_DIR)/Image" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/images/Image"
	install -m 0644 "$(VM_IMAGE_DIR)/initrd.img" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/images/initrd.img"
	@if [ -s "$(VM_PKG_ROOTFS_CACHE)" ] && [ "$(VM_PKG_ROOTFS_CACHE)" -nt "$(VM_IMAGE_DIR)/rootfs.raw" ]; then \
		printf "reusing cached %s\n" "$(VM_PKG_ROOTFS_CACHE)"; \
	else \
		printf "compressing %s -> %s\n" "$(VM_IMAGE_DIR)/rootfs.raw" "$(VM_PKG_ROOTFS_CACHE)"; \
		mkdir -p "$(dir $(VM_PKG_ROOTFS_CACHE))"; \
		gzip -c "$(VM_IMAGE_DIR)/rootfs.raw" > "$(VM_PKG_ROOTFS_CACHE).tmp"; \
		mv "$(VM_PKG_ROOTFS_CACHE).tmp" "$(VM_PKG_ROOTFS_CACHE)"; \
	fi
	install -m 0644 "$(VM_PKG_ROOTFS_CACHE)" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/images/$(VM_PKG_ROOTFS_ARCHIVE)"
	install -m 0755 "$(VM_BUILD_SUPPORT_DIR)/create-cloud-init.sh" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/Support/Build/create-cloud-init.sh"
	install -m 0644 "infra/macos-nginx/vitalserver.conf.template" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/Support/Proxy/vitalserver.conf.template"
	rsync -a $(VM_RSYNC_EXCLUDES) "$(VM_GUEST_DIR)/" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/"
	@mkdir -p "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/apps/vitalserver" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/vendor/vitalserver" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/docs" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/docker-images"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/docker "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) apps/vitalserver/runtime "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/apps/vitalserver/"
	rsync -a --delete $(VM_RSYNC_EXCLUDES) vendor/vitalserver/vitalserver-old "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/vendor/vitalserver/"
	install -m 0644 docs/openapi.yaml "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/docs/openapi.yaml"
	install -m 0644 "$(VM_DOCKER_IMAGE_BUNDLE)" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/docker-images/vitalserver-images.tar.gz"
	cp "$(VM_GUEST_DIR)/vitalserver.env" "$(VM_PKG_ROOT)$(VM_INSTALL_HOME)/data/deploy/.env"
	@VITALSERVER_VM_BIN="$(VM_INSTALL_BIN)" \
	VITALSERVER_VM_HOME="$(VM_INSTALL_HOME)" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("$(VM_LAUNCHER_DIR)/launchd/com.tirosh.vitalserver-vm.plist.template"); s=p.read_text(); s=s.replace("$${VITALSERVER_VM_BIN}", os.environ["VITALSERVER_VM_BIN"]).replace("$${VITALSERVER_VM_HOME}", os.environ["VITALSERVER_VM_HOME"]); pathlib.Path("$(VM_PKG_ROOT)/Library/LaunchDaemons/com.tirosh.vitalserver-vm.plist").write_text(s)'
	@VITALSERVER_PROXY_RUN="$(VM_INSTALL_PROXY_RUN)" \
	VITALSERVER_VM_HOME="$(VM_INSTALL_HOME)" \
	VITALSERVER_NGINX_PREFIX="$(VM_INSTALL_NGINX_PREFIX)" \
	VITALSERVER_NGINX_BIN="$(VM_INSTALL_NGINX_BIN)" \
	VITALSERVER_PROXY_PORT="$(VITALSERVER_PROXY_PORT)" \
	"$(PYTHON)" -c 'import os, pathlib; p=pathlib.Path("$(VM_LAUNCHER_DIR)/launchd/com.tirosh.vitalserver-proxy.plist.template"); s=p.read_text(); keys=("VITALSERVER_PROXY_RUN", "VITALSERVER_VM_HOME", "VITALSERVER_NGINX_PREFIX", "VITALSERVER_NGINX_BIN", "VITALSERVER_PROXY_PORT"); [(s := s.replace("$${" + k + "}", os.environ[k])) for k in keys]; pathlib.Path("$(VM_PKG_ROOT)/Library/LaunchDaemons/com.tirosh.vitalserver-proxy.plist").write_text(s)'
	install -m 0755 "$(VM_PACKAGING_DIR)/preinstall" "$(VM_PKG_SCRIPTS)/preinstall"
	install -m 0755 "$(VM_PACKAGING_DIR)/postinstall" "$(VM_PKG_SCRIPTS)/postinstall"
	@xattr -rc "$(VM_PKG_ROOT)" 2>/dev/null || true
	@printf "VM package staging root is ready: %s\n" "$(VM_PKG_ROOT)"

vm-pkg: vm-pkg-stage
	@mkdir -p "$(dir $(VM_PKG_OUTPUT))"
	COPYFILE_DISABLE=1 pkgbuild \
		--root "$(VM_PKG_ROOT)" \
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

vm-app: vm-pkg
	cd "$(VM_LAUNCHER_DIR)" && env SDKROOT="$(VM_SDKROOT)" CLANG_MODULE_CACHE_PATH="$(VM_CLANG_MODULE_CACHE)" swift build -c release --product TiroshVitalServerApp
	rm -rf "$(VM_APP_BUNDLE)"
	@mkdir -p "$(VM_APP_CONTENTS)/MacOS" "$(VM_APP_RESOURCES)"
	install -m 0755 "$(VM_APP_BIN)" "$(VM_APP_CONTENTS)/MacOS/$(VM_APP_NAME)"
	install -m 0644 "$(VM_LAUNCHER_DIR)/Support/App/Info.plist" "$(VM_APP_CONTENTS)/Info.plist"
	install -m 0644 "$(VM_LAUNCHER_DIR)/Support/App/AppIcon.icns" "$(VM_APP_RESOURCES)/AppIcon.icns"
	install -m 0644 "$(VM_PKG_OUTPUT)" "$(VM_APP_RESOURCES)/TiroshVitalServerVM.pkg"
	install -m 0755 "$(VM_PACKAGING_DIR)/uninstall" "$(VM_APP_RESOURCES)/tirosh-vitalserver-uninstall"
	codesign --force --sign "$(VM_CODESIGN_IDENTITY)" "$(VM_APP_BUNDLE)"
	@printf "VM control app is ready: %s\n" "$(VM_APP_BUNDLE)"

vm-dmg: vm-app
	rm -f "$(VM_DMG_OUTPUT)"
	hdiutil create \
		-volname "$(VM_APP_NAME)" \
		-srcfolder "$(VM_APP_BUNDLE)" \
		-ov \
		-format UDZO \
		"$(VM_DMG_OUTPUT)"
	@printf "VM control app dmg is ready: %s\n" "$(VM_DMG_OUTPUT)"

vm-pkg-clean:
	rm -rf "$(VM_PKG_BUILD_DIR)" "$(VM_PKG_OUTPUT)" "$(VM_APP_BUNDLE)" "$(VM_DMG_OUTPUT)"

vm-pkg-install:
	@test -s "$(VM_PKG_OUTPUT)" || { printf "missing %s. Run: make vm-pkg\n" "$(VM_PKG_OUTPUT)" >&2; exit 1; }
	sudo installer -pkg "$(VM_PKG_OUTPUT)" -target /

vm-pkg-uninstall-dev:
	sudo "$(VM_PACKAGING_DIR)/uninstall-dev.sh"

vm-installed-status:
	@printf "Installed VM runtime\n"
	@test -x "$(VM_INSTALL_BIN)" && printf "  launcher: %s\n" "$(VM_INSTALL_BIN)" || printf "  missing launcher: %s\n" "$(VM_INSTALL_BIN)"
	@test -x "$(VM_INSTALL_PROXY_RUN)" && printf "  proxy runner: %s\n" "$(VM_INSTALL_PROXY_RUN)" || printf "  missing proxy runner: %s\n" "$(VM_INSTALL_PROXY_RUN)"
	@test -x "$(VM_INSTALL_UNINSTALL)" && printf "  uninstaller: %s\n" "$(VM_INSTALL_UNINSTALL)" || printf "  missing uninstaller: %s\n" "$(VM_INSTALL_UNINSTALL)"
	@test -x "$(VM_INSTALL_NGINX_BIN)" && printf "  nginx: %s\n" "$(VM_INSTALL_NGINX_BIN)" || printf "  missing nginx: %s\n" "$(VM_INSTALL_NGINX_BIN)"
	@launchctl print system/com.tirosh.vitalserver-vm >/dev/null 2>&1 && printf "  launchd vm: loaded\n" || printf "  launchd vm: not loaded\n"
	@launchctl print system/com.tirosh.vitalserver-proxy >/dev/null 2>&1 && printf "  launchd proxy: loaded\n" || printf "  launchd proxy: not loaded\n"
	@if [ -s "$(VM_INSTALLED_IP_FILE)" ]; then \
		printf "  vm ip: %s\n" "$$(cat "$(VM_INSTALLED_IP_FILE)")"; \
	else \
		printf "  vm ip: waiting for %s\n" "$(VM_INSTALLED_IP_FILE)"; \
	fi

vm-installed-health: vm-installed-status
	@status=0; \
	if [ -s "$(VM_INSTALLED_IP_FILE)" ]; then \
		vm_ip="$$(cat "$(VM_INSTALLED_IP_FILE)")"; \
		code="$$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://$$vm_ip/" 2>/dev/null)" && http_status=0 || http_status=$$?; \
		if [ "$$http_status" -eq 0 ] && [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ]; then \
			printf "  guest http: ok http://%s/ -> %s\n" "$$vm_ip" "$$code"; \
		else \
			printf "  guest http: failed http://%s/ -> %s\n" "$$vm_ip" "$${code:-curl-error}" >&2; \
			status=1; \
		fi; \
	else \
		status=1; \
	fi; \
	code="$$(curl -sS -I -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$(VITALSERVER_PROXY_PORT)/" 2>/dev/null)" && http_status=0 || http_status=$$?; \
	if [ "$$http_status" -eq 0 ] && [ "$$code" -ge 200 ] && [ "$$code" -lt 400 ]; then \
		printf "  host proxy: ok http://127.0.0.1:%s/ -> %s\n" "$(VITALSERVER_PROXY_PORT)" "$$code"; \
	else \
		printf "  host proxy: failed http://127.0.0.1:%s/ -> %s\n" "$(VITALSERVER_PROXY_PORT)" "$${code:-curl-error}" >&2; \
		status=1; \
	fi; \
	exit $$status

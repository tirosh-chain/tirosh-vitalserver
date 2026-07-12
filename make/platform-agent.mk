PLATFORM_AGENT_DIR ?= apps/vitalserver-platform-agent
PLATFORM_AGENT_OUT ?= .tmp/platform-agent
GO ?= go

LINUX_GUEST_RUNTIME_WHEELHOUSE := $(PLATFORM_AGENT_OUT)/guest-runtime-wheelhouse-linux-amd64

.PHONY: platform-agent/test platform-agent/package-test platform-agent/build/linux platform-agent/build/linux-provider platform-agent/build/linux-guest-wheelhouse platform-agent/build/windows platform-agent/build/windows-provider platform-agent/build/hyperv-image platform-agent/package/linux platform-agent/package/windows-acceptance-candidate platform-agent/package/windows platform-agent/proof

platform-agent/test:
	cd "$(PLATFORM_AGENT_DIR)" && $(GO) test -mod=vendor ./...

platform-agent/package-test:
	sh -n "$(PLATFORM_AGENT_DIR)/packaging/linux/install.sh"
	bash -n "$(PLATFORM_AGENT_DIR)/packaging/windows/hyperv-guest/bootstrap.sh"
	uv run pytest \
		packages/vitalserver-devtools/tests/unit/test_linux_runtime_bundle.py \
		packages/vitalserver-devtools/tests/unit/test_linux_installed_acceptance.py \
		packages/vitalserver-devtools/tests/unit/test_linux_support_export.py \
		packages/vitalserver-devtools/tests/unit/test_update_trust_catalog.py \
		packages/vitalserver-devtools/tests/unit/test_hyperv_guest_payload.py \
		packages/vitalserver-devtools/tests/unit/test_hyperv_image_bundle.py \
		packages/vitalserver-devtools/tests/unit/test_hyperv_seed.py \
		packages/vitalserver-devtools/tests/unit/test_windows_hyperv_packaging.py \
		packages/vitalserver-devtools/tests/unit/test_windows_runtime_bundle.py \
		packages/vitalserver-devtools/tests/unit/test_windows_runtime_v2_acceptance_verifier.py \
		-q

platform-agent/build/linux:
	mkdir -p "$(PLATFORM_AGENT_OUT)"
	cd "$(PLATFORM_AGENT_DIR)" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build -mod=vendor -trimpath -o "$(abspath $(PLATFORM_AGENT_OUT))/vitalserver-platform-agent-linux-amd64" ./cmd/vitalserver-platform-agent

platform-agent/build/linux-provider:
	mkdir -p "$(PLATFORM_AGENT_OUT)"
	cd "$(PLATFORM_AGENT_DIR)" && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build -mod=vendor -trimpath -o "$(abspath $(PLATFORM_AGENT_OUT))/vitalserver-runtime-provider-linux-amd64" ./cmd/vitalserver-runtime-provider

platform-agent/build/linux-guest-wheelhouse:
	mkdir -p "$(PLATFORM_AGENT_OUT)"
	rm -rf "$(LINUX_GUEST_RUNTIME_WHEELHOUSE)"
	uv run python scripts/stage_guest_runtime_wheelhouse.py \
		--project "packages/vitalserver-guest-tools" \
		--target linux-amd64 \
		--output "$(LINUX_GUEST_RUNTIME_WHEELHOUSE)"

platform-agent/build/windows:
	mkdir -p "$(PLATFORM_AGENT_OUT)"
	cd "$(PLATFORM_AGENT_DIR)" && CGO_ENABLED=0 GOOS=windows GOARCH=amd64 $(GO) build -mod=vendor -trimpath -o "$(abspath $(PLATFORM_AGENT_OUT))/vitalserver-platform-agent-windows-amd64.exe" ./cmd/vitalserver-platform-agent

platform-agent/build/windows-provider:
	mkdir -p "$(PLATFORM_AGENT_OUT)"
	cd "$(PLATFORM_AGENT_DIR)" && CGO_ENABLED=0 GOOS=windows GOARCH=amd64 $(GO) build -mod=vendor -trimpath -o "$(abspath $(PLATFORM_AGENT_OUT))/vitalserver-hyperv-runtime-provider-windows-amd64.exe" ./cmd/vitalserver-hyperv-runtime-provider

platform-agent/build/hyperv-image:
	@test -n "$(HYPERV_SYSTEM_RAW)" || (echo "HYPERV_SYSTEM_RAW is required" >&2; exit 2)
	@test -n "$(HYPERV_RUNTIME_DATA_RAW)" || (echo "HYPERV_RUNTIME_DATA_RAW is required" >&2; exit 2)
	@test -n "$(HYPERV_SEED_ISO)" || (echo "HYPERV_SEED_ISO is required" >&2; exit 2)
	@test -n "$(HYPERV_ROOTFS_PROOF)" || (echo "HYPERV_ROOTFS_PROOF is required" >&2; exit 2)
	@test -n "$(QEMU_IMG)" || (echo "QEMU_IMG is required" >&2; exit 2)
	uv run python scripts/build_hyperv_image_bundle.py \
		--system-raw "$(HYPERV_SYSTEM_RAW)" \
		--runtime-data-raw "$(HYPERV_RUNTIME_DATA_RAW)" \
		--seed-iso "$(HYPERV_SEED_ISO)" \
		--rootfs-proof "$(HYPERV_ROOTFS_PROOF)" \
		--guest-address "$(if $(HYPERV_GUEST_ADDRESS),$(HYPERV_GUEST_ADDRESS),172.24.0.2)" \
		--qemu-img "$(QEMU_IMG)" \
		--output-directory "$(PLATFORM_AGENT_OUT)/hyperv-image"

platform-agent/package/linux: platform-agent/build/linux platform-agent/build/linux-provider platform-agent/build/linux-guest-wheelhouse pwa/build
	@test -n "$(LINUX_PLATFORM_VERSION)" || (echo "LINUX_PLATFORM_VERSION is required" >&2; exit 2)
	@test -n "$(LINUX_RUNTIME_BUNDLE_VERSION)" || (echo "LINUX_RUNTIME_BUNDLE_VERSION is required" >&2; exit 2)
	@test -n "$(LINUX_RUNTIME_BUNDLE_DIR)" || (echo "LINUX_RUNTIME_BUNDLE_DIR is required" >&2; exit 2)
	@test -n "$(LINUX_RUNTIME_IMAGES_ARCHIVE)" || (echo "LINUX_RUNTIME_IMAGES_ARCHIVE is required" >&2; exit 2)
	uv run python scripts/build_linux_runtime_bundle.py \
		--platform-version "$(LINUX_PLATFORM_VERSION)" \
		--runtime-bundle-version "$(LINUX_RUNTIME_BUNDLE_VERSION)" \
		--agent-binary "$(PLATFORM_AGENT_OUT)/vitalserver-platform-agent-linux-amd64" \
		--provider-binary "$(PLATFORM_AGENT_OUT)/vitalserver-runtime-provider-linux-amd64" \
		--runtime-controller-wheelhouse "$(LINUX_GUEST_RUNTIME_WHEELHOUSE)" \
		--pwa-directory "apps/vitalserver-runtime-pwa/dist" \
		--runtime-bundle-directory "$(LINUX_RUNTIME_BUNDLE_DIR)" \
		--images-archive "$(LINUX_RUNTIME_IMAGES_ARCHIVE)" \
		--output "$(PLATFORM_AGENT_OUT)/VitalServer-Linux-$(LINUX_PLATFORM_VERSION)-amd64.tar.gz"

platform-agent/package/windows-acceptance-candidate: platform-agent/build/windows platform-agent/build/windows-provider pwa/build
	@test -n "$(WINDOWS_PLATFORM_VERSION)" || (echo "WINDOWS_PLATFORM_VERSION is required" >&2; exit 2)
	@test -n "$(WINDOWS_RUNTIME_BUNDLE_VERSION)" || (echo "WINDOWS_RUNTIME_BUNDLE_VERSION is required" >&2; exit 2)
	@test -n "$(WINDOWS_HYPERV_IMAGE_DIR)" || (echo "WINDOWS_HYPERV_IMAGE_DIR is required" >&2; exit 2)
	uv run python scripts/build_windows_runtime_bundle.py \
		--platform-version "$(WINDOWS_PLATFORM_VERSION)" \
		--runtime-bundle-version "$(WINDOWS_RUNTIME_BUNDLE_VERSION)" \
		--agent-binary "$(PLATFORM_AGENT_OUT)/vitalserver-platform-agent-windows-amd64.exe" \
		--provider-binary "$(PLATFORM_AGENT_OUT)/vitalserver-hyperv-runtime-provider-windows-amd64.exe" \
		--pwa-directory "apps/vitalserver-runtime-pwa/dist" \
		--hyperv-image-directory "$(WINDOWS_HYPERV_IMAGE_DIR)" \
		--acceptance-candidate \
		--output "$(PLATFORM_AGENT_OUT)/VitalServer-Windows-$(WINDOWS_PLATFORM_VERSION)-acceptance-candidate-amd64.zip"

platform-agent/package/windows: platform-agent/build/windows platform-agent/build/windows-provider pwa/build
	@test -n "$(WINDOWS_PLATFORM_VERSION)" || (echo "WINDOWS_PLATFORM_VERSION is required" >&2; exit 2)
	@test -n "$(WINDOWS_RUNTIME_BUNDLE_VERSION)" || (echo "WINDOWS_RUNTIME_BUNDLE_VERSION is required" >&2; exit 2)
	@test -n "$(WINDOWS_HYPERV_IMAGE_DIR)" || (echo "WINDOWS_HYPERV_IMAGE_DIR is required" >&2; exit 2)
	@test -n "$(WINDOWS_HYPERV_ACCEPTANCE_MANIFEST)" || (echo "WINDOWS_HYPERV_ACCEPTANCE_MANIFEST is required" >&2; exit 2)
	uv run python scripts/build_windows_runtime_bundle.py \
		--platform-version "$(WINDOWS_PLATFORM_VERSION)" \
		--runtime-bundle-version "$(WINDOWS_RUNTIME_BUNDLE_VERSION)" \
		--agent-binary "$(PLATFORM_AGENT_OUT)/vitalserver-platform-agent-windows-amd64.exe" \
		--provider-binary "$(PLATFORM_AGENT_OUT)/vitalserver-hyperv-runtime-provider-windows-amd64.exe" \
		--pwa-directory "apps/vitalserver-runtime-pwa/dist" \
		--hyperv-image-directory "$(WINDOWS_HYPERV_IMAGE_DIR)" \
		--acceptance-manifest "$(WINDOWS_HYPERV_ACCEPTANCE_MANIFEST)" \
		--output "$(PLATFORM_AGENT_OUT)/VitalServer-Windows-$(WINDOWS_PLATFORM_VERSION)-amd64.zip"

platform-agent/proof/windows-lifecycle:
	@test -n "$(WINDOWS_SEALED_BUNDLE)" || (echo "WINDOWS_SEALED_BUNDLE is required" >&2; exit 2)
	@test -n "$(WINDOWS_CLEAN_HOST_ACCEPTANCE)" || (echo "WINDOWS_CLEAN_HOST_ACCEPTANCE is required" >&2; exit 2)
	@test -n "$(WINDOWS_REBOOT_PROOF)" || (echo "WINDOWS_REBOOT_PROOF is required" >&2; exit 2)
	@test -n "$(WINDOWS_REBOOT_RUNTIME_ACCEPTANCE)" || (echo "WINDOWS_REBOOT_RUNTIME_ACCEPTANCE is required" >&2; exit 2)
	@test -n "$(WINDOWS_UPDATE_BUNDLE)" || (echo "WINDOWS_UPDATE_BUNDLE is required" >&2; exit 2)
	@test -n "$(WINDOWS_UPDATE_ROLLBACK_PROOF)" || (echo "WINDOWS_UPDATE_ROLLBACK_PROOF is required" >&2; exit 2)
	@test -n "$(WINDOWS_UNINSTALL_REINSTALL_PROOF)" || (echo "WINDOWS_UNINSTALL_REINSTALL_PROOF is required" >&2; exit 2)
	@test -n "$(WINDOWS_CLEAN_UNINSTALL_PROOF)" || (echo "WINDOWS_CLEAN_UNINSTALL_PROOF is required" >&2; exit 2)
	@test -n "$(WINDOWS_LIFECYCLE_ACCEPTANCE_OUT)" || (echo "WINDOWS_LIFECYCLE_ACCEPTANCE_OUT is required" >&2; exit 2)
	uv run python scripts/verify_windows_runtime_v2_acceptance.py \
		--sealed-bundle "$(WINDOWS_SEALED_BUNDLE)" \
		--clean-host-acceptance "$(WINDOWS_CLEAN_HOST_ACCEPTANCE)" \
		--reboot-proof "$(WINDOWS_REBOOT_PROOF)" \
		--reboot-runtime-acceptance "$(WINDOWS_REBOOT_RUNTIME_ACCEPTANCE)" \
		--update-bundle "$(WINDOWS_UPDATE_BUNDLE)" \
		--update-rollback-proof "$(WINDOWS_UPDATE_ROLLBACK_PROOF)" \
		--uninstall-reinstall-proof "$(WINDOWS_UNINSTALL_REINSTALL_PROOF)" \
		--clean-uninstall-proof "$(WINDOWS_CLEAN_UNINSTALL_PROOF)" \
		--output "$(WINDOWS_LIFECYCLE_ACCEPTANCE_OUT)"

platform-agent/proof: platform-agent/test platform-agent/package-test platform-agent/build/linux platform-agent/build/linux-provider platform-agent/build/windows platform-agent/build/windows-provider

from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
PACKAGE_MAKEFILE = ROOT / "make/vm/package.mk"
RUNTIME_MAKEFILE = ROOT / "make/vm/runtime.mk"
ROOT_MAKEFILE = ROOT / "Makefile"


def test_dmg_delivery_targets_keep_the_field_proof_order() -> None:
    package_makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")

    for target in ("internal/vm/dmg/dev", "internal/vm/dmg/release"):
        recipe = target_recipe(package_makefile, target)
        assert_in_order(
            recipe,
            (
                f"$(MAKE) {target}/review",
                f"$(MAKE) {target}/compile",
                f"$(MAKE) {target}/artifact-verify",
                f"$(MAKE) {target}/runtime-smoke",
            ),
        )


def test_dmg_compile_is_clean_and_cached_target_is_not_a_field_gate() -> None:
    package_makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")

    for target in ("internal/vm/dmg/dev/compile", "internal/vm/dmg/release/compile"):
        assert "VM_RECREATE_ROOTFS=true" in target_recipe(package_makefile, target)

    cached_recipe = target_recipe(package_makefile, "internal/vm/dmg/dev/cached")
    assert "VM_RECREATE_ROOTFS=true" not in cached_recipe
    assert "$(MAKE) internal/vm/dmg VM_RELEASE_FILE=\"$(VM_RELEASE_FILE)\"" in (
        cached_recipe
    )


def test_package_environment_and_pwa_fail_before_rootfs_compile() -> None:
    makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")

    assert (
        "internal/vm/pkg: internal/vm/release-contract "
        "internal/vm/pkg/environment-preflight pwa/build internal/vm/golden-rootfs"
    ) in makefile
    assert (
        "internal/vm/dmg: internal/vm/release-contract "
        "internal/vm/dmg/environment-preflight pwa/build internal/vm/golden-rootfs"
    ) in makefile


def test_package_delivery_requires_the_release_owned_bootstrap_trust_store() -> None:
    makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")

    for target in (
        "internal/vm/pkg/environment-preflight",
        "internal/vm/dmg/environment-preflight",
        "internal/vm/dmg/artifact-verify",
    ):
        recipe = target_recipe(makefile, target)
        assert "VM_UPDATE_BOOTSTRAP_TRUST_STORE is required" in recipe
        assert (
            '--update-bootstrap-trust-store "$(VM_UPDATE_BOOTSTRAP_TRUST_STORE)"'
            in recipe
        )


def test_stable_update_uses_the_helper_host_release_contract_only() -> None:
    makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")
    artifact_recipe = target_recipe(
        makefile,
        "internal/vm/update/host-platform-artifact",
    )
    release_recipe = target_recipe(makefile, "internal/vm/update")

    assert "helper-host-platform-release-archive" in artifact_recipe
    assert "host-platform-release-archive-composer" not in makefile
    assert "runtime-platform/tooling" not in artifact_recipe
    assert (
        "application/vnd.tirosh.vitalserver-helper."
        "host-platform-release+tar+gzip"
    ) in makefile
    assert (
        '--host-platform-artifact-media-type '
        '"$(VM_UPDATE_HELPER_HOST_PLATFORM_MEDIA_TYPE)"'
    ) in release_recipe

    for target in (
        "internal/vm/pkg",
        "internal/vm/dmg",
    ):
        assert (
            '--update-bootstrap-trust-store "$(VM_UPDATE_BOOTSTRAP_TRUST_STORE)"'
            in target_recipe(makefile, target)
        )


def test_rootfs_cache_miss_recreates_the_base_disk() -> None:
    recipe = target_recipe(
        PACKAGE_MAKEFILE.read_text(encoding="utf-8"),
        "internal/vm/golden-rootfs",
    )
    airgap_rootfs_call = recipe.index("$(MAKE) internal/vm/airgap-rootfs")
    fresh_disk_flag = recipe.index("VM_RECREATE_ROOTFS=true")

    assert airgap_rootfs_call < fresh_disk_flag


def test_clean_rootfs_compile_reuses_only_verified_apt_prepared_seed() -> None:
    makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")
    recipe = target_recipe(makefile, "internal/vm/golden-rootfs")

    assert "VM_PKG_APT_ROOTFS_CONTRACT_VERSION := 1" in makefile
    assert "rootfs-apt-packages.txt" in makefile
    assert "rootfs-apt-cache-contract.txt" in makefile
    apt_contract_inputs = makefile.split(
        "VM_PKG_APT_ROOTFS_CONTRACT_INPUTS :=",
        maxsplit=1,
    )[1].split("VM_PKG_APT_ROOTFS_CONTRACT_FINGERPRINT", maxsplit=1)[0]
    assert "prepare-airgap-rootfs.sh" not in apt_contract_inputs
    assert "shasum -a 256 -c" in recipe
    assert 'VM_ROOTFS_SEED="$${apt_rootfs_seed}"' in recipe
    assert "Published verified APT-prepared rootfs cache" in recipe


def test_rootfs_seed_is_restored_after_fresh_ubuntu_disk_creation() -> None:
    recipe = target_recipe(
        RUNTIME_MAKEFILE.read_text(encoding="utf-8"),
        "internal/vm/download",
    )

    assert_in_order(
        recipe,
        (
            'ubuntu \\\n--runtime-dir "$(VM_RUNTIME_DIR)"',
            'gzip -dc "$(VM_ROOTFS_SEED)"',
            'qemu-img check -f raw',
            'mv "$${seed_tmp}" "$(VM_RUNTIME_DIR)/vm-disk.img"',
        ),
    )


def test_airgap_rootfs_waits_for_launcher_exit_before_mutating_runtime_files() -> None:
    recipe = target_recipe(
        PACKAGE_MAKEFILE.read_text(encoding="utf-8"),
        "internal/vm/airgap-rootfs",
    )

    stop_request = "macos-runtime-control"
    shutdown_wait = "macos-runtime-wait-stopped"
    no_running_guard = "macos-runtime-require-no-running"

    first_stop = recipe.index(stop_request)
    first_wait = recipe.index(shutdown_wait, first_stop)
    first_guard = recipe.index(no_running_guard, first_wait)
    second_stop = recipe.index(stop_request, first_guard)
    second_wait = recipe.index(shutdown_wait, second_stop)
    second_guard = recipe.index(no_running_guard, second_wait)

    assert (
        first_stop
        < first_wait
        < first_guard
        < second_stop
        < second_wait
        < second_guard
    )
    assert recipe.count("macos-runtime-force-stop") >= 2
    assert 'apt_source="network"' in recipe
    assert 'apt_source="verified-cache"' in recipe
    assert '--apt-source "$${apt_source}"' in recipe


def test_vm_stage_materializes_host_settings_owner_after_guest_deploy() -> None:
    recipe = target_recipe(
        RUNTIME_MAKEFILE.read_text(encoding="utf-8"),
        "internal/vm/stage",
    )

    assert_in_order(
        recipe,
        (
            "guest-deploy",
            "macos-runtime-control",
            "runtime configure",
        ),
    )


def test_rootfs_contract_ignores_legacy_generated_guest_wheels() -> None:
    makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")

    assert "VM_PKG_ROOTFS_CONTRACT_VERSION := 6" in makefile
    assert "-path packages/vitalserver-guest-tools/dist" in makefile


def test_diagnostic_runtime_smoke_requires_a_compiled_rootfs() -> None:
    makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")
    require_recipe = target_recipe(makefile, "internal/vm/golden-rootfs/require")

    assert (
        "internal/vm/golden-rootfs/runtime-smoke: "
        "internal/vm/golden-rootfs/require"
    ) in makefile
    assert "run make dist/dmg/dev/compile first" in require_recipe
    assert "internal/vm/docker/images" not in require_recipe
    assert "internal/vm/airgap-rootfs" not in require_recipe


def test_release_contract_precedes_fingerprint_and_docker_compile() -> None:
    makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")

    for target in (
        "internal/vm/airgap-rootfs",
        "internal/vm/golden-rootfs",
        "internal/vm/docker/images",
        "internal/vm/pkg",
        "internal/vm/dmg",
        "internal/vm/update",
    ):
        assert f"{target}: internal/vm/release-contract" in makefile


def test_distribution_review_runs_the_complete_swift_suite_and_guest_repair() -> None:
    review = target_recipe(
        PACKAGE_MAKEFILE.read_text(encoding="utf-8"),
        "internal/vm/distribution/review",
    )

    assert "swift test" in review
    assert '--package-path "$(VM_SWIFT_PACKAGE_DIR)"' in review
    assert "--filter" not in review
    assert "test_release_sync_contract.py" in review
    assert "packages/vitalserver-guest-tools/tests/test_redis_repair.py" in review


def test_distribution_review_runs_current_macos_stabilization_contracts() -> None:
    review = target_recipe(
        PACKAGE_MAKEFILE.read_text(encoding="utf-8"),
        "internal/vm/distribution/review",
    )

    for current_product_test in (
        "packages/vitalserver-devtools/tests/unit/"
        "test_macos_package_install_policy.py",
        "packages/vitalserver-devtools/tests/unit/test_macos_package_receipts.py",
        "packages/vitalserver-devtools/tests/unit/test_macos_installed_runtime.py",
        "packages/vitalserver-devtools/tests/unit/"
        "test_macos_update_bundle_usecases.py",
        "packages/vitalserver-devtools/tests/unit/"
        "test_update_bootstrap_trust_store.py",
    ):
        assert current_product_test in review

    assert "packages/vitalserver-devtools/tests/unit" not in review.splitlines()


def test_vm_image_update_does_not_infer_updater_bridge_from_rootfs() -> None:
    makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")
    image_update_contract = makefile.split(
        "internal/vm/image-update: VM_UPDATE_ROOTFS_BASE",
        maxsplit=1,
    )[1].split("internal/vm/image-update/dev", maxsplit=1)[0]

    assert "VM_IMAGE_UPDATE_REQUIRES_TWO_PHASE_UPDATE ?= false" in makefile
    assert (
        "internal/vm/image-update: "
        "VM_IMAGE_UPDATE_REQUIRES_TWO_PHASE_UPDATE := true"
    ) not in makefile
    assert (
        'VM_IMAGE_UPDATE_REQUIRES_TWO_PHASE_UPDATE='
        '"$(VM_IMAGE_UPDATE_REQUIRES_TWO_PHASE_UPDATE)"'
    ) in image_update_contract


def test_public_product_update_uses_signed_stable_three_layer_contract() -> None:
    package_makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")
    root_makefile = ROOT_MAKEFILE.read_text(encoding="utf-8")
    update = target_recipe(package_makefile, "internal/vm/update")
    verify = target_recipe(package_makefile, "internal/vm/update/verify")

    assert "helper-stable-update-release" in update
    assert "--container-artifact" in update
    assert "--guest-runtime-artifact" in update
    assert "--host-platform-artifact" in update
    assert update.index("--container-artifact") < update.index(
        "--guest-runtime-artifact"
    ) < update.index("--host-platform-artifact")
    assert "--publisher-private-key" in update
    assert "--publisher-trust-store" in update
    assert "release-update-bundle" not in update
    assert "verify-update-bootstrap-bundle" in verify
    assert "--publisher-trust-store" in verify
    assert "dist/update/dev/apply-smoke" in root_makefile
    assert "dist/update/release/apply-smoke" in root_makefile


def test_stable_update_field_smokes_require_owner_proof() -> None:
    package_makefile = PACKAGE_MAKEFILE.read_text(encoding="utf-8")
    root_makefile = ROOT_MAKEFILE.read_text(encoding="utf-8")
    apply_smoke = target_recipe(
        package_makefile,
        "internal/vm/update/apply-smoke",
    )
    rollback_smoke = target_recipe(
        package_makefile,
        "internal/vm/update/rollback-smoke/dev",
    )

    assert "VM_UPDATE_APPLY_REQUEST_ID" in apply_smoke
    assert "verify-update-bootstrap-bundle" not in apply_smoke
    assert "internal/vm/update/verify" in apply_smoke
    assert "runtime apply-update-bootstrap" in apply_smoke
    assert "runtime prove-update-bootstrap" in apply_smoke
    assert "--expect succeeded" in apply_smoke
    assert "VM_UPDATE_ROLLBACK_PROOF_BUNDLE" in rollback_smoke
    assert "verify-update-bootstrap-bundle" in rollback_smoke
    assert "signed rollback proof bundle unexpectedly succeeded" in rollback_smoke
    assert "--expect failed-rolled-back" in rollback_smoke
    assert "dist/update/dev/rollback-smoke" in root_makefile


def test_public_dmg_targets_route_only_to_the_standard_profiles() -> None:
    makefile = ROOT_MAKEFILE.read_text(encoding="utf-8")

    assert "dist/dmg/dev: internal/vm/dmg/dev" in makefile
    assert "dist/dmg/release: internal/vm/dmg/release" in makefile
    assert "dist/dmg/dev/cached: internal/vm/dmg/dev/cached" in makefile
    assert "dist/dmg/release/verify:" not in makefile
    assert "dist/pkg/verify/dev:" not in makefile


def target_recipe(makefile: str, target: str) -> str:
    lines = makefile.splitlines()
    start = next(
        index + 1
        for index, line in enumerate(lines)
        if line.startswith(f"{target}:")
        and not line.startswith(f"{target}: override")
    )
    recipe_lines: list[str] = []
    for line in lines[start:]:
        if line.startswith("\t"):
            recipe_lines.append(line.strip())
            continue
        if line:
            break
    return "\n".join(recipe_lines)


def assert_in_order(recipe: str, commands: tuple[str, ...]) -> None:
    positions = [recipe.index(command) for command in commands]
    assert positions == sorted(positions)

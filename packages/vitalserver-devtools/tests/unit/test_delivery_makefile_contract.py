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


def test_rootfs_cache_miss_recreates_the_base_disk() -> None:
    recipe = target_recipe(
        PACKAGE_MAKEFILE.read_text(encoding="utf-8"),
        "internal/vm/golden-rootfs",
    )
    airgap_rootfs_call = recipe.index("$(MAKE) internal/vm/airgap-rootfs")
    fresh_disk_flag = recipe.index("VM_RECREATE_ROOTFS=true")

    assert airgap_rootfs_call < fresh_disk_flag


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


def test_distribution_review_covers_release_contract_and_guest_repair() -> None:
    review = target_recipe(
        PACKAGE_MAKEFILE.read_text(encoding="utf-8"),
        "internal/vm/distribution/review",
    )

    assert "GuestCommandDispatcherSupportTests" in review
    assert "test_release_sync_contract.py" in review
    assert "packages/vitalserver-guest-tools/tests/test_redis_repair.py" in review


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

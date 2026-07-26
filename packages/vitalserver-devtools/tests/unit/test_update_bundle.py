from __future__ import annotations

import json
import tarfile
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.update_bundle import (
    BuildUpdateBundleInput,
    build_bundle,
    verify_bundle,
)


def test_update_bundle_builds_and_verifies_tarball(tmp_path: Path) -> None:
    app_bundle = tmp_path / "app-bundle.tar.gz"
    app_bundle.write_bytes(b"app")

    output_dir = tmp_path / "dist"
    build_bundle(
        BuildUpdateBundleInput(
            version="1.2.3",
            runtime_version=None,
            bundle_name=None,
            channel="stable",
            release_label="1.2.3",
            min_updater_version=None,
            bundle_kind="product-update",
            helper_version="1.2.3",
            target_platform="macos-arm64",
            component=["serviceStack=2.3.4-stack.1", "vitalServer=2.3.4"],
            requires_guest_activation=None,
            requires_two_phase_update=False,
            output_dir=output_dir,
            rootfs_base=None,
            app_bundle=app_bundle,
            runtime_tools=None,
            nginx_bundle=None,
            guest_deploy=None,
            migration=[],
        )
    )

    archive = output_dir / "update-bundle-stable-product-update-1.2.3.tar.gz"
    assert archive.is_file()
    assert not (output_dir / "update-bundle-stable-product-update-1.2.3").exists()
    with tarfile.open(archive, "r:gz") as tar:
        manifest_file = tar.extractfile(
            "update-bundle-stable-product-update-1.2.3/manifest.json"
        )
        assert manifest_file is not None
        manifest = json.loads(manifest_file.read().decode("utf-8"))
    assert manifest["schemaVersion"] == 3
    assert manifest["channel"] == "stable"
    assert manifest["releaseLabel"] == "1.2.3"
    assert manifest["targetPlatform"] == "macos-arm64"

    verify_bundle(archive)


def test_update_bundle_uses_explicit_safe_bundle_name(tmp_path: Path) -> None:
    app_bundle = tmp_path / "app-bundle.tar.gz"
    app_bundle.write_bytes(b"app")

    output_dir = tmp_path / "dist"
    build_bundle(
        BuildUpdateBundleInput(
            version="1.2.3",
            runtime_version=None,
            bundle_name="custom-update-bundle",
            channel="stable",
            release_label="1.2.3",
            min_updater_version=None,
            bundle_kind="product-update",
            helper_version="1.2.3",
            target_platform="macos-arm64",
            component=[],
            requires_guest_activation=None,
            requires_two_phase_update=False,
            output_dir=output_dir,
            rootfs_base=None,
            app_bundle=app_bundle,
            runtime_tools=None,
            nginx_bundle=None,
            guest_deploy=None,
            migration=[],
        )
    )

    assert (output_dir / "custom-update-bundle.tar.gz").is_file()


def test_vm_image_update_manifest_does_not_infer_two_phase_from_rootfs(
    tmp_path: Path,
) -> None:
    rootfs_base = tmp_path / "rootfs-base.raw.gz"
    rootfs_base.write_bytes(b"rootfs")
    output_dir = tmp_path / "dist"

    build_bundle(
        BuildUpdateBundleInput(
            version="1.2.3",
            runtime_version=None,
            bundle_name=None,
            channel="stable",
            release_label="1.2.3",
            min_updater_version="1.0.0",
            bundle_kind="vm-image-update",
            helper_version="1.2.3",
            target_platform="macos-arm64",
            component=["updater=1.2.3"],
            requires_guest_activation=False,
            requires_two_phase_update=False,
            output_dir=output_dir,
            rootfs_base=rootfs_base,
            app_bundle=None,
            runtime_tools=None,
            nginx_bundle=None,
            guest_deploy=None,
            migration=[],
        )
    )

    archive = output_dir / "update-bundle-stable-vm-image-update-1.2.3.tar.gz"
    with tarfile.open(archive, "r:gz") as tar:
        manifest_file = tar.extractfile(
            "update-bundle-stable-vm-image-update-1.2.3/manifest.json"
        )
        assert manifest_file is not None
        manifest = json.loads(manifest_file.read().decode("utf-8"))

    assert manifest["bundleKind"] == "vm-image-update"
    assert manifest["requiresTwoPhaseUpdate"] is False
    assert [artifact["type"] for artifact in manifest["artifacts"]] == [
        "rootfs-base"
    ]
    verify_bundle(archive)


def test_update_bundle_manifest_preserves_explicit_two_phase_bridge_requirement(
    tmp_path: Path,
) -> None:
    runtime_tools = tmp_path / "runtime-tools.tar.gz"
    runtime_tools.write_bytes(b"updater")
    output_dir = tmp_path / "dist"

    build_bundle(
        BuildUpdateBundleInput(
            version="1.2.3",
            runtime_version=None,
            bundle_name=None,
            channel="stable",
            release_label="1.2.3",
            min_updater_version="1.0.0",
            bundle_kind="product-update",
            helper_version="1.2.3",
            target_platform="macos-arm64",
            component=["updater=1.2.3"],
            requires_guest_activation=False,
            requires_two_phase_update=True,
            output_dir=output_dir,
            rootfs_base=None,
            app_bundle=None,
            runtime_tools=runtime_tools,
            nginx_bundle=None,
            guest_deploy=None,
            migration=[],
        )
    )

    archive = output_dir / "update-bundle-stable-product-update-1.2.3.tar.gz"
    with tarfile.open(archive, "r:gz") as tar:
        manifest_file = tar.extractfile(
            "update-bundle-stable-product-update-1.2.3/manifest.json"
        )
        assert manifest_file is not None
        manifest = json.loads(manifest_file.read().decode("utf-8"))

    assert manifest["requiresTwoPhaseUpdate"] is True

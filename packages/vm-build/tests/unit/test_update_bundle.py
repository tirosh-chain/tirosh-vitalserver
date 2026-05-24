from __future__ import annotations

import json
import tarfile
from argparse import Namespace
from pathlib import Path

from tirosh_vitalserver.vm_build.update_bundle import (
    run_build_update_bundle,
    run_verify_update_bundle,
)


def test_update_bundle_builds_and_verifies_tarball(tmp_path: Path) -> None:
    app_bundle = tmp_path / "app-bundle.tar.gz"
    app_bundle.write_bytes(b"app")

    output_dir = tmp_path / "dist"
    run_build_update_bundle(
        Namespace(
            version="1.2.3",
            runtime_version=None,
            bundle_name=None,
            channel="stable",
            release_label="1.2.3",
            min_updater_version=None,
            bundle_kind="product-update",
            helper_version="1.2.3",
            target_platform=["macos-arm64"],
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

    run_verify_update_bundle(Namespace(bundle_path=archive))


def test_update_bundle_uses_explicit_safe_bundle_name(tmp_path: Path) -> None:
    app_bundle = tmp_path / "app-bundle.tar.gz"
    app_bundle.write_bytes(b"app")

    output_dir = tmp_path / "dist"
    run_build_update_bundle(
        Namespace(
            version="1.2.3",
            runtime_version=None,
            bundle_name="custom-update-bundle",
            channel="stable",
            release_label="1.2.3",
            min_updater_version=None,
            bundle_kind="product-update",
            helper_version="1.2.3",
            target_platform=["macos-arm64"],
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

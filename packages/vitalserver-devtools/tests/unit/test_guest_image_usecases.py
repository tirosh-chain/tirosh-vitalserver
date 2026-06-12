from __future__ import annotations

import re
from pathlib import Path

import pytest
from pytest import MonkeyPatch

from tirosh_vitalserver.devtools.application.inputs import UbuntuBootAssetsInput
from tirosh_vitalserver.devtools.application.usecases import (
    guest_image as guest_image_usecases,
)
from tirosh_vitalserver.devtools.application.usecases.guest_services import (
    stage_rootfs_input_metadata,
)
from tirosh_vitalserver.devtools.config.build_toml import load_build_toml
from tirosh_vitalserver.devtools.config.guest_image import load_ubuntu_image_config
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.guest_image import (
    UbuntuBootAssetPlan,
    ubuntu_boot_asset_plan,
    ubuntu_download_cache_key,
)


def test_prepare_ubuntu_boot_assets_builds_plan_from_config(
    tmp_path: Path,
    monkeypatch: MonkeyPatch,
) -> None:
    plan: UbuntuBootAssetPlan | None = None

    def load_config(path: Path) -> dict[str, dict[str, object]]:
        return {
            "guest": {
                "ubuntu": {
                    "version": "24.04",
                    "base_url": "https://example.invalid/noble",
                    "apt_snapshot": "20250313T000000Z",
                    "arch": "auto",
                    "kernel_suffix": "vmlinuz-generic",
                    "initrd_suffix": "initrd-generic",
                },
                "runtime": {
                    "runtime_dir": "runtime",
                    "rootfs_size": "8G",
                    "disk_image_name": "disk.img",
                },
            },
        }

    def run_ubuntu(value: UbuntuBootAssetPlan) -> int:
        nonlocal plan
        plan = value
        return 0

    monkeypatch.setattr(guest_image_usecases, "load_config", load_config)
    monkeypatch.setattr(
        guest_image_usecases,
        "default_runtime_dir",
        lambda: tmp_path / "default-runtime",
    )
    monkeypatch.setattr(guest_image_usecases, "host_machine", lambda: "arm64")
    monkeypatch.setattr(guest_image_usecases, "run_ubuntu", run_ubuntu)

    result = guest_image_usecases.prepare_ubuntu_boot_assets(
        UbuntuBootAssetsInput(
            config=Path("config/vm-build.toml"),
            runtime_dir=None,
            rootfs_size=None,
            recreate_rootfs=None,
            disk_image_name=None,
        )
    )

    assert result == 0
    assert plan is not None
    assert plan.arch == "arm64"
    assert plan.runtime_dir == Path("runtime")
    assert (
        plan.download_dir
        == Path("runtime")
        / "downloads"
        / ubuntu_download_cache_key("https://example.invalid/noble")
    )
    assert plan.rootfs_size == "8G"
    assert plan.disk_image_name == "disk.img"


def test_default_ubuntu_image_config_uses_pinned_noble_release_source() -> None:
    repo_root = Path(__file__).resolve().parents[4]
    ubuntu_config = load_ubuntu_image_config(
        load_build_toml(repo_root / "config/vm-build.toml")
    )

    assert ubuntu_config.version == "24.04"
    assert ubuntu_config.base_url == (
        "https://cloud-images.ubuntu.com/releases/noble/release-20250516"
    )
    assert ubuntu_config.apt_snapshot == "20250515T000000Z"
    assert not ubuntu_config.base_url.endswith("/release")


def test_ubuntu_image_config_rejects_invalid_apt_snapshot() -> None:
    with pytest.raises(DomainError, match="unsupported guest.ubuntu.apt_snapshot"):
        load_ubuntu_image_config(
            {
                "guest": {
                    "ubuntu": {
                        "version": "24.04",
                        "base_url": "https://example.invalid/noble",
                        "apt_snapshot": "2025-03-13",
                    },
                },
            }
        )


def test_ubuntu_boot_asset_plan_rejects_rootfs_smaller_than_airgap_minimum() -> None:
    with pytest.raises(DomainError, match="rootfs_size is too small"):
        ubuntu_boot_asset_plan(
            config_path=Path("config/vm-build.toml"),
            runtime_dir=Path("runtime"),
            rootfs_size="4G",
            recreate_rootfs=True,
            disk_image_name="vm-disk.img",
            ubuntu_version="24.04",
            base_url="https://example.invalid/noble",
            requested_arch="arm64",
            host_machine="arm64",
            kernel_suffix="vmlinuz-generic",
            initrd_suffix="initrd-generic",
        )


def test_ubuntu_download_cache_key_preserves_release_source_identity() -> None:
    old_release = ubuntu_download_cache_key(
        "https://cloud-images.ubuntu.com/releases/noble/release-20250313"
    )
    new_release = ubuntu_download_cache_key(
        "https://cloud-images.ubuntu.com/releases/noble/release-20250516"
    )

    assert old_release.startswith("release-20250313-")
    assert new_release.startswith("release-20250516-")
    assert old_release != new_release


def test_stage_rootfs_input_metadata_preserves_ubuntu_source_identity(
    tmp_path: Path,
) -> None:
    base_url = "https://cloud-images.ubuntu.com/releases/noble/release-20250313"

    stage_rootfs_input_metadata(
        deploy_dir=tmp_path,
        base_url=base_url,
        apt_snapshot="20250313T000000Z",
    )

    metadata = load_json(tmp_path / "build-metadata/rootfs-input.json")
    assert metadata["schemaVersion"] == 1
    assert isinstance(metadata["guestClockUtc"], str)
    assert re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z",
        metadata["guestClockUtc"],
    )
    assert metadata["runtimeBootSmoke"] == {"enabled": False}
    assert metadata["ubuntu"] == {
        "aptSnapshot": "20250313T000000Z",
        "baseUrl": base_url,
        "cacheKey": ubuntu_download_cache_key(base_url),
    }


def test_stage_rootfs_input_metadata_preserves_run_identity(
    tmp_path: Path,
) -> None:
    base_url = "https://cloud-images.ubuntu.com/releases/noble/release-20250313"

    stage_rootfs_input_metadata(
        deploy_dir=tmp_path,
        base_url=base_url,
        apt_snapshot="20250313T000000Z",
        run_id="run-test",
    )

    metadata = load_json(tmp_path / "build-metadata/rootfs-input.json")
    assert metadata["runId"] == "run-test"


def load_json(path: Path) -> dict[str, object]:
    import json

    with path.open(encoding="utf-8") as handle:
        document = json.load(handle)
    assert isinstance(document, dict)
    return document

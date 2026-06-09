from __future__ import annotations

from pathlib import Path

import pytest
from pytest import MonkeyPatch

from tirosh_vitalserver.devtools.application.inputs import UbuntuBootAssetsInput
from tirosh_vitalserver.devtools.application.usecases import (
    guest_image as guest_image_usecases,
)
from tirosh_vitalserver.devtools.config.build_toml import load_build_toml
from tirosh_vitalserver.devtools.config.guest_image import load_ubuntu_image_config
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.guest_image import (
    UbuntuBootAssetPlan,
    ubuntu_boot_asset_plan,
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
    assert plan.rootfs_size == "8G"
    assert plan.disk_image_name == "disk.img"


def test_default_ubuntu_image_config_uses_pinned_noble_release_source() -> None:
    repo_root = Path(__file__).resolve().parents[4]
    ubuntu_config = load_ubuntu_image_config(
        load_build_toml(repo_root / "config/vm-build.toml")
    )

    assert ubuntu_config.version == "24.04"
    assert ubuntu_config.base_url == (
        "https://cloud-images.ubuntu.com/releases/noble/release-20260518"
    )
    assert not ubuntu_config.base_url.endswith("/release")


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

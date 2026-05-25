from __future__ import annotations

from pathlib import Path

from pytest import MonkeyPatch

from tirosh_vitalserver.devtools.application.inputs import UbuntuBootAssetsInput
from tirosh_vitalserver.devtools.application.usecases import (
    guest_image as guest_image_usecases,
)
from tirosh_vitalserver.devtools.core.guest_image import UbuntuBootAssetPlan


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

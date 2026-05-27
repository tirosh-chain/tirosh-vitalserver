from __future__ import annotations

import gzip
import platform
import shutil
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.toolchain.shell_commands import (
    capture_json,
    require_tool,
    run,
)
from tirosh_vitalserver.devtools.core.guest_image import (
    UbuntuBootAssetPlan,
    size_to_bytes,
)


def host_machine() -> str:
    return platform.machine()


def run_ubuntu(plan: UbuntuBootAssetPlan) -> int:
    require_tool("curl")
    require_tool("qemu-img", "Install it on the build machine with: brew install qemu")
    plan.runtime_dir.mkdir(parents=True, exist_ok=True)
    plan.download_dir.mkdir(parents=True, exist_ok=True)

    print(f"Ubuntu image config: {plan.config_path}")
    print(f"Ubuntu image arch: {plan.arch}")

    download_once(
        f"{plan.base_url}/unpacked/{plan.assets.kernel_name}",
        plan.download_dir / plan.assets.kernel_name,
    )
    download_once(
        f"{plan.base_url}/unpacked/{plan.assets.initrd_name}",
        plan.download_dir / plan.assets.initrd_name,
    )
    download_once(
        f"{plan.base_url}/{plan.assets.image_name}",
        plan.download_dir / plan.assets.image_name,
    )

    with (
        gzip.open(plan.download_dir / plan.assets.kernel_name, "rb") as source,
        (plan.runtime_dir / "Image").open("wb") as target,
    ):
        shutil.copyfileobj(source, target)
    shutil.copy2(
        plan.download_dir / plan.assets.initrd_name,
        plan.runtime_dir / "initrd.img",
    )

    if plan.recreate_rootfs:
        plan.disk_image.unlink(missing_ok=True)

    if plan.disk_image.exists() and plan.disk_image.stat().st_size > 0:
        print(f"exists {plan.disk_image}")
    else:
        print(
            f"converting {plan.download_dir / plan.assets.image_name} "
            f"to {plan.disk_image_name}"
        )
        run(
            [
                "qemu-img",
                "convert",
                "-p",
                "-O",
                "raw",
                str(plan.download_dir / plan.assets.image_name),
                str(plan.disk_image),
            ]
        )

    resize_rootfs_if_needed(plan.disk_image, plan.disk_image_name, plan.rootfs_size)

    print("Linux boot assets are ready:")
    print(f"  {plan.runtime_dir / 'Image'}")
    print(f"  {plan.runtime_dir / 'initrd.img'}")
    print(f"  {plan.disk_image} ({plan.rootfs_size} target)")
    return 0


def download_once(url: str, output: Path) -> None:
    if output.exists() and output.stat().st_size > 0:
        print(f"exists {output}")
        return
    partial = output.with_name(output.name + ".partial")
    print(f"downloading {url}")
    run(
        [
            "curl",
            "--fail",
            "--location",
            "--continue-at",
            "-",
            "--output",
            str(partial),
            url,
        ]
    )
    partial.replace(output)


def resize_rootfs_if_needed(
    disk_image: Path,
    disk_image_name: str,
    rootfs_size: str,
) -> None:
    info = capture_json(["qemu-img", "info", "--output=json", str(disk_image)])
    if not isinstance(info, dict) or not isinstance(info.get("virtual-size"), int):
        raise SystemExit(f"error: unable to read virtual size for {disk_image}")
    current_size = info["virtual-size"]
    desired_size = size_to_bytes(rootfs_size)
    if current_size >= desired_size:
        print(f"{disk_image_name} size is already >= {rootfs_size}")
        return
    print(f"resizing {disk_image_name} to {rootfs_size}")
    run(["qemu-img", "resize", "-f", "raw", str(disk_image), rootfs_size])

from __future__ import annotations

import gzip
import platform
import shutil
from argparse import Namespace
from pathlib import Path

from .config import (
    load_config,
    optional_bool,
    optional_string,
    required_string,
    section,
)
from .process import capture_json, require_tool, run


def run_ubuntu(args: Namespace) -> int:
    config = load_config(args.config)
    ubuntu_config = section(config, "ubuntu")
    runtime_config = section(config, "runtime")

    default_home = Path.home() / ".tirosh/vitalserver-vm"
    runtime_dir = args.runtime_dir or default_home / "runtime"
    download_dir = runtime_dir / "downloads"
    rootfs_size = args.rootfs_size or optional_string(
        runtime_config,
        "rootfs_size",
        "8G",
    )
    recreate_rootfs = (
        args.recreate_rootfs
        if args.recreate_rootfs is not None
        else optional_bool(runtime_config, "recreate_rootfs", False)
    )
    disk_image_name = args.disk_image_name or optional_string(
        runtime_config,
        "disk_image_name",
        "vm-disk.img",
    )
    disk_image = runtime_dir / disk_image_name

    ubuntu_version = required_string(ubuntu_config, "version")
    base_url = required_string(ubuntu_config, "base_url")
    requested_arch = optional_string(ubuntu_config, "arch", "auto")
    arch = resolve_arch(requested_arch)
    kernel_suffix = optional_string(ubuntu_config, "kernel_suffix", "vmlinuz-generic")
    initrd_suffix = optional_string(ubuntu_config, "initrd_suffix", "initrd-generic")

    asset_prefix = f"ubuntu-{ubuntu_version}-server-cloudimg-{arch}"
    kernel_name = f"{asset_prefix}-{kernel_suffix}"
    initrd_name = f"{asset_prefix}-{initrd_suffix}"
    image_name = f"{asset_prefix}.img"

    require_tool("curl")
    require_tool("qemu-img", "Install it on the build machine with: brew install qemu")
    runtime_dir.mkdir(parents=True, exist_ok=True)
    download_dir.mkdir(parents=True, exist_ok=True)

    print(f"Ubuntu image config: {args.config}")
    print(f"Ubuntu image arch: {arch}")

    download_once(f"{base_url}/unpacked/{kernel_name}", download_dir / kernel_name)
    download_once(f"{base_url}/unpacked/{initrd_name}", download_dir / initrd_name)
    download_once(f"{base_url}/{image_name}", download_dir / image_name)

    with gzip.open(download_dir / kernel_name, "rb") as source, (
        runtime_dir / "Image"
    ).open("wb") as target:
        shutil.copyfileobj(source, target)
    shutil.copy2(download_dir / initrd_name, runtime_dir / "initrd.img")

    if recreate_rootfs:
        disk_image.unlink(missing_ok=True)

    if disk_image.exists() and disk_image.stat().st_size > 0:
        print(f"exists {disk_image}")
    else:
        print(f"converting {download_dir / image_name} to {disk_image_name}")
        run(
            [
                "qemu-img",
                "convert",
                "-p",
                "-O",
                "raw",
                str(download_dir / image_name),
                str(disk_image),
            ]
        )

    resize_rootfs_if_needed(disk_image, disk_image_name, rootfs_size)

    print("Linux boot assets are ready:")
    print(f"  {runtime_dir / 'Image'}")
    print(f"  {runtime_dir / 'initrd.img'}")
    print(f"  {disk_image} ({rootfs_size} target)")
    return 0

def resolve_arch(requested: str) -> str:
    if requested != "auto":
        return requested
    machine = platform.machine()
    if machine in ("arm64", "aarch64"):
        return "arm64"
    if machine in ("x86_64", "amd64"):
        return "amd64"
    raise SystemExit(f"error: unsupported host architecture: {machine}")


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


def size_to_bytes(value: str) -> int:
    number_text = value[:-1] if value[-1:].lower() in ("k", "m", "g") else value
    unit = value[-1:].lower() if value[-1:].lower() in ("k", "m", "g") else ""
    try:
        number = int(number_text)
    except ValueError as exc:
        raise SystemExit(f"error: unsupported VM_ROOTFS_SIZE: {value}") from exc
    multiplier = {"": 1, "k": 1024, "m": 1024 * 1024, "g": 1024 * 1024 * 1024}[unit]
    return number * multiplier

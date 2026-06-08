from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.errors import DomainError

MINIMUM_AIRGAP_ROOTFS_SIZE = "8G"


@dataclass(frozen=True)
class UbuntuAssetNames:
    arch: str
    kernel_name: str
    initrd_name: str
    image_name: str


@dataclass(frozen=True)
class GuestRuntimeConfig:
    runtime_dir: Path
    rootfs_size: str
    recreate_rootfs: bool
    disk_image_name: str


@dataclass(frozen=True)
class UbuntuImageConfig:
    version: str
    base_url: str
    arch: str
    kernel_suffix: str
    initrd_suffix: str


@dataclass(frozen=True)
class CloudInitConfig:
    seed_directory_name: str
    seed_iso_name: str
    hostname: str
    username: str
    password: str
    ssh_key_path: Path
    run_bootstrap: bool
    share_tag: str
    share_mount: str
    bootstrap_script: str


@dataclass(frozen=True)
class UbuntuBootAssetPlan:
    config_path: Path
    runtime_dir: Path
    download_dir: Path
    disk_image: Path
    disk_image_name: str
    rootfs_size: str
    recreate_rootfs: bool
    base_url: str
    arch: str
    assets: UbuntuAssetNames


@dataclass(frozen=True)
class CloudInitSeedSpec:
    seed_dir: Path
    seed_iso: Path
    hostname: str
    instance_id: str
    username: str
    password: str
    ssh_key_path: Path
    run_bootstrap: bool
    share_tag: str
    share_mount: str
    bootstrap_script: str


def resolve_ubuntu_arch(requested: str, host_machine: str) -> str:
    if requested != "auto":
        return requested
    if host_machine in ("arm64", "aarch64"):
        return "arm64"
    if host_machine in ("x86_64", "amd64"):
        return "amd64"
    raise DomainError(f"error: unsupported host architecture: {host_machine}")


def ubuntu_asset_names(
    *,
    version: str,
    arch: str,
    kernel_suffix: str,
    initrd_suffix: str,
) -> UbuntuAssetNames:
    asset_prefix = f"ubuntu-{version}-server-cloudimg-{arch}"
    return UbuntuAssetNames(
        arch=arch,
        kernel_name=f"{asset_prefix}-{kernel_suffix}",
        initrd_name=f"{asset_prefix}-{initrd_suffix}",
        image_name=f"{asset_prefix}.img",
    )


def ubuntu_boot_asset_plan(
    *,
    config_path: Path,
    runtime_dir: Path,
    rootfs_size: str,
    recreate_rootfs: bool,
    disk_image_name: str,
    ubuntu_version: str,
    base_url: str,
    requested_arch: str,
    host_machine: str,
    kernel_suffix: str,
    initrd_suffix: str,
) -> UbuntuBootAssetPlan:
    arch = resolve_ubuntu_arch(requested_arch, host_machine)
    require_minimum_rootfs_size(rootfs_size)
    assets = ubuntu_asset_names(
        version=ubuntu_version,
        arch=arch,
        kernel_suffix=kernel_suffix,
        initrd_suffix=initrd_suffix,
    )
    return UbuntuBootAssetPlan(
        config_path=config_path,
        runtime_dir=runtime_dir,
        download_dir=runtime_dir / "downloads",
        disk_image=runtime_dir / disk_image_name,
        disk_image_name=disk_image_name,
        rootfs_size=rootfs_size,
        recreate_rootfs=recreate_rootfs,
        base_url=base_url,
        arch=arch,
        assets=assets,
    )


def require_minimum_rootfs_size(value: str) -> None:
    minimum_bytes = size_to_bytes(MINIMUM_AIRGAP_ROOTFS_SIZE)
    actual_bytes = size_to_bytes(value)
    if actual_bytes < minimum_bytes:
        raise DomainError(
            "error: guest rootfs_size is too small for air-gapped runtime "
            f"package preparation: rootfs_size={value} "
            f"minimum={MINIMUM_AIRGAP_ROOTFS_SIZE}"
        )


def size_to_bytes(value: str) -> int:
    number_text = value[:-1] if value[-1:].lower() in ("k", "m", "g") else value
    unit = value[-1:].lower() if value[-1:].lower() in ("k", "m", "g") else ""
    try:
        number = int(number_text)
    except ValueError as exc:
        raise DomainError(f"error: unsupported VM_ROOTFS_SIZE: {value}") from exc
    multiplier = {"": 1, "k": 1024, "m": 1024 * 1024, "g": 1024 * 1024 * 1024}[unit]
    return number * multiplier


def cloud_init_meta_data(instance_id: str, hostname: str) -> str:
    return f"instance-id: {instance_id}\nlocal-hostname: {hostname}\n"


def cloud_init_ssh_keys(keys: list[str]) -> str:
    if not keys:
        return "    ssh_authorized_keys: []"
    return "\n".join(["    ssh_authorized_keys:", *[f"      - {key}" for key in keys]])


def cloud_init_bootstrap_commands(
    *,
    run_bootstrap: bool,
    share_tag: str,
    share_mount: str,
    bootstrap_script: str,
) -> str:
    if not run_bootstrap:
        return ""
    return "\n".join(
        [
            "runcmd:",
            f"  - mkdir -p {share_mount}",
            (
                f"  - mountpoint -q {share_mount} "
                f"|| mount -t virtiofs {share_tag} {share_mount}"
            ),
            f"  - test -x {bootstrap_script}",
            f"  - {bootstrap_script}",
        ]
    )


def cloud_init_user_data(
    *,
    hostname: str,
    username: str,
    password: str,
    ssh_keys: list[str],
    run_bootstrap: bool,
    share_tag: str,
    share_mount: str,
    bootstrap_script: str,
) -> str:
    return "\n".join(
        [
            "#cloud-config",
            f"hostname: {hostname}",
            "manage_etc_hosts: true",
            "ssh_pwauth: true",
            "disable_root: true",
            "users:",
            "  - default",
            f"  - name: {username}",
            "    groups: [adm, sudo]",
            "    shell: /bin/bash",
            "    sudo: ALL=(ALL) NOPASSWD:ALL",
            "    lock_passwd: false",
            cloud_init_ssh_keys(ssh_keys),
            "chpasswd:",
            "  expire: false",
            "  users:",
            f"    - name: {username}",
            f"      password: {password}",
            "      type: text",
            cloud_init_bootstrap_commands(
                run_bootstrap=run_bootstrap,
                share_tag=share_tag,
                share_mount=share_mount,
                bootstrap_script=bootstrap_script,
            ),
            "",
        ]
    )

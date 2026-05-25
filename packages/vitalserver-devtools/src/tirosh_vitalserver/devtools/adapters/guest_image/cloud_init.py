from __future__ import annotations

import shutil
import subprocess
import uuid
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.toolchain.shell_commands import require_tool
from tirosh_vitalserver.devtools.core.guest_image import (
    CloudInitSeedSpec,
    cloud_init_meta_data,
    cloud_init_user_data,
)


def create_cloud_init_seed(spec: CloudInitSeedSpec) -> None:
    require_tool("hdiutil")
    prepare_seed_directory(spec.seed_dir, spec.seed_iso)
    write_meta_data(spec.seed_dir, spec.instance_id, spec.hostname)
    write_user_data(
        seed_dir=spec.seed_dir,
        hostname=spec.hostname,
        username=spec.username,
        password=spec.password,
        ssh_key_path=spec.ssh_key_path,
        run_bootstrap=spec.run_bootstrap,
        share_tag=spec.share_tag,
        share_mount=spec.share_mount,
        bootstrap_script=spec.bootstrap_script,
    )
    build_seed_iso(spec.seed_dir, spec.seed_iso)


def default_runtime_dir() -> Path:
    return Path.home() / ".tirosh/vitalserver-vm/runtime"


def default_ssh_key_path() -> Path:
    return Path.home() / ".ssh/id_ed25519.pub"


def generate_instance_id() -> str:
    return f"tirosh-{uuid.uuid4()}"


def prepare_seed_directory(seed_dir: Path, seed_iso: Path) -> None:
    if seed_dir.exists():
        shutil.rmtree(seed_dir)
    seed_dir.mkdir(parents=True)
    seed_iso.parent.mkdir(parents=True, exist_ok=True)


def write_meta_data(seed_dir: Path, instance_id: str, hostname: str) -> None:
    (seed_dir / "meta-data").write_text(
        cloud_init_meta_data(instance_id, hostname),
        encoding="utf-8",
    )


def write_user_data(
    *,
    seed_dir: Path,
    hostname: str,
    username: str,
    password: str,
    ssh_key_path: Path,
    run_bootstrap: bool,
    share_tag: str,
    share_mount: str,
    bootstrap_script: str,
) -> None:
    ssh_keys = read_ssh_keys(ssh_key_path)
    (seed_dir / "user-data").write_text(
        cloud_init_user_data(
            hostname=hostname,
            username=username,
            password=password,
            ssh_keys=ssh_keys,
            run_bootstrap=run_bootstrap,
            share_tag=share_tag,
            share_mount=share_mount,
            bootstrap_script=bootstrap_script,
        ),
        encoding="utf-8",
    )


def read_ssh_keys(ssh_key_path: Path) -> list[str]:
    if not ssh_key_path.is_file() or ssh_key_path.stat().st_size == 0:
        return []
    return [
        line.strip()
        for line in ssh_key_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def build_seed_iso(seed_dir: Path, seed_iso: Path) -> None:
    if seed_iso.exists():
        seed_iso.unlink()
    subprocess.run(
        [
            "hdiutil",
            "makehybrid",
            "-iso",
            "-joliet",
            "-default-volume-name",
            "cidata",
            "-o",
            str(seed_iso),
            str(seed_dir),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def print_result(
    seed_iso: Path,
    username: str,
    password: str,
    hostname: str,
    instance_id: str,
    run_bootstrap: bool,
    bootstrap_script: str,
) -> None:
    print("cloud-init seed is ready:")
    print(f"  {seed_iso}")
    print(f"  user: {username}")
    print(f"  password: {password}")
    print(f"  hostname: {hostname}")
    print(f"  instance-id: {instance_id}")
    print(f"  auto bootstrap: {str(run_bootstrap).lower()}")
    if run_bootstrap:
        print(f"  bootstrap script: {bootstrap_script}")

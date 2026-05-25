from __future__ import annotations

import shutil
import subprocess
import uuid
from argparse import Namespace
from pathlib import Path

from tirosh_vitalserver.devtools.config.build_toml import (
    load_build_toml,
    optional_bool,
    optional_string,
    section,
)
from tirosh_vitalserver.devtools.toolchain.shell_commands import require_tool


def run_cloud_init(args: Namespace) -> int:
    config = load_build_toml(args.config)
    runtime_config = section(config, "runtime")
    cloud_config = section(config, "cloud_init")

    runtime_dir = (
        args.runtime_dir
        or Path(
            optional_string(runtime_config, "runtime_dir", str(default_runtime_dir()))
        ).expanduser()
    )
    seed_dir = args.seed_dir or runtime_dir / optional_string(
        cloud_config,
        "seed_directory_name",
        "cloud-init-seed",
    )
    seed_iso = args.seed_iso or runtime_dir / optional_string(
        cloud_config,
        "seed_iso_name",
        "seed.iso",
    )
    hostname = args.hostname or optional_string(
        cloud_config,
        "hostname",
        "tirosh-vitalserver",
    )
    instance_id = args.instance_id or generate_instance_id()
    username = args.username or optional_string(cloud_config, "username", "ubuntu")
    password = args.password or optional_string(cloud_config, "password", "ubuntu")
    ssh_key_path = (
        args.ssh_key
        or Path(
            optional_string(
                cloud_config,
                "ssh_key_path",
                str(Path.home() / ".ssh/id_ed25519.pub"),
            )
        ).expanduser()
    )
    run_bootstrap = (
        args.run_bootstrap
        if args.run_bootstrap is not None
        else optional_bool(cloud_config, "run_bootstrap", True)
    )
    share_tag = args.share_tag or optional_string(cloud_config, "share_tag", "tirosh")
    share_mount = args.share_mount or optional_string(
        cloud_config,
        "share_mount",
        "/mnt/tirosh",
    )
    bootstrap_script = args.bootstrap_script or optional_string(
        cloud_config,
        "bootstrap_script",
        f"{share_mount}/deploy/bootstrap.sh",
    )

    require_tool("hdiutil")
    prepare_seed_directory(seed_dir, seed_iso)
    write_meta_data(seed_dir, instance_id, hostname)
    write_user_data(
        seed_dir=seed_dir,
        hostname=hostname,
        username=username,
        password=password,
        ssh_key_path=ssh_key_path,
        run_bootstrap=run_bootstrap,
        share_tag=share_tag,
        share_mount=share_mount,
        bootstrap_script=bootstrap_script,
    )
    build_seed_iso(seed_dir, seed_iso)
    print_result(
        seed_iso,
        username,
        password,
        hostname,
        instance_id,
        run_bootstrap,
        bootstrap_script,
    )
    return 0


def default_runtime_dir() -> Path:
    return Path.home() / ".tirosh/vitalserver-vm/runtime"


def generate_instance_id() -> str:
    return f"tirosh-{uuid.uuid4()}"


def prepare_seed_directory(seed_dir: Path, seed_iso: Path) -> None:
    if seed_dir.exists():
        shutil.rmtree(seed_dir)
    seed_dir.mkdir(parents=True)
    seed_iso.parent.mkdir(parents=True, exist_ok=True)


def write_meta_data(seed_dir: Path, instance_id: str, hostname: str) -> None:
    (seed_dir / "meta-data").write_text(
        f"instance-id: {instance_id}\nlocal-hostname: {hostname}\n",
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
    ssh_keys = cloud_init_ssh_keys(ssh_key_path)
    bootstrap_commands = cloud_init_bootstrap_commands(
        run_bootstrap=run_bootstrap,
        share_tag=share_tag,
        share_mount=share_mount,
        bootstrap_script=bootstrap_script,
    )
    (seed_dir / "user-data").write_text(
        "\n".join(
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
                ssh_keys,
                "chpasswd:",
                "  expire: false",
                "  users:",
                f"    - name: {username}",
                f"      password: {password}",
                "      type: text",
                bootstrap_commands,
                "",
            ]
        ),
        encoding="utf-8",
    )


def cloud_init_ssh_keys(ssh_key_path: Path) -> str:
    if not ssh_key_path.is_file() or ssh_key_path.stat().st_size == 0:
        return "    ssh_authorized_keys: []"
    keys = [
        line.strip()
        for line in ssh_key_path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
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

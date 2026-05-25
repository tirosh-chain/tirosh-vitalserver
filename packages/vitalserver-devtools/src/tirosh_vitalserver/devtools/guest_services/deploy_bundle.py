from __future__ import annotations

import shutil
from argparse import Namespace
from pathlib import Path

from tirosh_vitalserver.devtools.config.build_toml import load_build_toml, section
from tirosh_vitalserver.devtools.config.guest_deploy import (
    GuestDeployConfig,
    load_guest_deploy_config,
)
from tirosh_vitalserver.devtools.toolchain.workspace_paths import repo_root

IGNORED_NAMES = (".DS_Store", "._*", "__pycache__")


def run_guest_deploy(args: Namespace) -> int:
    root = repo_root()
    config = load_build_toml(args.config)
    deploy_config = load_guest_deploy_config(section(config, "guest_deploy"))
    runtime_dir = resolve_path(root, args.runtime_dir)
    vm_home = resolve_path(root, args.vm_home)
    if args.deploy_dir:
        deploy_dir = resolve_path(root, args.deploy_dir)
    else:
        deploy_dir = vm_home / "data/deploy"
    docker_bundle = (
        resolve_path(root, args.docker_bundle)
        if args.docker_bundle is not None
        else None
    )

    stage_guest_deploy(
        root=root,
        runtime_dir=runtime_dir,
        deploy_dir=deploy_dir,
        config=deploy_config,
        docker_bundle=docker_bundle,
    )
    ensure_vm_data_dirs(vm_home)
    print(f"guest deployment bundle is ready: {deploy_dir}")
    return 0


def stage_guest_deploy(
    *,
    root: Path,
    runtime_dir: Path,
    deploy_dir: Path,
    config: GuestDeployConfig,
    docker_bundle: Path | None = None,
) -> None:
    copy_tree(runtime_dir / "Support/Guest", deploy_dir, merge=True)
    for entry in config.includes:
        source = root / entry.source
        destination = deploy_dir / entry.destination
        if source.is_dir():
            copy_tree(source, destination)
        elif source.is_file():
            copy_file(source, destination)
        else:
            raise SystemExit(f"error: missing guest deploy include: {entry.source}")
    if docker_bundle:
        copy_file(docker_bundle, deploy_dir / config.docker_image_bundle_destination)


def ensure_vm_data_dirs(vm_home: Path) -> None:
    for relative in ["data/deploy", "data/vital-files", "data/vr-release", "data/run"]:
        (vm_home / relative).mkdir(parents=True, exist_ok=True)


def copy_tree(source: Path, destination: Path, *, merge: bool = False) -> None:
    if not source.is_dir():
        raise SystemExit(f"error: missing directory: {source}")
    if destination.exists() and not merge:
        shutil.rmtree(destination)
    shutil.copytree(
        source,
        destination,
        dirs_exist_ok=merge,
        ignore=shutil.ignore_patterns(*IGNORED_NAMES),
    )


def copy_file(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise SystemExit(f"error: missing file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def resolve_path(root: Path, path: Path) -> Path:
    path = path.expanduser()
    return path if path.is_absolute() else root / path

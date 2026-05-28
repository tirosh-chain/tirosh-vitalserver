from __future__ import annotations

import shutil
from pathlib import Path

from tirosh_vitalserver.devtools.core.guest_services import (
    IGNORED_NAMES,
    GuestDeployPlan,
)


def stage_guest_deploy(plan: GuestDeployPlan) -> None:
    copy_tree(plan.support_guest_source, plan.deploy_dir, merge=True)
    for entry in plan.includes:
        if entry.source.is_dir():
            copy_tree(entry.source, entry.destination)
        elif entry.source.is_file():
            copy_file(entry.source, entry.destination)
        else:
            raise SystemExit(f"error: missing guest deploy include: {entry.source}")
    if plan.docker_bundle_source and plan.docker_bundle_destination:
        copy_file(plan.docker_bundle_source, plan.docker_bundle_destination)
    if (
        plan.optional_docker_bundle_source
        and plan.optional_docker_bundle_destination
        and plan.optional_docker_bundle_source.is_file()
    ):
        copy_file(
            plan.optional_docker_bundle_source,
            plan.optional_docker_bundle_destination,
        )


def ensure_vm_data_dirs(plan: GuestDeployPlan) -> None:
    for directory in plan.vm_data_dirs:
        directory.mkdir(parents=True, exist_ok=True)


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

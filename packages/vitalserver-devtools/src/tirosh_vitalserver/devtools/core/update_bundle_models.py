from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ArtifactInput:
    source: Path
    name: str
    kind: str


@dataclass(frozen=True)
class BuildUpdateBundleInput:
    version: str
    runtime_version: str | None
    bundle_name: str | None
    channel: str
    release_label: str | None
    min_updater_version: str | None
    bundle_kind: str
    helper_version: str | None
    target_platform: str
    component: list[str]
    requires_guest_activation: bool | None
    requires_two_phase_update: bool
    output_dir: Path
    rootfs_base: Path | None
    app_bundle: Path | None
    runtime_tools: Path | None
    nginx_bundle: Path | None
    guest_deploy: Path | None
    migration: list[Path]


@dataclass(frozen=True)
class BuildUpdateBundleResult:
    archive: Path


@dataclass(frozen=True)
class ArchiveMember:
    name: str
    is_file: bool
    is_dir: bool
    is_symlink: bool
    is_hardlink: bool

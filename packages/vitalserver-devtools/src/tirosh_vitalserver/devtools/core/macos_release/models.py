from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.guest_services import (
    GuestDeployPlan,
    RootfsInputMetadataPlan,
)
from tirosh_vitalserver.devtools.core.macos_release.settings import MacOSReleaseSettings
from tirosh_vitalserver.devtools.core.release_manifest import ReleaseManifest


@dataclass(frozen=True)
class PackageContext:
    root: Path
    runtime_dir: Path
    release: ReleaseManifest
    pkg_root: Path
    pkg_scripts: Path
    pkg_output: Path
    clean_uninstaller_pkg_output: Path
    dmg_output: Path
    app_bundle: Path
    runtime_cli: Path
    nginx_bundle: Path
    docker_bundle: Path
    rootfs_base: Path
    golden_runtime_dir: Path
    guest_deploy_plan: GuestDeployPlan
    rootfs_input_metadata_plan: RootfsInputMetadataPlan
    proxy_port: str
    settings: MacOSReleaseSettings


@dataclass(frozen=True)
class StagedUpdateArtifacts:
    app_bundle: Path
    runtime_tools: Path
    nginx_bundle: Path
    guest_deploy: Path

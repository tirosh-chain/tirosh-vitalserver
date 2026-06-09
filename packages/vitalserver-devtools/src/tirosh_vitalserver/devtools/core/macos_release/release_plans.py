from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.macos_release.artifact_names import (
    format_release_name,
)
from tirosh_vitalserver.devtools.core.macos_release.settings import MacOSReleaseSettings
from tirosh_vitalserver.devtools.core.release_manifest import ReleaseManifest
from tirosh_vitalserver.devtools.core.update_bundle import is_safe_bundle_name

DEFAULT_UPDATE_MIGRATIONS = (
    "001-refresh-cloud-init-seed",
    "002-migrate-runtime-logs",
    "003-install-host-launchd-services",
    "004-refresh-vm-shutdown-timeouts",
    "005-write-guest-runtime-settings-read-model",
)


@dataclass(frozen=True)
class PackageOutputs:
    pkg_output: Path
    clean_uninstaller_pkg_output: Path
    dmg_output: Path


@dataclass(frozen=True)
class PackageCleanPlan:
    paths: list[Path]


def release_update_bundle_name(
    *,
    channel: str,
    bundle_kind: str,
    release_label: str,
    explicit_name: str | None,
) -> str:
    bundle_name = (
        explicit_name or f"update-bundle-{channel}-{bundle_kind}-{release_label}"
    )
    if not is_safe_bundle_name(bundle_name):
        raise DomainError(f"invalid bundle name: {bundle_name}")
    return bundle_name


def release_update_components(
    *,
    helper_version: str,
    vitalserver_version: str,
) -> list[str]:
    return [
        f"helperUI={helper_version}+macos.1",
        f"updater={helper_version}",
        f"supervisor={helper_version}",
        f"vmDriver={helper_version}+macos.1",
        f"serviceStack={vitalserver_version}-stack.1",
        f"vitalServer={vitalserver_version}",
    ]


def host_proxy_expected_version(
    *,
    release: ReleaseManifest,
    explicit_version: str | None,
) -> str:
    if explicit_version:
        return explicit_version
    if release.host_proxy_image:
        return release.host_proxy_image
    raise DomainError("error: missing release field: services.hostProxy.image")


def require_rootfs_for_update(bundle_kind: str, rootfs_base: Path | None) -> None:
    if bundle_kind == "vm-image-update" and rootfs_base is None:
        raise DomainError("error: --rootfs-base is required for vm-image-update")


def default_update_migrations(runtime_dir: Path) -> list[Path]:
    migrations_dir = runtime_dir / "Support/Build/migrations"
    return [migrations_dir / name for name in DEFAULT_UPDATE_MIGRATIONS]


def default_pkg_output(
    settings: MacOSReleaseSettings,
    release: ReleaseManifest,
) -> Path:
    return settings.dist_dir / format_release_name(
        settings.outputs.pkg_filename_template,
        release,
    )


def default_dmg_output(
    settings: MacOSReleaseSettings,
    release: ReleaseManifest,
) -> Path:
    return settings.dist_dir / format_release_name(
        settings.outputs.dmg_filename_template,
        release,
    )


def default_clean_uninstaller_pkg_output(
    settings: MacOSReleaseSettings,
    release: ReleaseManifest,
) -> Path:
    filename = f"VitalServerHelperResetForReinstall-{release.release_label}.pkg"
    return settings.dist_dir / filename


def package_outputs(
    *,
    settings: MacOSReleaseSettings,
    release: ReleaseManifest,
    requested_output: Path | None,
    output_kind: str,
) -> PackageOutputs:
    if requested_output:
        pkg_output = requested_output
    elif output_kind == "dmg":
        pkg_output = default_dmg_output(settings, release)
    else:
        pkg_output = default_pkg_output(settings, release)

    dmg_output = pkg_output
    if pkg_output.suffix == ".dmg":
        pkg_output = default_pkg_output(settings, release)
    else:
        dmg_output = default_dmg_output(settings, release)
    return PackageOutputs(
        pkg_output=pkg_output,
        clean_uninstaller_pkg_output=default_clean_uninstaller_pkg_output(
            settings,
            release,
        ),
        dmg_output=dmg_output,
    )


def package_clean_plan(
    *,
    root: Path,
    settings: MacOSReleaseSettings,
    release: ReleaseManifest,
) -> PackageCleanPlan:
    paths = [
        settings.pkg_root.parent,
        default_pkg_output(settings, release),
        default_clean_uninstaller_pkg_output(settings, release),
        settings.app_bundle,
        default_dmg_output(settings, release),
    ]
    for path in paths:
        require_safe_package_clean_path(root=root, settings=settings, path=path)
    return PackageCleanPlan(paths=paths)


def require_safe_package_clean_path(
    *,
    root: Path,
    settings: MacOSReleaseSettings,
    path: Path,
) -> None:
    resolved_root = root.resolve(strict=False)
    resolved_path = path.resolve(strict=False)
    dangerous_paths = {Path("/"), resolved_root, resolved_root.parent}
    if resolved_path in dangerous_paths:
        raise DomainError(f"refusing to clean unsafe path: {path}")
    if not resolved_path.is_relative_to(resolved_root):
        raise DomainError(f"refusing to clean path outside workspace: {path}")

    allowed_roots = [
        settings.pkg_root.parent,
        settings.app_bundle.parent,
        settings.dist_dir,
        settings.dmg_staging_dir,
    ]
    resolved_allowed_roots = [
        allowed_root.resolve(strict=False) for allowed_root in allowed_roots
    ]
    if not any(
        resolved_path == allowed_root
        or resolved_path.is_relative_to(allowed_root)
        for allowed_root in resolved_allowed_roots
    ):
        raise DomainError(f"refusing to clean unmanaged package path: {path}")

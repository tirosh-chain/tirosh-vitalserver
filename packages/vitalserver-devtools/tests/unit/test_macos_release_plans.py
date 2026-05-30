from __future__ import annotations

from dataclasses import replace

import pytest

from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.macos_release.release_plans import (
    default_update_migrations,
    package_clean_plan,
)
from tirosh_vitalserver.devtools.core.release_manifest import ReleaseManifest


def test_package_clean_plan_allows_managed_build_paths() -> None:
    root = repo_root()
    settings = load_macos_release_settings(root / "config/vm-build.toml", root)
    release = ReleaseManifest(
        channel="dev",
        helper_version="1.2.3",
        release_label="1.2.3-dev",
        minimum_updater_version="1.0.0",
        vitalserver_version="2.3.4",
        target_platform="macos-arm64",
    )

    plan = package_clean_plan(root=root, settings=settings, release=release)

    assert settings.pkg_root.parent in plan.paths
    assert settings.app_bundle in plan.paths
    assert all(path.resolve(strict=False).is_relative_to(root) for path in plan.paths)


def test_package_clean_plan_rejects_workspace_root() -> None:
    root = repo_root()
    settings = load_macos_release_settings(root / "config/vm-build.toml", root)
    release = ReleaseManifest(
        channel="dev",
        helper_version="1.2.3",
        release_label="1.2.3-dev",
        minimum_updater_version="1.0.0",
        vitalserver_version="2.3.4",
        target_platform="macos-arm64",
    )
    settings = replace(settings, pkg_root=root / "root")

    with pytest.raises(DomainError, match="unsafe path"):
        package_clean_plan(root=root, settings=settings, release=release)


def test_default_update_migrations_include_guest_runtime_settings_read_model() -> None:
    root = repo_root()

    migrations = default_update_migrations(root / "apps/vitalserver-macos-runtime")

    assert migrations[-1].name == "005-write-guest-runtime-settings-read-model"
    assert all(path.is_file() for path in migrations)
    assert all(path.stat().st_mode & 0o111 for path in migrations)

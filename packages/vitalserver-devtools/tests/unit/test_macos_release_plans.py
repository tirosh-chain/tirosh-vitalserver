from __future__ import annotations

from dataclasses import replace
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release import installer_package
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.guest_services import GuestDeployPlan
from tirosh_vitalserver.devtools.core.macos_release.models import PackageContext
from tirosh_vitalserver.devtools.core.macos_release.release_plans import (
    default_clean_uninstaller_pkg_output,
    default_update_migrations,
    package_clean_plan,
    package_outputs,
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
    assert default_clean_uninstaller_pkg_output(settings, release) in plan.paths
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


def test_default_clean_uninstaller_pkg_output_uses_release_label() -> None:
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

    output = default_clean_uninstaller_pkg_output(settings, release)

    assert output == (
        settings.dist_dir / "VitalServerHelperResetForReinstall-1.2.3-dev.pkg"
    )


def test_package_outputs_include_clean_uninstaller_pkg() -> None:
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

    outputs = package_outputs(
        settings=settings,
        release=release,
        requested_output=None,
        output_kind="dmg",
    )

    assert outputs.pkg_output == settings.dist_dir / "VitalServerHelper-1.2.3-dev.pkg"
    assert outputs.clean_uninstaller_pkg_output == (
        settings.dist_dir / "VitalServerHelperResetForReinstall-1.2.3-dev.pkg"
    )
    assert outputs.dmg_output == settings.dist_dir / "VitalServerHelper-1.2.3-dev.dmg"


def test_build_dmg_stages_installer_and_clean_uninstaller_pkg(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = repo_root()
    settings = load_macos_release_settings(root / "config/vm-build.toml", root)
    staging = tmp_path / "dmg-staging"
    settings = replace(
        settings,
        pkg_root=tmp_path / "build/root",
        dmg_staging_dir=staging,
        outputs=replace(
            settings.outputs,
            dmg_staging_dir=staging,
            dmg_installer_pkg_name="Install VitalServer Helper.pkg",
            dmg_clean_uninstaller_pkg_name=(
                "Troubleshooting Tools/"
                "Reset VitalServer Helper for Reinstall.pkg"
            ),
        ),
    )
    release = ReleaseManifest(
        channel="dev",
        helper_version="1.2.3",
        release_label="1.2.3-dev",
        minimum_updater_version="1.0.0",
        vitalserver_version="2.3.4",
        target_platform="macos-arm64",
    )
    pkg_output = tmp_path / "dist/VitalServerHelper-1.2.3-dev.pkg"
    reset_installer_pkg_output = (
        tmp_path / "dist/VitalServerHelperResetForReinstall-1.2.3-dev.pkg"
    )
    dmg_output = tmp_path / "dist/VitalServerHelper-1.2.3-dev.dmg"
    pkg_output.parent.mkdir()
    pkg_output.write_text("installer", encoding="utf-8")
    commands: list[list[str]] = []

    def fake_build_reset_installer_pkg(**kwargs: object) -> None:
        assert kwargs["pkg_output"] == reset_installer_pkg_output
        reset_installer_pkg_output.write_text("reset-installer", encoding="utf-8")

    def fake_run(command: list[str], **_: object) -> None:
        commands.append(command)

    monkeypatch.setattr(
        installer_package,
        "build_reset_installer_pkg",
        fake_build_reset_installer_pkg,
    )
    monkeypatch.setattr(installer_package, "attached_disk_images", lambda: [])
    monkeypatch.setattr(installer_package, "run", fake_run)

    context = PackageContext(
        root=root,
        runtime_dir=tmp_path / "runtime",
        release=release,
        pkg_root=settings.pkg_root,
        pkg_scripts=tmp_path / "build/scripts",
        pkg_output=pkg_output,
        clean_uninstaller_pkg_output=reset_installer_pkg_output,
        dmg_output=dmg_output,
        app_bundle=tmp_path / "app/VitalServer Helper.app",
        runtime_cli=tmp_path / "bin/vitalserver-vm",
        nginx_bundle=tmp_path / "nginx",
        docker_bundle=tmp_path / "docker-images.tar.gz",
        rootfs_base=tmp_path / "rootfs-base.raw.gz",
        golden_runtime_dir=tmp_path / "golden",
        guest_deploy_plan=GuestDeployPlan(
            support_guest_source=tmp_path / "support-guest",
            deploy_dir=tmp_path / "deploy",
            includes=[],
            python_wheel_projects=[],
            docker_bundle_source=None,
            docker_bundle_destination=None,
            optional_docker_bundle_source=None,
            optional_docker_bundle_destination=None,
            vm_data_dirs=[],
        ),
        proxy_port="80",
        settings=settings,
    )

    installer_package.build_dmg(context)

    assert (staging / "Install VitalServer Helper.pkg").read_text(
        encoding="utf-8"
    ) == "installer"
    assert (
        staging
        / "Troubleshooting Tools/Reset VitalServer Helper for Reinstall.pkg"
    ).read_text(encoding="utf-8") == "reset-installer"
    assert commands[-1][:2] == ["hdiutil", "create"]
    assert str(staging) in commands[-1]
    assert str(dmg_output) in commands[-1]


def test_build_dmg_fails_when_output_dmg_is_attached(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    dmg_output = tmp_path / "dist/VitalServerHelper-1.2.3-dev.dmg"
    monkeypatch.setattr(
        installer_package,
        "attached_disk_images",
        lambda: [
            {
                "image-path": str(dmg_output),
                "system-entities": [
                    {"dev-entry": "/dev/disk5"},
                    {"mount-point": "/Volumes/VitalServer Helper"},
                ],
            }
        ],
    )

    with pytest.raises(RuntimeError, match="DMG output is currently attached"):
        installer_package.ensure_dmg_output_is_not_attached(dmg_output)


def test_default_update_migrations_include_guest_runtime_settings_read_model() -> None:
    root = repo_root()

    migrations = default_update_migrations(root / "apps/vitalserver-macos-runtime")

    assert migrations[-1].name == "005-write-guest-runtime-settings-read-model"
    assert all(path.is_file() for path in migrations)
    assert all(path.stat().st_mode & 0o111 for path in migrations)

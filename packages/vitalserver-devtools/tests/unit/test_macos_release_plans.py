from __future__ import annotations

import subprocess
from dataclasses import replace
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release import installer_package
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import ReleasePackageInput
from tirosh_vitalserver.devtools.application.usecases import macos_package
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
from tirosh_vitalserver.devtools.core.preflight import PreflightStatus
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
        installer_package.detach_unmounted_dmg_output_attachments(dmg_output)


def test_build_dmg_detaches_output_dmg_when_attached_without_mount(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    dmg_output = tmp_path / "dist/VitalServerHelper-1.2.3-dev.dmg"
    commands: list[list[str]] = []
    monkeypatch.setattr(
        installer_package,
        "attached_disk_images",
        lambda: [
            {
                "image-path": str(dmg_output),
                "system-entities": [
                    {"dev-entry": "/dev/disk5"},
                    {"dev-entry": "/dev/disk5s1"},
                ],
            }
        ],
    )
    monkeypatch.setattr(
        installer_package,
        "run",
        lambda command: commands.append(command),
    )

    installer_package.detach_unmounted_dmg_output_attachments(dmg_output)

    assert commands == [["hdiutil", "detach", "/dev/disk5"]]


def test_release_package_preflight_reports_missing_rootfs_before_build(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    golden = tmp_path / "golden"
    golden.mkdir()
    (golden / "Image").write_text("kernel", encoding="utf-8")
    (golden / "initrd.img").write_text("initrd", encoding="utf-8")
    monkeypatch.setattr(macos_package.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(macos_package, "attached_disk_images", lambda: [])
    monkeypatch.setattr(
        macos_package.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args=args[0],
            returncode=0,
            stdout='{"manifests":[{"platform":{"os":"linux","architecture":"arm64"}}]}',
            stderr="",
        ),
    )

    report = macos_package.release_package_preflight_report(
        release_package_input(tmp_path, rootfs_base=tmp_path / "missing.raw.gz"),
        output_kind="pkg",
    )

    rootfs_check = next(check for check in report.checks if check.name == "rootfs-base")
    assert rootfs_check.status == PreflightStatus.MISSING
    assert report.blockers == (rootfs_check,)


def test_release_dmg_preflight_blocks_mounted_output(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = repo_root()
    input = release_package_input(tmp_path)
    settings = load_macos_release_settings(root / "config/vm-build.toml", root)
    release = ReleaseManifest(
        channel="dev",
        helper_version="1.2.3",
        release_label="1.2.3-dev",
        minimum_updater_version="1.0.0",
        vitalserver_version="2.3.4",
        target_platform="macos-arm64",
    )
    dmg_output = package_outputs(
        settings=settings,
        release=release,
        requested_output=input.output,
        output_kind="dmg",
    ).dmg_output
    monkeypatch.setattr(macos_package.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(
        macos_package,
        "load_release_manifest",
        lambda path: release,
    )
    monkeypatch.setattr(
        macos_package,
        "attached_disk_images",
        lambda: [
            {
                "image-path": str(dmg_output),
                "system-entities": [{"mount-point": "/Volumes/VitalServer Helper"}],
            }
        ],
    )
    monkeypatch.setattr(
        macos_package.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args=args[0],
            returncode=0,
            stdout='{"manifests":[{"platform":{"os":"linux","architecture":"arm64"}}]}',
            stderr="",
        ),
    )

    report = macos_package.release_package_preflight_report(input, output_kind="dmg")

    attachment = next(
        check for check in report.checks if check.name == "dmg-output-attachment"
    )
    assert attachment.status == PreflightStatus.BLOCKED
    assert attachment in report.blockers


def test_release_package_preflight_reports_unavailable_docker_manifest(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(macos_package.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(macos_package, "attached_disk_images", lambda: [])
    monkeypatch.setattr(
        macos_package.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args=args[0],
            returncode=1,
            stdout="",
            stderr="manifest unknown",
        ),
    )

    report = macos_package.release_package_preflight_report(
        release_package_input(tmp_path),
        output_kind="pkg",
    )

    manifest_checks = [
        check for check in report.checks if check.name.startswith("docker-manifest:")
    ]
    assert manifest_checks
    assert manifest_checks[0].status == PreflightStatus.UNAVAILABLE
    assert manifest_checks[0] in report.blockers


def test_release_package_preflight_reports_docker_platform_mismatch(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(macos_package.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(
        macos_package.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args=args[0],
            returncode=0,
            stdout='{"manifests":[{"platform":{"os":"linux","architecture":"amd64"}}]}',
            stderr="",
        ),
    )

    report = macos_package.release_package_preflight_report(
        release_package_input(tmp_path),
        output_kind="pkg",
    )

    manifest_checks = [
        check for check in report.checks if check.name.startswith("docker-manifest:")
    ]
    assert manifest_checks
    assert manifest_checks[0].status == PreflightStatus.INVALID
    assert manifest_checks[0] in report.blockers


def test_release_package_preflight_rejects_directory_output(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    output = tmp_path / "dist/output.pkg"
    output.mkdir(parents=True)
    monkeypatch.setattr(macos_package.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(
        macos_package.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args=args[0],
            returncode=0,
            stdout='{"manifests":[{"platform":{"os":"linux","architecture":"arm64"}}]}',
            stderr="",
        ),
    )

    report = macos_package.release_package_preflight_report(
        release_package_input(tmp_path, output=output),
        output_kind="pkg",
    )

    output_check = next(check for check in report.checks if check.name == "pkg-output")
    assert output_check.status == PreflightStatus.INVALID
    assert output_check in report.blockers


def release_package_input(
    tmp_path: Path,
    *,
    rootfs_base: Path | None = None,
    output: Path | None = None,
) -> ReleasePackageInput:
    root = repo_root()
    rootfs = rootfs_base or tmp_path / "rootfs-base.raw.gz"
    golden = tmp_path / "golden"
    golden.mkdir(exist_ok=True)
    if rootfs_base is None:
        rootfs.write_text("rootfs", encoding="utf-8")
    (golden / "Image").write_text("kernel", encoding="utf-8")
    (golden / "initrd.img").write_text("initrd", encoding="utf-8")
    return ReleasePackageInput(
        config=root / "config/vm-build.toml",
        release_file=root / "apps/vitalserver-macos-runtime/release-dev.json",
        output=output or tmp_path / "dist/VitalServerHelper-1.2.3-dev.dmg",
        output_kind="pkg",
        rootfs_base=rootfs,
        golden_runtime_dir=golden,
        proxy_port="80",
        compression_threads=None,
        sdkroot=None,
        clang_module_cache=None,
        codesign_identity="-",
        nginx_binary=None,
        nginx_expected_version=None,
        docker_platform=None,
    )


def test_default_update_migrations_include_guest_runtime_settings_read_model() -> None:
    root = repo_root()

    migrations = default_update_migrations(root / "apps/vitalserver-macos-runtime")

    assert migrations[-1].name == "005-write-guest-runtime-settings-read-model"
    assert all(path.is_file() for path in migrations)
    assert all(path.stat().st_mode & 0o111 for path in migrations)

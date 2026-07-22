from __future__ import annotations

import json
import os
import signal
import subprocess
from dataclasses import replace
from hashlib import sha256
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    REQUIRED_ROOTFS_STAGES,
    ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION,
    rootfs_artifact_manifest_path,
)
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    GUEST_DEPLOY_MATERIAL_DIGEST_VERSION,
    guest_deploy_material_sha256,
)
from tirosh_vitalserver.devtools.adapters.macos_release import installer_package
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    MacOSPackageInstallInput,
    ReleaseDmgArtifactVerifyInput,
    ReleasePackageEnvironmentPreflightInput,
    ReleasePackageInput,
    ReleaseTroubleshootingToolsVerifyInput,
)
from tirosh_vitalserver.devtools.application.usecases import macos_package
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.guest_image import (
    RuntimeDataDiskConfig,
    ubuntu_download_cache_key,
)
from tirosh_vitalserver.devtools.core.guest_services import (
    RootfsInputMetadataPlan,
)
from tirosh_vitalserver.devtools.core.macos_release.install_paths import (
    settings_install_home,
)
from tirosh_vitalserver.devtools.core.macos_release.models import PackageContext
from tirosh_vitalserver.devtools.core.macos_release.release_plans import (
    default_troubleshooting_tools_output,
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
    assert default_troubleshooting_tools_output(settings, release) in plan.paths
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


def test_default_troubleshooting_tools_output_uses_release_label() -> None:
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

    output = default_troubleshooting_tools_output(settings, release)

    assert output == (
        settings.dist_dir / "VitalServerHelperTroubleshootingTools-1.2.3-dev"
    )


def test_package_outputs_include_pkg_and_dmg_outputs() -> None:
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
    assert outputs.dmg_output == settings.dist_dir / "VitalServerHelper-1.2.3-dev.dmg"


def test_build_dmg_stages_installer_and_troubleshooting_command(
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
    dmg_output = tmp_path / "dist/VitalServerHelper-1.2.3-dev.dmg"
    pkg_output.parent.mkdir()
    pkg_output.write_text("installer", encoding="utf-8")
    commands: list[list[str]] = []
    released_outputs: list[Path] = []

    def fake_stage_troubleshooting_tools(**kwargs: object) -> None:
        assert kwargs["runtime_cli"] == tmp_path / "bin/vitalserver-vm"
        tools_dir = kwargs["tools_dir"]
        assert isinstance(tools_dir, Path)
        tools_dir.mkdir(parents=True)
        (tools_dir / "Reset VitalServer Helper for Reinstall.command").write_text(
            "reset-command",
            encoding="utf-8",
        )
        (tools_dir / "bin").mkdir()
        (tools_dir / "bin/vitalserver-vm-reset-installer").write_text(
            "reset-cli",
            encoding="utf-8",
        )
        (tools_dir / "bin/vitalserver-troubleshooting-reset-for-reinstall").write_text(
            "reset-troubleshooting-cli",
            encoding="utf-8",
        )
        (tools_dir / "bin/vitalserver-troubleshooting-upstream-redis-save").write_text(
            "redis-save-cli",
            encoding="utf-8",
        )
        (tools_dir / "Create Upstream Redis Backup.command").write_text(
            "redis-backup-command",
            encoding="utf-8",
        )

    def fake_run(command: list[str], **_: object) -> None:
        commands.append(command)

    monkeypatch.setattr(
        installer_package,
        "stage_troubleshooting_tools",
        fake_stage_troubleshooting_tools,
    )
    monkeypatch.setattr(installer_package, "attached_disk_images", lambda: [])
    monkeypatch.setattr(installer_package, "run", fake_run)
    monkeypatch.setattr(
        installer_package,
        "release_orphaned_dmg_output_helpers",
        released_outputs.append,
    )

    context = PackageContext(
        root=root,
        runtime_dir=tmp_path / "runtime",
        release=release,
        pkg_root=settings.pkg_root,
        pkg_scripts=tmp_path / "build/scripts",
        pkg_output=pkg_output,
        dmg_output=dmg_output,
        app_bundle=tmp_path / "app/VitalServer Helper.app",
        runtime_cli=tmp_path / "bin/vitalserver-vm",
        nginx_bundle=tmp_path / "nginx",
        rootfs_base=tmp_path / "rootfs-base.raw.gz",
        golden_runtime_dir=tmp_path / "golden",
        guest_deploy_source=tmp_path / "compiled-deploy",
        rootfs_input_metadata_plan=RootfsInputMetadataPlan(
            deploy_dir=tmp_path / "deploy",
            base_url="https://example.invalid/noble",
            apt_snapshot="20250515T000000Z",
            runtime_data=RuntimeDataDiskConfig(
                disk_image_name="runtime-data.img",
                disk_size="16G",
                filesystem_label="vital-runtime",
                mount_path="/mnt/runtime",
                docker_data_root="/mnt/runtime/docker",
                containerd_root="/mnt/runtime/containerd",
            ),
            docker_platform="linux/arm64",
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
        / "Troubleshooting Tools/Reset VitalServer Helper for Reinstall.command"
    ).read_text(encoding="utf-8") == "reset-command"
    assert (
        staging / "Troubleshooting Tools/bin/vitalserver-vm-reset-installer"
    ).read_text(encoding="utf-8") == "reset-cli"
    reset_tool = (
        staging
        / "Troubleshooting Tools/bin/vitalserver-troubleshooting-reset-for-reinstall"
    )
    redis_save_tool = (
        staging
        / "Troubleshooting Tools/bin/vitalserver-troubleshooting-upstream-redis-save"
    )
    assert reset_tool.read_text(encoding="utf-8") == "reset-troubleshooting-cli"
    assert redis_save_tool.read_text(encoding="utf-8") == "redis-save-cli"
    assert (
        staging / "Troubleshooting Tools/Create Upstream Redis Backup.command"
    ).read_text(encoding="utf-8") == "redis-backup-command"
    assert commands[-1][:2] == ["hdiutil", "create"]
    assert str(staging) in commands[-1]
    assert str(dmg_output) in commands[-1]
    assert released_outputs == [dmg_output]


def test_release_orphaned_dmg_output_helpers_waits_for_normal_release(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    dmg_output = tmp_path / "VitalServerHelper.dmg"
    holder = installer_package.DmgOutputHolder(
        pid=123,
        parent_pid=77,
        executable=Path("/usr/bin/hdiutil"),
        open_dmg_paths=(dmg_output,),
    )
    observations = iter([[holder], []])
    sent_signals: list[tuple[int, int]] = []

    monkeypatch.setattr(
        installer_package,
        "dmg_output_holders",
        lambda _path: next(observations),
    )
    monkeypatch.setattr(installer_package.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(
        installer_package.os,
        "kill",
        lambda pid, requested_signal: sent_signals.append((pid, requested_signal)),
    )

    installer_package.release_orphaned_dmg_output_helpers(
        dmg_output,
        grace_attempts=2,
        terminate_attempts=1,
        kill_attempts=1,
        poll_seconds=0,
    )

    assert sent_signals == []


def test_dmg_output_holders_reads_explicit_process_ownership(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    dmg_output = tmp_path / "VitalServerHelper.dmg"
    helper = (
        "/System/Library/PrivateFrameworks/DiskImages.framework/"
        "Resources/diskimages-helper"
    )
    responses = iter(
        [
            subprocess.CompletedProcess([], 0, stdout="81947\n", stderr=""),
            subprocess.CompletedProcess(
                [],
                0,
                stdout=f"1 {helper}\n",
                stderr="",
            ),
            subprocess.CompletedProcess(
                [],
                0,
                stdout=f"p81947\nfcwd\nn{tmp_path}\nf5\nn{dmg_output}\n",
                stderr="",
            ),
        ]
    )

    monkeypatch.setattr(
        installer_package.shutil,
        "which",
        lambda name: f"/usr/bin/{name}",
    )
    monkeypatch.setattr(
        installer_package,
        "run_inspection_command",
        lambda *_args, **_kwargs: next(responses),
    )

    assert installer_package.dmg_output_holders(dmg_output) == [
        installer_package.DmgOutputHolder(
            pid=81947,
            parent_pid=1,
            executable=Path(helper),
            open_dmg_paths=(dmg_output,),
        )
    ]


def test_release_orphaned_dmg_output_helpers_terminates_exact_orphan(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    dmg_output = tmp_path / "VitalServerHelper.dmg"
    holder = installer_package.DmgOutputHolder(
        pid=81947,
        parent_pid=1,
        executable=Path(
            "/System/Library/PrivateFrameworks/DiskImages.framework/"
            "Resources/diskimages-helper"
        ),
        open_dmg_paths=(dmg_output,),
    )
    observations = iter([[holder], [holder], []])
    sent_signals: list[tuple[int, int]] = []

    monkeypatch.setattr(
        installer_package,
        "dmg_output_holders",
        lambda _path: next(observations),
    )
    monkeypatch.setattr(installer_package.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(
        installer_package.os,
        "kill",
        lambda pid, requested_signal: sent_signals.append((pid, requested_signal)),
    )

    installer_package.release_orphaned_dmg_output_helpers(
        dmg_output,
        grace_attempts=1,
        terminate_attempts=1,
        kill_attempts=1,
        poll_seconds=0,
    )

    assert sent_signals == [
        (81947, signal.SIGTERM),
        (81947, signal.SIGKILL),
    ]


def test_release_orphaned_dmg_output_helpers_rejects_unowned_holder(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    dmg_output = tmp_path / "VitalServerHelper.dmg"
    other_dmg = tmp_path / "OperatorMounted.dmg"
    holder = installer_package.DmgOutputHolder(
        pid=456,
        parent_pid=1,
        executable=Path(
            "/System/Library/PrivateFrameworks/DiskImages.framework/"
            "Resources/diskimages-helper"
        ),
        open_dmg_paths=(dmg_output, other_dmg),
    )
    sent_signals: list[tuple[int, int]] = []

    monkeypatch.setattr(
        installer_package,
        "dmg_output_holders",
        lambda _path: [holder],
    )
    monkeypatch.setattr(installer_package.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(
        installer_package.os,
        "kill",
        lambda pid, requested_signal: sent_signals.append((pid, requested_signal)),
    )

    with pytest.raises(
        RuntimeError,
        match=r"refusing to signal.*pid=456.*OperatorMounted\.dmg",
    ):
        installer_package.release_orphaned_dmg_output_helpers(
            dmg_output,
            grace_attempts=1,
            terminate_attempts=1,
            kill_attempts=1,
            poll_seconds=0,
        )

    assert sent_signals == []


def test_attached_disk_images_reports_hdiutil_info_timeout(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def timeout(*args: object, **kwargs: object) -> subprocess.CompletedProcess[bytes]:
        raise subprocess.TimeoutExpired(cmd=["hdiutil", "info", "-plist"], timeout=10)

    monkeypatch.setattr(installer_package.subprocess, "run", timeout)

    with pytest.raises(
        RuntimeError,
        match="timed out after 10 seconds",
    ):
        installer_package.attached_disk_images()


def test_stage_reset_installer_command_renders_command_and_bundles_cli(
    tmp_path: Path,
) -> None:
    root = repo_root()
    settings = load_macos_release_settings(root / "config/vm-build.toml", root)
    settings = replace(settings, pkg_root=tmp_path / "build/root")
    runtime_dir = root / "apps/vitalserver-macos-runtime"
    runtime_cli = tmp_path / "bin/vitalserver-vm"
    runtime_cli.parent.mkdir(parents=True)
    runtime_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    runtime_cli.chmod(0o755)
    reset_troubleshooting_cli = (
        tmp_path / "bin/vitalserver-troubleshooting-reset-for-reinstall"
    )
    reset_troubleshooting_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    reset_troubleshooting_cli.chmod(0o755)
    upstream_redis_save_cli = (
        tmp_path / "bin/vitalserver-troubleshooting-upstream-redis-save"
    )
    upstream_redis_save_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    upstream_redis_save_cli.chmod(0o755)
    tools_dir = tmp_path / "Troubleshooting Tools"

    installer_package.stage_reset_installer_command(
        settings=settings,
        runtime_dir=runtime_dir,
        runtime_cli=runtime_cli,
        tools_dir=tools_dir,
    )

    command = tools_dir / "Reset VitalServer Helper for Reinstall.command"
    cli = tools_dir / "bin/vitalserver-vm-reset-installer"
    command_text = command.read_text(encoding="utf-8")

    assert command.is_file()
    assert cli.is_file()
    assert os.access(command, os.X_OK)
    assert os.access(cli, os.X_OK)
    assert (
        'reset_bin="${script_dir}/bin/vitalserver-troubleshooting-reset-for-reinstall"'
        in command_text
    )
    assert 'exec /usr/bin/sudo "$0" "$@"' in command_text
    assert (
        'wrapper_log="${wrapper_log_dir%/}/tirosh-vitalserver-reset-for-reinstall.log"'
        in command_text
    )
    assert 'VITALSERVER_VM_HOME="${vm_home}" "${reset_bin}"' in command_text


def test_stage_troubleshooting_tools_stages_reset_and_redis_commands(
    tmp_path: Path,
) -> None:
    root = repo_root()
    settings = load_macos_release_settings(root / "config/vm-build.toml", root)
    settings = replace(settings, pkg_root=tmp_path / "build/root")
    runtime_dir = root / "apps/vitalserver-macos-runtime"
    runtime_cli = tmp_path / "bin/vitalserver-vm"
    runtime_cli.parent.mkdir(parents=True)
    runtime_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    runtime_cli.chmod(0o755)
    reset_troubleshooting_cli = (
        tmp_path / "bin/vitalserver-troubleshooting-reset-for-reinstall"
    )
    reset_troubleshooting_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    reset_troubleshooting_cli.chmod(0o755)
    upstream_redis_save_cli = (
        tmp_path / "bin/vitalserver-troubleshooting-upstream-redis-save"
    )
    upstream_redis_save_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    upstream_redis_save_cli.chmod(0o755)
    tools_dir = tmp_path / "Troubleshooting Tools"

    installer_package.stage_troubleshooting_tools(
        settings=settings,
        runtime_dir=runtime_dir,
        runtime_cli=runtime_cli,
        tools_dir=tools_dir,
    )

    reset_command = tools_dir / "Reset VitalServer Helper for Reinstall.command"
    redis_command = tools_dir / "Create Upstream Redis Backup.command"
    cli = tools_dir / "bin/vitalserver-vm-reset-installer"
    reset_cli = tools_dir / "bin/vitalserver-troubleshooting-reset-for-reinstall"
    redis_save_cli = tools_dir / "bin/vitalserver-troubleshooting-upstream-redis-save"
    redis_command_text = redis_command.read_text(encoding="utf-8")

    assert reset_command.is_file()
    assert redis_command.is_file()
    assert cli.is_file()
    assert reset_cli.is_file()
    assert redis_save_cli.is_file()
    assert os.access(reset_command, os.X_OK)
    assert os.access(redis_command, os.X_OK)
    assert os.access(cli, os.X_OK)
    assert os.access(reset_cli, os.X_OK)
    assert os.access(redis_save_cli, os.X_OK)
    assert "vitalserver-troubleshooting-upstream-redis-save" in redis_command_text
    assert 'archive_name="redis-upstream-import.tar.gz"' in redis_command_text
    assert (
        'log_file="${log_dir%/}/tirosh-vitalserver-upstream-redis-backup.log"'
        in redis_command_text
    )
    assert "dump.rdb" in redis_command_text
    assert 'COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 \\' in (
        redis_command_text
    )
    assert '/usr/bin/tar -czf "${archive}" -C "${source_dir}" .' in (
        redis_command_text
    )


def test_troubleshooting_tools_verify_accepts_staged_commands(
    tmp_path: Path,
) -> None:
    root = repo_root()
    tools_dir = stage_troubleshooting_tools_for_test(tmp_path)

    report = macos_package.troubleshooting_tools_report(
        ReleaseTroubleshootingToolsVerifyInput(
            config=root / "config/vm-build.toml",
            release_file=root / "apps/vitalserver-macos-runtime/release-dev.json",
            output=tools_dir,
        )
    )

    assert report.passed


def test_troubleshooting_tools_verify_requires_wrapper_log_before_sudo(
    tmp_path: Path,
) -> None:
    root = repo_root()
    tools_dir = stage_troubleshooting_tools_for_test(tmp_path)
    reset_command = tools_dir / "Reset VitalServer Helper for Reinstall.command"
    reset_command.write_text(
        reset_command.read_text(encoding="utf-8").replace(
            'exec > >(tee -a "${wrapper_log}") 2>&1',
            'exec > >(tee -a "${uninstall_log}") 2>&1',
        ),
        encoding="utf-8",
    )

    report = macos_package.troubleshooting_tools_report(
        ReleaseTroubleshootingToolsVerifyInput(
            config=root / "config/vm-build.toml",
            release_file=root / "apps/vitalserver-macos-runtime/release-dev.json",
            output=tools_dir,
        )
    )

    user_log_check = next(
        check
        for check in report.checks
        if check.name == "troubleshooting-reset-command-wrapper-log"
    )
    assert user_log_check.status == PreflightStatus.INVALID
    assert user_log_check in report.blockers


def stage_troubleshooting_tools_for_test(tmp_path: Path) -> Path:
    root = repo_root()
    settings = load_macos_release_settings(root / "config/vm-build.toml", root)
    settings = replace(settings, pkg_root=tmp_path / "build/root")
    runtime_dir = root / "apps/vitalserver-macos-runtime"
    runtime_cli = tmp_path / "bin/vitalserver-vm"
    runtime_cli.parent.mkdir(parents=True)
    runtime_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    runtime_cli.chmod(0o755)
    reset_troubleshooting_cli = (
        tmp_path / "bin/vitalserver-troubleshooting-reset-for-reinstall"
    )
    reset_troubleshooting_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    reset_troubleshooting_cli.chmod(0o755)
    upstream_redis_save_cli = (
        tmp_path / "bin/vitalserver-troubleshooting-upstream-redis-save"
    )
    upstream_redis_save_cli.write_text("#!/bin/sh\n", encoding="utf-8")
    upstream_redis_save_cli.chmod(0o755)
    tools_dir = tmp_path / "Troubleshooting Tools"
    installer_package.stage_troubleshooting_tools(
        settings=settings,
        runtime_dir=runtime_dir,
        runtime_cli=runtime_cli,
        tools_dir=tools_dir,
    )
    return tools_dir


def test_build_pkg_materializes_compiled_guest_deploy_for_installed_bootstrap(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = tmp_path / "repo"
    runtime_dir = root / "apps/vitalserver-macos-runtime"
    packaging_dir = runtime_dir / "Support/Packaging"
    packaging_dir.mkdir(parents=True)
    for name in [
        "preinstall",
        "proxy-run.template",
        "uninstall.template",
        "postinstall.template",
        "components.plist.template",
    ]:
        path = packaging_dir / name
        path.write_text("#!/bin/sh\n", encoding="utf-8")
        path.chmod(0o755)
    (runtime_dir / "Entitlements.shared.plist").write_text(
        "<plist></plist>",
        encoding="utf-8",
    )
    (root / "infra/macos-nginx").mkdir(parents=True)
    (root / "infra/macos-nginx/vitalserver.conf.template").write_text(
        "proxy",
        encoding="utf-8",
    )
    app_bundle = tmp_path / "VitalServer Helper.app"
    app_bundle.mkdir()
    (app_bundle / "Contents").mkdir()
    nginx_bundle = tmp_path / "nginx"
    nginx_bundle.mkdir()
    (nginx_bundle / "nginx").write_text("nginx", encoding="utf-8")
    runtime_cli = tmp_path / "vitalserver-vm"
    runtime_cli.write_text("vm", encoding="utf-8")
    runtime_cli.chmod(0o755)
    rootfs_base = tmp_path / "rootfs-base.raw.gz"
    rootfs_base.write_text("rootfs", encoding="utf-8")
    rootfs_manifest = rootfs_artifact_manifest_path(rootfs_base)
    docker_bundle = tmp_path / "docker-images.tar.gz"
    docker_bundle.write_text("docker", encoding="utf-8")
    compiled_deploy = tmp_path / "compiled-deploy"
    (compiled_deploy / "build-metadata").mkdir(parents=True)
    (compiled_deploy / "build-metadata/rootfs-input.json").write_text(
        json.dumps(rootfs_input_metadata(run_id="golden-run")) + "\n",
        encoding="utf-8",
    )
    (compiled_deploy / "bootstrap.sh").write_text(
        "#!/bin/sh\ncompiled deploy\n",
        encoding="utf-8",
    )
    (compiled_deploy / "host-time.json").write_text(
        '{"epochSeconds":1}\n',
        encoding="utf-8",
    )
    write_rootfs_artifact_receipt(rootfs_base, compiled_deploy)
    golden = tmp_path / "golden"
    golden.mkdir()
    (golden / "Image").write_text("kernel", encoding="utf-8")
    (golden / "initrd.img").write_text("initrd", encoding="utf-8")

    settings = load_macos_release_settings(repo_root() / "config/vm-build.toml", root)
    settings = replace(
        settings,
        runtime_dir=runtime_dir,
        app_bundle=app_bundle,
        runtime_cli=runtime_cli,
        nginx_bundle=nginx_bundle,
        docker_bundle=docker_bundle,
        pkg_root=tmp_path / "pkg-root",
        pkg_scripts=tmp_path / "pkg-scripts",
        pkg_component_plist=tmp_path / "components.plist",
    )
    package_vm_home = settings.pkg_root / settings_install_home(settings).strip("/")
    context = PackageContext(
        root=root,
        runtime_dir=runtime_dir,
        release=ReleaseManifest(
            channel="dev",
            helper_version="1.2.3",
            release_label="1.2.3-dev",
            minimum_updater_version="1.0.0",
            vitalserver_version="2.3.4",
            target_platform="macos-arm64",
        ),
        pkg_root=settings.pkg_root,
        pkg_scripts=settings.pkg_scripts,
        pkg_output=tmp_path / "dist/VitalServerHelper-1.2.3-dev.pkg",
        dmg_output=tmp_path / "dist/VitalServerHelper-1.2.3-dev.dmg",
        app_bundle=app_bundle,
        runtime_cli=runtime_cli,
        nginx_bundle=nginx_bundle,
        rootfs_base=rootfs_base,
        golden_runtime_dir=golden,
        guest_deploy_source=compiled_deploy,
        rootfs_input_metadata_plan=RootfsInputMetadataPlan(
            deploy_dir=package_vm_home / "data/deploy",
            base_url="https://example.invalid/noble",
            apt_snapshot="20250515T000000Z",
            runtime_data=RuntimeDataDiskConfig(
                disk_image_name="runtime-data.img",
                disk_size="16G",
                filesystem_label="vital-runtime",
                mount_path="/mnt/runtime",
                docker_data_root="/mnt/runtime/docker",
                containerd_root="/mnt/runtime/containerd",
            ),
            docker_platform="linux/arm64",
        ),
        proxy_port="80",
        settings=settings,
    )
    commands: list[list[str]] = []
    monkeypatch.setattr(
        installer_package,
        "run",
        lambda command, **_: commands.append(command),
    )
    monkeypatch.setattr(
        installer_package,
        "assert_virtualization_entitlement",
        lambda _: None,
    )
    monkeypatch.setattr(installer_package, "render_launchd_templates", lambda _: None)
    monkeypatch.setattr(
        installer_package,
        "render_packaging_executable",
        lambda _settings, _template, destination: destination.write_text(
            "#!/bin/sh\n",
            encoding="utf-8",
        ),
    )
    monkeypatch.setattr(
        installer_package,
        "render_packaging_template",
        lambda _settings, _template, destination, _values: destination.write_text(
            "<plist></plist>",
            encoding="utf-8",
        ),
    )

    installer_package.build_pkg(context)

    metadata = package_vm_home / "data/deploy/build-metadata/rootfs-input.json"
    assert metadata.is_file()
    document = json.loads(metadata.read_text(encoding="utf-8"))
    assert document["runtimeData"]["diskImageName"] == "runtime-data.img"
    assert document["runtimeData"]["mountPath"] == "/mnt/runtime"
    assert document["dockerImages"]["platform"] == "linux/arm64"
    assert document["ubuntu"]["aptSnapshot"] == "20250515T000000Z"
    assert "runId" not in document
    assert (
        package_vm_home / "data/deploy/bootstrap.sh"
    ).read_text(encoding="utf-8") == "#!/bin/sh\ncompiled deploy\n"
    assert not (package_vm_home / "data/deploy/host-time.json").exists()
    assert (
        package_vm_home / "runtime" / rootfs_manifest.name
    ).read_text(encoding="utf-8") == rootfs_manifest.read_text(encoding="utf-8")
    assert any(command[0] == "pkgbuild" for command in commands)

    commands.clear()
    mismatched_context = replace(
        context,
        rootfs_input_metadata_plan=replace(
            context.rootfs_input_metadata_plan,
            apt_snapshot="20260611T000000Z",
        ),
    )
    with pytest.raises(SystemExit, match="does not match rootfs artifact receipt"):
        installer_package.build_pkg(mismatched_context)
    assert not any(command[0] == "pkgbuild" for command in commands)


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


def test_build_dmg_forces_detach_when_unmounted_attachment_is_busy(
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
                "system-entities": [{"dev-entry": "/dev/disk5"}],
            }
        ],
    )

    def run(command: list[str]) -> None:
        commands.append(command)
        if command == ["hdiutil", "detach", "/dev/disk5"]:
            raise subprocess.CalledProcessError(16, command)

    monkeypatch.setattr(installer_package, "run", run)

    installer_package.detach_unmounted_dmg_output_attachments(dmg_output)

    assert commands == [
        ["hdiutil", "detach", "/dev/disk5"],
        ["hdiutil", "detach", "-force", "/dev/disk5"],
    ]


def test_detach_dmg_attachment_prefers_device_entry_and_forces_after_failure(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    mount = tmp_path / "mount"
    mount.mkdir()
    commands: list[list[str]] = []

    def run(command: list[str]) -> None:
        commands.append(command)
        if command == ["hdiutil", "detach", "/dev/disk9"]:
            raise subprocess.CalledProcessError(16, command)

    monkeypatch.setattr(installer_package, "run", run)

    installer_package.detach_dmg_attachment(
        installer_package.DmgAttachment(
            mount_point=mount,
            device_entry="/dev/disk9",
        )
    )

    assert commands == [
        ["hdiutil", "detach", "/dev/disk9"],
        ["hdiutil", "detach", "-force", "/dev/disk9"],
    ]


def test_detach_dmg_attachment_reports_force_failure(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    mount = tmp_path / "mount"
    mount.mkdir()

    def run(command: list[str]) -> None:
        raise subprocess.CalledProcessError(16, command)

    monkeypatch.setattr(installer_package, "run", run)

    with pytest.raises(RuntimeError, match="force detach exited 16"):
        installer_package.detach_dmg_attachment(
            installer_package.DmgAttachment(
                mount_point=mount,
                device_entry="/dev/disk9",
            )
        )


def rootfs_input_metadata(*, run_id: str | None = None) -> dict[str, object]:
    document: dict[str, object] = {
        "schemaVersion": 1,
        "guestClockUtc": "2026-06-11T00:00:00Z",
        "runtimeBootSmoke": {"enabled": False},
        "dockerImages": {"platform": "linux/arm64"},
        "runtimeData": {
            "diskImageName": "runtime-data.img",
            "diskSize": "16G",
            "filesystemLabel": "vital-runtime",
            "mountPath": "/mnt/runtime",
            "dockerDataRoot": "/mnt/runtime/docker",
            "containerdRoot": "/mnt/runtime/containerd",
        },
        "ubuntu": {
            "aptSnapshot": "20250515T000000Z",
            "baseUrl": "https://example.invalid/noble",
            "cacheKey": ubuntu_download_cache_key("https://example.invalid/noble"),
        },
    }
    if run_id is not None:
        document["runId"] = run_id
    return document


def write_rootfs_artifact_receipt(rootfs: Path, deploy: Path) -> None:
    rootfs_artifact_manifest_path(rootfs).write_text(
        json.dumps(
            {
                "schemaVersion": ROOTFS_ARTIFACT_MANIFEST_SCHEMA_VERSION,
                "artifact": {"sha256": sha256(rootfs.read_bytes()).hexdigest()},
                "guestDeploy": {
                    "path": "data/deploy",
                    "materialDigestVersion": GUEST_DEPLOY_MATERIAL_DIGEST_VERSION,
                    "materialSha256": guest_deploy_material_sha256(deploy),
                },
                "source": {"runId": "rootfs-run"},
                "proof": {
                    "cleanupStatus": "passed",
                    "requiredStages": list(REQUIRED_ROOTFS_STAGES),
                },
            }
        ),
        encoding="utf-8",
    )


def write_expanded_dmg_pkg_payload(destination: Path) -> Path:
    assert not destination.exists()
    payload = destination / "Payload"
    installed_home = (
        payload / "Library/Application Support/VitalServerHelper/vm"
    )
    rootfs = installed_home / "runtime" / "rootfs-base.raw.gz"
    rootfs.parent.mkdir(parents=True)
    rootfs.write_bytes(b"rootfs")
    deploy = installed_home / "data" / "deploy"
    (deploy / "build-metadata").mkdir(parents=True)
    (deploy / "build-metadata/rootfs-input.json").write_text(
        json.dumps(rootfs_input_metadata()) + "\n",
        encoding="utf-8",
    )
    (deploy / "host-time.json").write_text(
        '{"updatedAt":"2026-06-11T00:00:01Z"}\n',
        encoding="utf-8",
    )
    (deploy / "bootstrap.sh").write_text("#!/bin/sh\n", encoding="utf-8")
    write_rootfs_artifact_receipt(rootfs, deploy)
    return payload


def test_release_dmg_artifact_verify_accepts_expected_layout(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = repo_root()
    dmg_output = tmp_path / "dist/VitalServerHelper-1.2.3-dev.dmg"
    dmg_output.parent.mkdir()
    dmg_output.write_text("dmg", encoding="utf-8")
    mount = tmp_path / "mount"
    tools = mount / "Troubleshooting Tools"
    (tools / "bin").mkdir(parents=True)
    (mount / "Install VitalServer Helper.pkg").write_text(
        "pkg",
        encoding="utf-8",
    )
    for path in [
        tools / "Reset VitalServer Helper for Reinstall.command",
        tools / "Create Upstream Redis Backup.command",
        tools / "bin/vitalserver-troubleshooting-reset-for-reinstall",
        tools / "bin/vitalserver-troubleshooting-upstream-redis-save",
    ]:
        path.write_text("#!/bin/sh\n", encoding="utf-8")
        path.chmod(0o755)
    detached: list[installer_package.DmgAttachment] = []

    monkeypatch.setattr(macos_package.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(
        macos_package,
        "load_release_manifest",
        lambda path: ReleaseManifest(
            channel="dev",
            helper_version="1.2.3",
            release_label="1.2.3-dev",
            minimum_updater_version="1.0.0",
            vitalserver_version="2.3.4",
            target_platform="macos-arm64",
        ),
    )
    monkeypatch.setattr(macos_package, "hdiutil_verify_image", lambda path: None)
    monkeypatch.setattr(
        macos_package,
        "expand_pkg_payload",
        lambda _package, destination: write_expanded_dmg_pkg_payload(destination),
    )
    monkeypatch.setattr(
        macos_package,
        "attach_dmg_readonly",
        lambda path: installer_package.DmgAttachment(
            mount_point=mount,
            device_entry="/dev/disk9",
        ),
    )
    monkeypatch.setattr(macos_package, "detach_dmg_attachment", detached.append)

    report = macos_package.release_dmg_artifact_report(
        ReleaseDmgArtifactVerifyInput(
            config=root / "config/vm-build.toml",
            release_file=root / "apps/vitalserver-macos-runtime/release-dev.json",
            output=dmg_output,
        )
    )

    assert report.passed
    assert detached == [
        installer_package.DmgAttachment(mount_point=mount, device_entry="/dev/disk9")
    ]


def test_verify_dmg_pkg_rootfs_material_rejects_guest_deploy_digest_mismatch(
    tmp_path: Path,
) -> None:
    payload = write_expanded_dmg_pkg_payload(tmp_path / "expanded")
    deploy = (
        payload
        / "Library/Application Support/VitalServerHelper/vm/data/deploy"
    )
    (deploy / "bootstrap.sh").write_text("tampered\n", encoding="utf-8")

    checks = macos_package.verify_dmg_pkg_rootfs_material(
        payload=payload,
        install_home_path="/Library/Application Support/VitalServerHelper/vm",
    )

    material = next(
        check
        for check in checks
        if check.name == "dmg-payload-guest-deploy-material-sha256"
    )
    assert material.status == PreflightStatus.FAILED


def test_verify_dmg_pkg_rootfs_material_rejects_missing_compile_proof(
    tmp_path: Path,
) -> None:
    payload = write_expanded_dmg_pkg_payload(tmp_path / "expanded")
    rootfs = (
        payload
        / "Library/Application Support/VitalServerHelper/vm/runtime/rootfs-base.raw.gz"
    )
    manifest = rootfs_artifact_manifest_path(rootfs)
    document = json.loads(manifest.read_text(encoding="utf-8"))
    del document["proof"]
    manifest.write_text(json.dumps(document), encoding="utf-8")

    checks = macos_package.verify_dmg_pkg_rootfs_material(
        payload=payload,
        install_home_path="/Library/Application Support/VitalServerHelper/vm",
    )

    proof = next(
        check
        for check in checks
        if check.name == "dmg-payload-rootfs-receipt"
        and check.status == PreflightStatus.INVALID
    )
    assert proof.message == "packaged rootfs receipt is invalid"


def test_release_dmg_artifact_verify_reports_missing_troubleshooting_command(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = repo_root()
    dmg_output = tmp_path / "dist/VitalServerHelper-1.2.3-dev.dmg"
    dmg_output.parent.mkdir()
    dmg_output.write_text("dmg", encoding="utf-8")
    mount = tmp_path / "mount"
    tools = mount / "Troubleshooting Tools"
    (tools / "bin").mkdir(parents=True)
    (mount / "Install VitalServer Helper.pkg").write_text(
        "pkg",
        encoding="utf-8",
    )
    for path in [
        tools / "Reset VitalServer Helper for Reinstall.command",
        tools / "bin/vitalserver-troubleshooting-reset-for-reinstall",
        tools / "bin/vitalserver-troubleshooting-upstream-redis-save",
    ]:
        path.write_text("#!/bin/sh\n", encoding="utf-8")
        path.chmod(0o755)

    monkeypatch.setattr(macos_package.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(
        macos_package,
        "load_release_manifest",
        lambda path: ReleaseManifest(
            channel="dev",
            helper_version="1.2.3",
            release_label="1.2.3-dev",
            minimum_updater_version="1.0.0",
            vitalserver_version="2.3.4",
            target_platform="macos-arm64",
        ),
    )
    monkeypatch.setattr(macos_package, "hdiutil_verify_image", lambda path: None)
    monkeypatch.setattr(
        macos_package,
        "expand_pkg_payload",
        lambda _package, destination: write_expanded_dmg_pkg_payload(destination),
    )
    monkeypatch.setattr(
        macos_package,
        "attach_dmg_readonly",
        lambda path: installer_package.DmgAttachment(
            mount_point=mount,
            device_entry="/dev/disk9",
        ),
    )
    monkeypatch.setattr(macos_package, "detach_dmg_attachment", lambda _: None)

    report = macos_package.release_dmg_artifact_report(
        ReleaseDmgArtifactVerifyInput(
            config=root / "config/vm-build.toml",
            release_file=root / "apps/vitalserver-macos-runtime/release-dev.json",
            output=dmg_output,
        )
    )

    redis_command = next(
        check
        for check in report.checks
        if check.name == "dmg-upstream-redis-backup-command"
    )
    assert redis_command.status == PreflightStatus.MISSING
    assert redis_command in report.blockers


def test_release_dmg_artifact_verify_reports_detach_failure(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = repo_root()
    dmg_output = tmp_path / "dist/VitalServerHelper-1.2.3-dev.dmg"
    dmg_output.parent.mkdir()
    dmg_output.write_text("dmg", encoding="utf-8")
    mount = tmp_path / "mount"
    tools = mount / "Troubleshooting Tools"
    (tools / "bin").mkdir(parents=True)
    (mount / "Install VitalServer Helper.pkg").write_text(
        "pkg",
        encoding="utf-8",
    )
    for path in [
        tools / "Reset VitalServer Helper for Reinstall.command",
        tools / "Create Upstream Redis Backup.command",
        tools / "bin/vitalserver-troubleshooting-reset-for-reinstall",
        tools / "bin/vitalserver-troubleshooting-upstream-redis-save",
    ]:
        path.write_text("#!/bin/sh\n", encoding="utf-8")
        path.chmod(0o755)

    monkeypatch.setattr(macos_package.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(
        macos_package,
        "load_release_manifest",
        lambda path: ReleaseManifest(
            channel="dev",
            helper_version="1.2.3",
            release_label="1.2.3-dev",
            minimum_updater_version="1.0.0",
            vitalserver_version="2.3.4",
            target_platform="macos-arm64",
        ),
    )
    monkeypatch.setattr(macos_package, "hdiutil_verify_image", lambda path: None)
    monkeypatch.setattr(
        macos_package,
        "expand_pkg_payload",
        lambda _package, destination: write_expanded_dmg_pkg_payload(destination),
    )
    monkeypatch.setattr(
        macos_package,
        "attach_dmg_readonly",
        lambda path: installer_package.DmgAttachment(
            mount_point=mount,
            device_entry="/dev/disk9",
        ),
    )

    def fail_detach(_: installer_package.DmgAttachment) -> None:
        raise RuntimeError("detach failed")

    monkeypatch.setattr(macos_package, "detach_dmg_attachment", fail_detach)

    report = macos_package.release_dmg_artifact_report(
        ReleaseDmgArtifactVerifyInput(
            config=root / "config/vm-build.toml",
            release_file=root / "apps/vitalserver-macos-runtime/release-dev.json",
            output=dmg_output,
        )
    )

    detach = next(check for check in report.checks if check.name == "dmg-detach")
    assert detach.status == PreflightStatus.FAILED
    assert detach in report.blockers


def test_install_pkg_reports_sudo_failure_without_traceback(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    root = repo_root()
    release_file = tmp_path / "release-dev.json"
    release_file.write_text(
        json.dumps(
                {
                    "channel": "dev",
                    "helperVersion": "1.2.3",
                    "releaseLabel": "1.2.3-dev",
                    "minUpdaterVersion": "1.0.0",
                    "vitalServerVersion": "2.3.4",
                    "targetPlatform": "macos-arm64",
                    "services": {
                        "lab": {
                            "image": "vitalserver-lab:0.2.0",
                        },
                        "postgres": {
                            "image": "postgres:16-alpine",
                        },
                    },
                }
            ),
            encoding="utf-8",
        )
    pkg_output = tmp_path / "dist/VitalServerHelper-1.2.3-dev.pkg"
    pkg_output.parent.mkdir(exist_ok=True)
    pkg_output.write_text("pkg", encoding="utf-8")
    monkeypatch.setattr(
        macos_package,
        "default_pkg_output",
        lambda settings, release: pkg_output,
    )

    def fail_run(command: list[str]) -> None:
        raise subprocess.CalledProcessError(1, command)

    monkeypatch.setattr(macos_package, "run", fail_run)

    with pytest.raises(SystemExit) as error:
        macos_package.install_pkg(
            MacOSPackageInstallInput(
                config=root / "config/vm-build.toml",
                release_file=release_file,
                install_settings=None,
            )
        )

    assert "installer command failed exitCode=1" in str(error.value)
    assert "interactive administrator shell" in str(error.value)


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


def test_release_package_environment_preflight_does_not_require_rootfs(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(macos_package.shutil, "which", lambda name: f"/usr/bin/{name}")
    monkeypatch.setattr(macos_package, "attached_disk_images", lambda: [])

    report = macos_package.release_package_environment_preflight_report(
        ReleasePackageEnvironmentPreflightInput(
            config=repo_root() / "config/vm-build.toml",
            release_file=repo_root()
            / "apps/vitalserver-macos-runtime/release-dev.json",
            output=tmp_path / "dist/VitalServerHelper.dmg",
            output_kind="dmg",
        )
    )

    assert report.passed
    assert all("rootfs" not in check.name for check in report.checks)


def test_release_package_preflight_reuses_compiled_guest_material_without_docker(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    rootfs = tmp_path / "rootfs-base.raw.gz"
    rootfs.write_bytes(b"rootfs")
    compiled_deploy = tmp_path / "compiled-deploy"
    (compiled_deploy / "build-metadata").mkdir(parents=True)
    (compiled_deploy / "build-metadata/rootfs-input.json").write_text(
        json.dumps(rootfs_input_metadata()) + "\n",
        encoding="utf-8",
    )
    (compiled_deploy / "bootstrap.sh").write_text("#!/bin/sh\n", encoding="utf-8")
    write_rootfs_artifact_receipt(rootfs, compiled_deploy)
    monkeypatch.setattr(
        macos_package.shutil,
        "which",
        lambda name: None if name == "docker" else f"/usr/bin/{name}",
    )
    report = macos_package.release_package_preflight_report(
        release_package_input(
            tmp_path,
            rootfs_base=rootfs,
            guest_deploy_source=compiled_deploy,
        ),
        output_kind="pkg",
    )

    assert report.passed
    compiled = next(
        check for check in report.checks if check.name == "compiled-guest-deploy"
    )
    assert compiled.status == PreflightStatus.PASSED


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
    guest_deploy_source: Path | None = None,
) -> ReleasePackageInput:
    root = repo_root()
    rootfs = rootfs_base or tmp_path / "rootfs-base.raw.gz"
    compiled_deploy = guest_deploy_source or tmp_path / "compiled-deploy"
    golden = tmp_path / "golden"
    golden.mkdir(exist_ok=True)
    if rootfs_base is None:
        rootfs.write_text("rootfs", encoding="utf-8")
    if not compiled_deploy.exists():
        (compiled_deploy / "build-metadata").mkdir(parents=True)
        (compiled_deploy / "build-metadata/rootfs-input.json").write_text(
            json.dumps(rootfs_input_metadata()) + "\n",
            encoding="utf-8",
        )
        (compiled_deploy / "bootstrap.sh").write_text(
            "#!/bin/sh\n",
            encoding="utf-8",
        )
    manifest = rootfs_artifact_manifest_path(rootfs)
    if rootfs.is_file() and not manifest.exists():
        write_rootfs_artifact_receipt(rootfs, compiled_deploy)
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
        guest_deploy_source=compiled_deploy,
    )


def test_default_update_migrations_include_current_baseline_migrations() -> None:
    root = repo_root()

    migrations = default_update_migrations(root / "apps/vitalserver-macos-runtime")

    assert migrations[-1].name == "004-refresh-vm-shutdown-timeouts"
    assert all(path.is_file() for path in migrations)
    assert all(path.stat().st_mode & 0o111 for path in migrations)

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.adapters.guest_image.rootfs_base import (
    require_rootfs_artifact_guest_deploy_match,
    require_rootfs_artifact_guest_deploy_material_sha256,
    require_rootfs_artifact_receipt,
    rootfs_artifact_manifest_path,
)
from tirosh_vitalserver.devtools.adapters.guest_services.deploy_bundle import (
    guest_deploy_material_sha256,
)
from tirosh_vitalserver.devtools.adapters.macos_release.artifact_files import (
    remove_path,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_package import (
    attach_dmg_readonly,
    attached_disk_images,
    attached_image_mount_points,
    detach_dmg_attachment,
    expand_pkg_payload,
    hdiutil_verify_image,
    stage_troubleshooting_tools,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_package import (
    build_dmg as run_build_dmg,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_package import (
    build_pkg as run_build_pkg,
)
from tirosh_vitalserver.devtools.adapters.macos_release.runtime_app import (
    build_app_bundle,
    build_swift,
    sign_runtime_cli,
    sync_release,
)
from tirosh_vitalserver.devtools.adapters.toolchain.shell_commands import run
from tirosh_vitalserver.devtools.adapters.toolchain.workspace_paths import repo_root
from tirosh_vitalserver.devtools.application.inputs import (
    MacOSPackageCleanInput,
    MacOSPackageInstallInput,
    NginxBundleInput,
    ReleaseDmgArtifactVerifyInput,
    ReleasePackageEnvironmentPreflightInput,
    ReleasePackageInput,
    ReleaseTroubleshootingToolsInput,
    ReleaseTroubleshootingToolsVerifyInput,
)
from tirosh_vitalserver.devtools.application.usecases.host_proxy import (
    build_nginx as build_nginx_bundle,
)
from tirosh_vitalserver.devtools.config.docker_images import load_docker_images_config
from tirosh_vitalserver.devtools.config.guest_image import (
    load_guest_runtime_config,
    load_ubuntu_image_config,
)
from tirosh_vitalserver.devtools.config.macos.release_settings import (
    load_macos_release_settings,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.config.release_manifest import load_release_manifest
from tirosh_vitalserver.devtools.core.guest_services import RootfsInputMetadataPlan
from tirosh_vitalserver.devtools.core.macos_release.install_paths import (
    settings_install_home,
)
from tirosh_vitalserver.devtools.core.macos_release.models import PackageContext
from tirosh_vitalserver.devtools.core.macos_release.release_plans import (
    default_pkg_output,
    default_troubleshooting_tools_output,
    host_proxy_expected_version,
    package_clean_plan,
    package_outputs,
)
from tirosh_vitalserver.devtools.core.preflight import (
    PreflightCheck,
    PreflightReport,
    PreflightStatus,
    print_preflight_report,
)


def build_pkg(input: ReleasePackageInput) -> int:
    preflight_release_package(input, output_kind="pkg")
    context = prepare_package_context(input)
    run_build_pkg(context)
    print(f"release pkg is ready: {context.pkg_output}")
    return 0


def build_dmg(input: ReleasePackageInput) -> int:
    preflight_release_package(input, output_kind="dmg")
    context = prepare_package_context(input)
    run_build_pkg(context)
    run_build_dmg(context)
    print(f"release dmg is ready: {context.dmg_output}")
    return 0


def verify_dmg_artifact(input: ReleaseDmgArtifactVerifyInput) -> int:
    report = release_dmg_artifact_report(input)
    print_preflight_report(report)
    if report.passed:
        return 0
    raise SystemExit(1)


def verify_troubleshooting_tools(
    input: ReleaseTroubleshootingToolsVerifyInput,
) -> int:
    report = troubleshooting_tools_report(input)
    print_preflight_report(report)
    if report.passed:
        return 0
    raise SystemExit(1)


def preflight_release_package(
    input: ReleasePackageInput,
    *,
    output_kind: str,
) -> int:
    report = release_package_preflight_report(input, output_kind=output_kind)
    print_preflight_report(report)
    if report.passed:
        return 0
    raise SystemExit(1)


def preflight_release_package_environment(
    input: ReleasePackageEnvironmentPreflightInput,
) -> int:
    report = release_package_environment_preflight_report(input)
    print_preflight_report(report)
    if report.passed:
        return 0
    raise SystemExit(1)


def release_package_environment_preflight_report(
    input: ReleasePackageEnvironmentPreflightInput,
) -> PreflightReport:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    outputs = package_outputs(
        settings=settings,
        release=release,
        requested_output=resolve_path(root, input.output) if input.output else None,
        output_kind=input.output_kind,
    )
    checks: list[PreflightCheck] = [
        check_required_tool("swift"),
        check_required_tool("codesign"),
        check_required_tool("pkgbuild"),
        check_output_path(outputs.pkg_output, "pkg-output"),
    ]
    if input.output_kind == "dmg":
        checks.extend(
            [
                check_required_tool("hdiutil"),
                check_output_path(outputs.dmg_output, "dmg-output"),
                check_dmg_output_state(outputs.dmg_output),
            ]
        )
    return PreflightReport(
        name=f"release-{input.output_kind}-environment",
        checks=tuple(checks),
    )


def release_package_preflight_report(
    input: ReleasePackageInput,
    *,
    output_kind: str,
) -> PreflightReport:
    root = repo_root()
    environment_report = release_package_environment_preflight_report(
        ReleasePackageEnvironmentPreflightInput(
            config=input.config,
            release_file=input.release_file,
            output=input.output,
            output_kind=output_kind,
        )
    )
    rootfs_base = resolve_path(root, input.rootfs_base)
    golden_runtime_dir = resolve_path(root, input.golden_runtime_dir)
    rootfs_base_check = check_required_file(rootfs_base, "rootfs-base")
    checks: list[PreflightCheck] = [
        *environment_report.checks,
        rootfs_base_check,
        check_required_file(golden_runtime_dir / "Image", "golden-kernel-image"),
        check_required_file(golden_runtime_dir / "initrd.img", "golden-initrd"),
    ]
    if not rootfs_base_check.blocks:
        checks.append(
            check_compiled_guest_deploy_matches_rootfs_artifact(
                rootfs_base=rootfs_base,
                guest_deploy_source=resolve_path(root, input.guest_deploy_source),
            )
        )
    return PreflightReport(name=f"release-{output_kind}", checks=tuple(checks))


def check_compiled_guest_deploy_matches_rootfs_artifact(
    *,
    rootfs_base: Path,
    guest_deploy_source: Path,
) -> PreflightCheck:
    source_check = check_required_dir(
        guest_deploy_source,
        "compiled-guest-deploy",
    )
    if source_check.blocks:
        return source_check
    try:
        actual = require_rootfs_artifact_guest_deploy_match(
            rootfs_base,
            guest_deploy_source,
        )
    except SystemExit as error:
        detail = str(error)
        return PreflightCheck(
            name="compiled-guest-deploy",
            status=(
                PreflightStatus.BLOCKED
                if "does not match rootfs artifact receipt" in detail
                else PreflightStatus.INVALID
            ),
            message="compiled Guest deploy does not match rootfs artifact receipt",
            detail=detail,
        )
    return PreflightCheck(
        name="compiled-guest-deploy",
        status=PreflightStatus.PASSED,
        message="compiled Guest deploy matches rootfs proof",
        detail=f"sha256={actual}",
    )


def release_dmg_artifact_report(
    input: ReleaseDmgArtifactVerifyInput,
) -> PreflightReport:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    outputs = package_outputs(
        settings=settings,
        release=release,
        requested_output=resolve_path(root, input.output) if input.output else None,
        output_kind="dmg",
    )
    dmg_output = outputs.dmg_output
    checks: list[PreflightCheck] = [
        check_required_tool("hdiutil"),
        check_required_tool("pkgutil"),
        check_required_file(dmg_output, "dmg-artifact"),
    ]
    if any(check.blocks for check in checks):
        return PreflightReport(name="release-dmg-artifact", checks=tuple(checks))
    checks.append(check_hdiutil_verify(dmg_output))
    if checks[-1].blocks:
        return PreflightReport(name="release-dmg-artifact", checks=tuple(checks))
    checks.extend(
        inspect_dmg_layout(
            dmg_output=dmg_output,
            installer_pkg_name=settings.outputs.dmg_installer_pkg_name,
            install_home_path=settings_install_home(settings),
        )
    )
    return PreflightReport(name="release-dmg-artifact", checks=tuple(checks))


def troubleshooting_tools_report(
    input: ReleaseTroubleshootingToolsVerifyInput,
) -> PreflightReport:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    tools_dir = (
        resolve_path(root, input.output)
        if input.output
        else default_troubleshooting_tools_output(settings, release)
    )
    reset_command = tools_dir / "Reset VitalServer Helper for Reinstall.command"
    redis_command = tools_dir / "Create Upstream Redis Backup.command"
    checks: list[PreflightCheck] = [
        check_required_dir(tools_dir, "troubleshooting-tools-dir"),
        check_required_executable_file(
            reset_command,
            "troubleshooting-reset-command",
        ),
        check_required_executable_file(
            redis_command,
            "troubleshooting-upstream-redis-backup-command",
        ),
        check_required_executable_file(
            tools_dir / "bin/vitalserver-troubleshooting-reset-for-reinstall",
            "troubleshooting-reset-cli",
        ),
        check_required_executable_file(
            tools_dir / "bin/vitalserver-troubleshooting-upstream-redis-save",
            "troubleshooting-upstream-redis-save-cli",
        ),
        check_text_contains(
            reset_command,
            "troubleshooting-reset-command-cli-contract",
            "vitalserver-troubleshooting-reset-for-reinstall",
        ),
        check_text_contains(
            reset_command,
            "troubleshooting-reset-command-user-log",
            "tirosh-vitalserver-reset-for-reinstall.log",
        ),
        check_text_absent(
            reset_command,
            "troubleshooting-reset-command-no-user-uninstall-log",
            (
                'exec > >(tee -a "${uninstall_log}") 2>&1\n'
                '  log "reset for reinstall command started'
            ),
        ),
        check_text_contains(
            reset_command,
            "troubleshooting-reset-command-wrapper-log",
            'exec > >(tee -a "${wrapper_log}") 2>&1',
        ),
        check_text_contains(
            redis_command,
            "troubleshooting-redis-command-cli-contract",
            "vitalserver-troubleshooting-upstream-redis-save",
        ),
        check_text_contains(
            redis_command,
            "troubleshooting-redis-command-save-timeout",
            'redis_save_timeout_seconds="${UPSTREAM_REDIS_SAVE_TIMEOUT_SECONDS:-15}"',
        ),
        check_text_contains(
            redis_command,
            "troubleshooting-redis-command-timeout-guard",
            "run_with_timeout()",
        ),
        check_text_contains(
            redis_command,
            "troubleshooting-redis-command-timeout-message",
            "upstream redis SAVE did not complete before timeout",
        ),
    ]
    return PreflightReport(name="release-troubleshooting-tools", checks=tuple(checks))


def check_hdiutil_verify(dmg_output: Path) -> PreflightCheck:
    try:
        hdiutil_verify_image(dmg_output)
    except RuntimeError as error:
        return PreflightCheck(
            name="dmg-hdiutil-verify",
            status=PreflightStatus.FAILED,
            message="hdiutil verify failed",
            detail=f"{dmg_output}: {error}",
        )
    return PreflightCheck(
        name="dmg-hdiutil-verify",
        status=PreflightStatus.PASSED,
        message=f"DMG image verified: {dmg_output}",
    )


def inspect_dmg_layout(
    *,
    dmg_output: Path,
    installer_pkg_name: str,
    install_home_path: str,
) -> list[PreflightCheck]:
    checks: list[PreflightCheck] = []
    attachment = None
    try:
        attachment = attach_dmg_readonly(dmg_output)
    except RuntimeError as error:
        return [
            PreflightCheck(
                name="dmg-attach",
                status=PreflightStatus.FAILED,
                message="failed to attach DMG read-only",
                detail=f"{dmg_output}: {error}",
            )
        ]
    try:
        mount = attachment.mount_point
        installer_pkg = mount / installer_pkg_name
        installer_pkg_check = check_required_mounted_file(
            installer_pkg,
            "dmg-installer-pkg",
        )
        checks.append(installer_pkg_check)
        if not installer_pkg_check.blocks:
            checks.extend(
                inspect_dmg_installer_pkg_payload(
                    installer_pkg=installer_pkg,
                    install_home_path=install_home_path,
                )
            )
        tools_dir = mount / "Troubleshooting Tools"
        checks.append(
            check_required_mounted_dir(tools_dir, "dmg-troubleshooting-tools")
        )
        checks.extend(
            [
                check_required_executable(
                    tools_dir / "Reset VitalServer Helper for Reinstall.command",
                    "dmg-reset-command",
                ),
                check_required_executable(
                    tools_dir / "Create Upstream Redis Backup.command",
                    "dmg-upstream-redis-backup-command",
                ),
                check_required_executable(
                    tools_dir
                    / "bin/vitalserver-troubleshooting-reset-for-reinstall",
                    "dmg-reset-cli",
                ),
                check_required_executable(
                    tools_dir
                    / "bin/vitalserver-troubleshooting-upstream-redis-save",
                    "dmg-upstream-redis-save-cli",
                ),
            ]
        )
    finally:
        try:
            detach_dmg_attachment(attachment)
        except RuntimeError as error:
            checks.append(
                PreflightCheck(
                    name="dmg-detach",
                    status=PreflightStatus.FAILED,
                    message="failed to detach DMG after verification",
                    detail=f"{dmg_output}: {error}",
                )
            )
    return checks


def inspect_dmg_installer_pkg_payload(
    *,
    installer_pkg: Path,
    install_home_path: str,
) -> list[PreflightCheck]:
    try:
        with TemporaryDirectory(prefix="vitalserver-dmg-pkg-") as temporary_dir:
            payload = expand_pkg_payload(
                installer_pkg,
                Path(temporary_dir) / "expanded",
            )
            checks = [
                PreflightCheck(
                    name="dmg-pkg-expand",
                    status=PreflightStatus.PASSED,
                    message=f"installer package payload expanded: {installer_pkg}",
                )
            ]
            checks.extend(
                verify_dmg_pkg_rootfs_material(
                    payload=payload,
                    install_home_path=install_home_path,
                )
            )
            return checks
    except (OSError, RuntimeError) as error:
        return [
            PreflightCheck(
                name="dmg-pkg-expand",
                status=PreflightStatus.FAILED,
                message="failed to expand installer package payload",
                detail=f"{installer_pkg}: {error}",
            )
        ]


def verify_dmg_pkg_rootfs_material(
    *,
    payload: Path,
    install_home_path: str,
) -> list[PreflightCheck]:
    installed_home = payload / install_home_path.strip("/")
    rootfs = installed_home / "runtime" / "rootfs-base.raw.gz"
    rootfs_manifest = rootfs_artifact_manifest_path(rootfs)
    guest_deploy = installed_home / "data" / "deploy"
    checks = [
        check_required_payload_file(rootfs, "dmg-payload-rootfs-base"),
        check_required_payload_file(
            rootfs_manifest,
            "dmg-payload-rootfs-manifest",
        ),
        check_required_mounted_dir(guest_deploy, "dmg-payload-guest-deploy"),
    ]
    if any(check.blocks for check in checks):
        return checks
    try:
        document = require_rootfs_artifact_receipt(rootfs)
        expected_guest_deploy_sha256 = (
            require_rootfs_artifact_guest_deploy_material_sha256(
                document,
                rootfs_manifest,
            )
        )
    except SystemExit as error:
        checks.append(
            PreflightCheck(
                name="dmg-payload-rootfs-receipt",
                status=PreflightStatus.INVALID,
                message="packaged rootfs receipt is invalid",
                detail=str(error),
            )
        )
        return checks
    checks.append(
        PreflightCheck(
            name="dmg-payload-rootfs-receipt",
            status=PreflightStatus.PASSED,
            message="packaged rootfs receipt matches its artifact and compile proof",
        )
    )
    try:
        actual_guest_deploy_sha256 = guest_deploy_material_sha256(guest_deploy)
    except SystemExit as error:
        checks.append(
            PreflightCheck(
                name="dmg-payload-guest-deploy-material-sha256",
                status=PreflightStatus.INVALID,
                message="packaged Guest deploy material is invalid",
                detail=str(error),
            )
        )
        return checks
    if actual_guest_deploy_sha256 != expected_guest_deploy_sha256:
        checks.append(
            PreflightCheck(
                name="dmg-payload-guest-deploy-material-sha256",
                status=PreflightStatus.FAILED,
                message="packaged Guest deploy material digest does not match manifest",
                detail=(
                    f"expected={expected_guest_deploy_sha256} "
                    f"actual={actual_guest_deploy_sha256} path={guest_deploy}"
                ),
            )
        )
    else:
        checks.append(
            PreflightCheck(
                name="dmg-payload-guest-deploy-material-sha256",
                status=PreflightStatus.PASSED,
                message="packaged Guest deploy material digest matches manifest",
            )
        )
    return checks


def check_required_payload_file(path: Path, name: str) -> PreflightCheck:
    if path.is_symlink():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message="required package payload file must not be a symlink",
            detail=str(path),
        )
    return check_required_mounted_file(path, name)


def check_required_mounted_file(path: Path, name: str) -> PreflightCheck:
    if path.is_file():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=f"required DMG file exists: {path}",
        )
    if path.exists():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message="required DMG path is not a file",
            detail=str(path),
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.MISSING,
        message="required DMG file is missing",
        detail=str(path),
    )


def check_required_mounted_dir(path: Path, name: str) -> PreflightCheck:
    if path.is_dir():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=f"required DMG directory exists: {path}",
        )
    if path.exists():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message="required DMG path is not a directory",
            detail=str(path),
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.MISSING,
        message="required DMG directory is missing",
        detail=str(path),
    )


def check_required_executable(path: Path, name: str) -> PreflightCheck:
    file_check = check_required_mounted_file(path, name)
    if file_check.blocks:
        return file_check
    if path.stat().st_mode & 0o111:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=f"required DMG executable exists: {path}",
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.INVALID,
        message="required DMG executable is not executable",
        detail=str(path),
    )


def check_required_dir(path: Path, name: str) -> PreflightCheck:
    if path.is_dir():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=f"required directory exists: {path}",
        )
    if path.exists():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message="required path is not a directory",
            detail=str(path),
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.MISSING,
        message="required directory is missing",
        detail=str(path),
    )


def check_required_executable_file(path: Path, name: str) -> PreflightCheck:
    file_check = check_required_file(path, name)
    if file_check.blocks:
        return file_check
    if path.stat().st_mode & 0o111:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=f"required executable exists: {path}",
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.INVALID,
        message="required executable is not executable",
        detail=str(path),
    )


def check_required_tool(name: str) -> PreflightCheck:
    if shutil.which(name):
        return PreflightCheck(
            name=f"tool:{name}",
            status=PreflightStatus.PASSED,
            message=f"required tool is available: {name}",
        )
    return PreflightCheck(
        name=f"tool:{name}",
        status=PreflightStatus.MISSING,
        message=f"required tool is missing: {name}",
    )


def check_required_file(path: Path, name: str) -> PreflightCheck:
    if path.is_file():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message=f"required package input exists: {path}",
        )
    if path.exists():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message="required package input is not a file",
            detail=str(path),
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.MISSING,
        message="required package input is missing",
        detail=str(path),
    )


def check_output_path(path: Path, name: str) -> PreflightCheck:
    if path.exists() and path.is_dir():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message="package output path is a directory",
            detail=str(path),
        )
    parent = path.parent
    if parent.exists() and not parent.is_dir():
        return PreflightCheck(
            name=name,
            status=PreflightStatus.INVALID,
            message="package output parent is not a directory",
            detail=str(parent),
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.PASSED,
        message=f"package output path is usable: {path}",
    )


def check_text_contains(path: Path, name: str, expected: str) -> PreflightCheck:
    text, error = read_text_for_preflight(path)
    if error:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.UNAVAILABLE,
            message="could not read text file",
            detail=f"{path}: {error}",
        )
    if expected in text:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message="required text marker is present",
            detail=str(path),
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.INVALID,
        message="required text marker is missing",
        detail=f"{path}: {expected}",
    )


def check_text_absent(path: Path, name: str, forbidden: str) -> PreflightCheck:
    text, error = read_text_for_preflight(path)
    if error:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.UNAVAILABLE,
            message="could not read text file",
            detail=f"{path}: {error}",
        )
    if forbidden not in text:
        return PreflightCheck(
            name=name,
            status=PreflightStatus.PASSED,
            message="forbidden text marker is absent",
            detail=str(path),
        )
    return PreflightCheck(
        name=name,
        status=PreflightStatus.INVALID,
        message="forbidden text marker is present",
        detail=f"{path}: {forbidden}",
    )


def read_text_for_preflight(path: Path) -> tuple[str, str | None]:
    try:
        return path.read_text(encoding="utf-8"), None
    except FileNotFoundError:
        return "", f"missing: {path}"
    except (OSError, UnicodeDecodeError) as error:
        return "", f"{type(error).__name__}: {error}"


def check_dmg_output_state(dmg_output: Path) -> PreflightCheck:
    try:
        attached = attached_disk_images()
    except RuntimeError as error:
        return PreflightCheck(
            name="dmg-output-attachment",
            status=PreflightStatus.FAILED,
            message="failed to inspect attached disk images",
            detail=str(error),
        )
    expected_path = str(dmg_output.resolve(strict=False))
    for image in attached:
        image_path = image.get("image-path")
        if not isinstance(image_path, str):
            continue
        if str(Path(image_path).resolve(strict=False)) != expected_path:
            continue
        mount_points = attached_image_mount_points(image)
        if mount_points:
            return PreflightCheck(
                name="dmg-output-attachment",
                status=PreflightStatus.BLOCKED,
                message="DMG output is currently mounted",
                detail=f"{expected_path} ({', '.join(mount_points)})",
            )
        return PreflightCheck(
            name="dmg-output-attachment",
            status=PreflightStatus.BLOCKED,
            message="DMG output is attached without a mount point",
            detail=expected_path,
        )
    return PreflightCheck(
        name="dmg-output-attachment",
        status=PreflightStatus.PASSED,
        message=f"DMG output is not attached: {expected_path}",
    )


def build_troubleshooting_tools(input: ReleaseTroubleshootingToolsInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    runtime_dir = settings.runtime_dir
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    tools_output = (
        resolve_path(root, input.output)
        if input.output
        else default_troubleshooting_tools_output(settings, release)
    )

    sync_release(root, runtime_dir, release_file)
    clang_module_cache = input.clang_module_cache or str(settings.clang_module_cache)
    build_swift(
        runtime_dir,
        input.sdkroot,
        clang_module_cache,
        settings.helper_product_name,
    )
    sign_runtime_cli(
        settings.runtime_cli,
        runtime_dir,
        input.codesign_identity,
    )
    stage_troubleshooting_tools(
        settings=settings,
        runtime_dir=runtime_dir,
        runtime_cli=settings.runtime_cli,
        tools_dir=tools_output,
    )
    print(f"troubleshooting tools are ready: {tools_output}")
    return 0


def clean_package(input: MacOSPackageCleanInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    plan = package_clean_plan(root=root, settings=settings, release=release)
    for path in plan.paths:
        if path.exists():
            remove_path(path)
    return 0


def install_pkg(input: MacOSPackageInstallInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    pkg_output = default_pkg_output(settings, release)
    if not pkg_output.is_file():
        raise SystemExit(
            f"missing {pkg_output}. Run: make vm-pkg-dev or make vm-pkg-release"
        )
    try:
        if input.install_settings:
            install_settings = resolve_path(
                root,
                input.install_settings,
            )
            if not install_settings.is_file():
                raise SystemExit(f"missing {install_settings}")
            run(
                [
                    "sudo",
                    "install",
                    "-m",
                    "0600",
                    str(install_settings),
                    settings.install.install_settings_json,
                ]
            )
            print(
                "installed runtime settings: "
                f"{settings.install.install_settings_json}"
            )
        run(["sudo", "installer", "-pkg", str(pkg_output), "-target", "/"])
    except subprocess.CalledProcessError as error:
        command = " ".join(str(part) for part in error.cmd)
        raise SystemExit(
            f"installer command failed exitCode={error.returncode}: {command}. "
            "Run from an interactive administrator shell or configure sudo "
            "credentials before running dist/install/* targets."
        ) from error
    return 0


def prepare_package_context(input: ReleasePackageInput) -> PackageContext:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    config = load_config(input.config)
    ubuntu_config = load_ubuntu_image_config(config)
    runtime_config = load_guest_runtime_config(config)
    docker_config = load_docker_images_config(config, root)
    runtime_dir = settings.runtime_dir
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    outputs = package_outputs(
        settings=settings,
        release=release,
        requested_output=resolve_path(root, input.output) if input.output else None,
        output_kind=input.output_kind,
    )

    sync_release(root, runtime_dir, release_file)
    clang_module_cache = input.clang_module_cache or str(settings.clang_module_cache)
    build_swift(
        runtime_dir,
        input.sdkroot,
        clang_module_cache,
        settings.helper_product_name,
    )
    sign_runtime_cli(
        settings.runtime_cli,
        runtime_dir,
        input.codesign_identity,
    )
    build_app_bundle(
        root=root,
        runtime_dir=runtime_dir,
        helper_bin=settings.helper_bin,
        app_bundle=settings.app_bundle,
        app_name=settings.app_name,
        helper_version=release.helper_version,
        codesign_identity=input.codesign_identity,
    )
    build_nginx_bundle(
        NginxBundleInput(
            config=input.config,
            bundle_dir=settings.nginx_bundle,
            binary=input.nginx_binary,
            expected_version=host_proxy_expected_version(
                release=release,
                explicit_version=input.nginx_expected_version,
            ),
        )
    )
    guest_deploy_source = resolve_path(root, input.guest_deploy_source)
    package_vm_home = settings.pkg_root / settings_install_home(settings).strip("/")

    return PackageContext(
        root=root,
        runtime_dir=runtime_dir,
        release=release,
        pkg_root=settings.pkg_root,
        pkg_scripts=settings.pkg_scripts,
        pkg_output=outputs.pkg_output,
        dmg_output=outputs.dmg_output,
        app_bundle=settings.app_bundle,
        runtime_cli=settings.runtime_cli,
        nginx_bundle=settings.nginx_bundle,
        rootfs_base=resolve_path(root, input.rootfs_base),
        golden_runtime_dir=resolve_path(root, input.golden_runtime_dir),
        guest_deploy_source=guest_deploy_source,
        rootfs_input_metadata_plan=RootfsInputMetadataPlan(
            deploy_dir=package_vm_home / "data/deploy",
            base_url=ubuntu_config.base_url,
            apt_snapshot=ubuntu_config.apt_snapshot,
            runtime_data=runtime_config.runtime_data_disk,
            docker_platform=input.docker_platform or docker_config.platform,
        ),
        proxy_port=input.proxy_port,
        settings=settings,
    )

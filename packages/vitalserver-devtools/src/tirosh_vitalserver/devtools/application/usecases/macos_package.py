from __future__ import annotations

import json
import shutil
import subprocess
from dataclasses import replace
from pathlib import Path

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.adapters.guest_services.docker_images import (
    build_docker_image_bundle as run_docker_image_bundle,
)
from tirosh_vitalserver.devtools.adapters.macos_release.artifact_files import (
    remove_path,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_package import (
    attach_dmg_readonly,
    attached_disk_images,
    attached_image_mount_points,
    detach_dmg_attachment,
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
from tirosh_vitalserver.devtools.application.guest_service_plans import (
    docker_image_bundle_build_plan,
)
from tirosh_vitalserver.devtools.application.inputs import (
    MacOSPackageCleanInput,
    MacOSPackageInstallInput,
    NginxBundleInput,
    ReleaseDmgArtifactVerifyInput,
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
from tirosh_vitalserver.devtools.core.guest_services import (
    ComposeServiceImageReference,
    DockerImagePlan,
    RootfsInputMetadataPlan,
    compose_service_image_references,
    guest_deploy_plan,
)
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


def release_package_preflight_report(
    input: ReleasePackageInput,
    *,
    output_kind: str,
) -> PreflightReport:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    outputs = package_outputs(
        settings=settings,
        release=release,
        requested_output=resolve_path(root, input.output) if input.output else None,
        output_kind=output_kind,
    )
    rootfs_base = resolve_path(root, input.rootfs_base)
    golden_runtime_dir = resolve_path(root, input.golden_runtime_dir)
    checks: list[PreflightCheck] = [
        check_required_tool("swift"),
        check_required_tool("codesign"),
        check_required_tool("pkgbuild"),
        check_required_file(rootfs_base, "rootfs-base"),
        check_required_file(golden_runtime_dir / "Image", "golden-kernel-image"),
        check_required_file(golden_runtime_dir / "initrd.img", "golden-initrd"),
        check_output_path(outputs.pkg_output, "pkg-output"),
    ]
    if output_kind == "dmg":
        checks.append(check_required_tool("hdiutil"))
        checks.append(check_output_path(outputs.dmg_output, "dmg-output"))
        checks.append(check_dmg_output_state(outputs.dmg_output))
    checks.extend(
        docker_image_bundle_preflight_checks(
            root=root,
            config=input.config,
            bundle_path=settings.docker_bundle,
            platform=input.docker_platform,
            compression_threads=input.compression_threads,
            include_optional=False,
            compose_path=settings.runtime_dir / "Support/Guest/compose.yaml",
            deploy_include_sources=[
                include.source for include in settings.guest_deploy.includes
            ],
        )
    )
    return PreflightReport(name=f"release-{output_kind}", checks=tuple(checks))


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
        checks.append(
            check_required_mounted_file(
                mount / installer_pkg_name,
                "dmg-installer-pkg",
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


def docker_image_bundle_preflight_checks(
    *,
    root: Path,
    config: Path,
    bundle_path: Path,
    platform: str | None,
    compression_threads: int | None,
    include_optional: bool,
    compose_path: Path,
    deploy_include_sources: list[Path],
) -> list[PreflightCheck]:
    build_config = load_config(config)
    docker_config = load_docker_images_config(build_config, root)
    plan = docker_image_bundle_build_plan(
        root=root,
        docker_config=docker_config,
        bundle_path=bundle_path,
        platform=platform,
        compression_threads=compression_threads,
    )
    checks = docker_image_plan_preflight_checks(plan.image_plan)
    checks.extend(
        guest_compose_contract_preflight_checks(
            root=root,
            compose_path=compose_path,
            plan=plan.image_plan,
            known_images=set(docker_config.images) | set(docker_config.optional_images),
            deploy_include_sources=deploy_include_sources,
            optional_images=set(docker_config.optional_images),
            include_optional=include_optional,
        )
    )
    if (
        include_optional
        and docker_config.optional_images
        and docker_config.optional_bundle_path is not None
    ):
        optional_config = replace(docker_config, images=docker_config.optional_images)
        optional_plan = docker_image_bundle_build_plan(
            root=root,
            docker_config=optional_config,
            bundle_path=docker_config.optional_bundle_path,
            platform=platform,
            compression_threads=compression_threads,
        )
        checks.extend(docker_image_plan_preflight_checks(optional_plan.image_plan))
    return checks


def guest_compose_contract_preflight_checks(
    *,
    root: Path,
    compose_path: Path,
    plan: DockerImagePlan,
    known_images: set[str],
    deploy_include_sources: list[Path],
    optional_images: set[str] | None = None,
    include_optional: bool = False,
) -> list[PreflightCheck]:
    compose_text, error = read_text_for_preflight(compose_path)
    if error:
        return [
            PreflightCheck(
                name="guest-compose-contract",
                status=PreflightStatus.UNAVAILABLE,
                message="could not read guest compose file",
                detail=f"{compose_path}: {error}",
            )
        ]
    references = compose_service_image_references(compose_text)
    if optional_images and not include_optional:
        references = tuple(
            reference
            for reference in references
            if reference.image not in optional_images
        )
    if not references:
        return [
            PreflightCheck(
                name="guest-compose-contract",
                status=PreflightStatus.INVALID,
                message="guest compose did not declare any service images",
                detail=str(compose_path),
            )
        ]

    checks: list[PreflightCheck] = []
    checks.append(check_runtime_proof_compose_services(references))
    dockerfiles_by_image = dockerfile_contracts_by_image(plan)
    for reference in references:
        checks.append(
            check_compose_image_is_bundled(
                reference=reference,
                known_images=known_images,
            )
        )
        if reference.dockerfile is None:
            continue
        checks.append(
            check_compose_dockerfile_is_configured(
                root=root,
                reference=reference,
                dockerfiles_by_image=dockerfiles_by_image,
            )
        )
        checks.append(
            check_compose_dockerfile_is_deployed(
                reference=reference,
                deploy_include_sources=deploy_include_sources,
            )
        )
    return checks


REQUIRED_RUNTIME_PRODUCT_COMPOSE_SERVICES = frozenset(
    {
        "postgres",
        "redis",
        "app",
        "recorder-recovery",
        "recorder-ingress",
        "vitaldb-observer",
        "redis-relay",
        "lab",
        "edge",
    }
)


def check_runtime_proof_compose_services(
    references: tuple[ComposeServiceImageReference, ...],
) -> PreflightCheck:
    services = {reference.service for reference in references}
    missing = sorted(REQUIRED_RUNTIME_PRODUCT_COMPOSE_SERVICES - services)
    forbidden = sorted(service for service in services if service == "testkit")
    if missing or forbidden:
        return PreflightCheck(
            name="guest-compose-product-services",
            status=PreflightStatus.INVALID,
            message="guest compose does not match Runtime v2 product stack",
            detail=f"missing={missing} forbidden={forbidden}",
        )
    return PreflightCheck(
        name="guest-compose-product-services",
        status=PreflightStatus.PASSED,
        message="guest compose declares Runtime v2 product services",
        detail=",".join(sorted(services)),
    )


def dockerfile_contracts_by_image(plan: DockerImagePlan) -> dict[str, Path]:
    return {
        plan.app_image: plan.app_dockerfile,
        plan.recorder_ingress_image: plan.recorder_ingress_dockerfile,
        plan.recorder_recovery_image: plan.recorder_recovery_dockerfile,
        plan.vitaldb_observer_image: plan.vitaldb_observer_dockerfile,
        plan.redis_relay_image: plan.redis_relay_dockerfile,
        plan.lab_image: plan.lab_dockerfile,
    }


def check_compose_image_is_bundled(
    *,
    reference: ComposeServiceImageReference,
    known_images: set[str],
) -> PreflightCheck:
    if reference.image in known_images:
        return PreflightCheck(
            name=f"guest-compose-image:{reference.service}",
            status=PreflightStatus.PASSED,
            message="guest compose image is declared in VM docker image config",
            detail=reference.image,
        )
    return PreflightCheck(
        name=f"guest-compose-image:{reference.service}",
        status=PreflightStatus.INVALID,
        message="guest compose image is not declared in VM docker image config",
        detail=f"service={reference.service} image={reference.image}",
    )


def check_compose_dockerfile_is_configured(
    *,
    root: Path,
    reference: ComposeServiceImageReference,
    dockerfiles_by_image: dict[str, Path],
) -> PreflightCheck:
    configured = dockerfiles_by_image.get(reference.image)
    if configured is None:
        return PreflightCheck(
            name=f"guest-compose-dockerfile:{reference.service}",
            status=PreflightStatus.INVALID,
            message="guest compose build image has no configured dockerfile",
            detail=f"service={reference.service} image={reference.image}",
        )
    configured_relative = configured.relative_to(root)
    if reference.dockerfile == configured_relative:
        return PreflightCheck(
            name=f"guest-compose-dockerfile:{reference.service}",
            status=PreflightStatus.PASSED,
            message="guest compose dockerfile matches VM docker image config",
            detail=str(reference.dockerfile),
        )
    return PreflightCheck(
        name=f"guest-compose-dockerfile:{reference.service}",
        status=PreflightStatus.INVALID,
        message="guest compose dockerfile does not match VM docker image config",
        detail=(
            f"service={reference.service} compose={reference.dockerfile} "
            f"config={configured_relative}"
        ),
    )


def check_compose_dockerfile_is_deployed(
    *,
    reference: ComposeServiceImageReference,
    deploy_include_sources: list[Path],
) -> PreflightCheck:
    dockerfile = reference.dockerfile
    if dockerfile is not None and path_is_covered_by_include(
        dockerfile,
        deploy_include_sources,
    ):
        return PreflightCheck(
            name=f"guest-compose-deploy:{reference.service}",
            status=PreflightStatus.PASSED,
            message="guest compose dockerfile is covered by guest deploy includes",
            detail=str(dockerfile),
        )
    return PreflightCheck(
        name=f"guest-compose-deploy:{reference.service}",
        status=PreflightStatus.INVALID,
        message="guest compose dockerfile is not covered by guest deploy includes",
        detail=f"service={reference.service} dockerfile={dockerfile}",
    )


def path_is_covered_by_include(path: Path, include_sources: list[Path]) -> bool:
    for source in include_sources:
        if path == source or path.is_relative_to(source):
            return True
    return False


def docker_image_plan_preflight_checks(plan: DockerImagePlan) -> list[PreflightCheck]:
    docker_tool = check_required_tool("docker")
    checks = [docker_tool]
    checks.append(check_required_file(plan.app_dockerfile, "dockerfile:app"))
    if plan.recorder_ingress_image in plan.images:
        checks.append(
            check_required_file(
                plan.recorder_ingress_dockerfile,
                "dockerfile:recorder-ingress",
            )
        )
    if plan.recorder_recovery_image in plan.images:
        checks.append(
            check_required_file(
                plan.recorder_recovery_dockerfile,
                "dockerfile:recorder-recovery",
            )
        )
    if plan.vitaldb_observer_image in plan.images:
        checks.append(
            check_required_file(
                plan.vitaldb_observer_dockerfile,
                "dockerfile:vitaldb-observer",
            )
        )
    if plan.redis_relay_image in plan.images:
        checks.append(
            check_required_file(
                plan.redis_relay_dockerfile,
                "dockerfile:redis-relay",
            )
        )
    if plan.lab_image in plan.images:
        checks.append(
            check_required_file(
                plan.lab_dockerfile,
                "dockerfile:lab",
            )
        )
    if not docker_tool.blocks:
        checks.extend(
            check_docker_manifest(image=image, platform=plan.platform)
            for image in plan.pull_images
        )
    return checks


def check_docker_manifest(*, image: str, platform: str) -> PreflightCheck:
    local_platform = docker_local_image_platform(image)
    if local_platform == platform:
        return PreflightCheck(
            name=f"docker-manifest:{image}",
            status=PreflightStatus.PASSED,
            message="local docker image matches requested platform",
            detail=f"image={image} platform={platform}",
        )

    command = ["docker", "manifest", "inspect", image]
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except FileNotFoundError:
        return PreflightCheck(
            name=f"docker-manifest:{image}",
            status=PreflightStatus.MISSING,
            message="docker command is missing",
            detail=image,
        )
    except subprocess.TimeoutExpired:
        return PreflightCheck(
            name=f"docker-manifest:{image}",
            status=PreflightStatus.UNAVAILABLE,
            message="docker manifest inspect timed out",
            detail=docker_manifest_unavailable_detail(
                image=image,
                platform=platform,
                reason="timeout",
            ),
        )
    if result.returncode != 0:
        stderr = result.stderr.strip()
        return PreflightCheck(
            name=f"docker-manifest:{image}",
            status=PreflightStatus.UNAVAILABLE,
            message="docker image manifest is unavailable",
            detail=docker_manifest_unavailable_detail(
                image=image,
                platform=platform,
                reason=stderr,
            ),
        )
    try:
        document = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        return PreflightCheck(
            name=f"docker-manifest:{image}",
            status=PreflightStatus.INVALID,
            message="docker image manifest output is invalid JSON",
            detail=f"image={image} error={error}",
        )
    if not docker_manifest_supports_platform(document, platform):
        return PreflightCheck(
            name=f"docker-manifest:{image}",
            status=PreflightStatus.INVALID,
            message="docker image manifest does not include requested platform",
            detail=f"image={image} platform={platform}",
        )
    return PreflightCheck(
        name=f"docker-manifest:{image}",
        status=PreflightStatus.PASSED,
        message="docker image manifest is available",
        detail=f"image={image} platform={platform}",
    )


def docker_manifest_unavailable_detail(
    *,
    image: str,
    platform: str,
    reason: str,
) -> str:
    return (
        f"image={image} platform={platform} reason={reason}; "
        f"retry after network/Docker Hub access recovers, or pre-pull with "
        f"`docker pull --platform {platform} {image}` so preflight can use the "
        "local image platform check"
    )


def docker_local_image_platform(image: str) -> str | None:
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", image],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    try:
        document = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    if not isinstance(document, list) or not document:
        return None
    image_document = document[0]
    if not isinstance(image_document, dict):
        return None
    os_name = image_document.get("Os")
    architecture = image_document.get("Architecture")
    if not isinstance(os_name, str) or not isinstance(architecture, str):
        return None
    return f"{os_name}/{architecture}"


def docker_manifest_supports_platform(document: object, platform: str) -> bool:
    requested_os, requested_architecture = docker_platform_parts(platform)
    if not isinstance(document, dict):
        return False
    manifests = document.get("manifests")
    if not isinstance(manifests, list):
        return True
    for manifest in manifests:
        if not isinstance(manifest, dict):
            continue
        manifest_platform = manifest.get("platform")
        if not isinstance(manifest_platform, dict):
            continue
        if (
            manifest_platform.get("os") == requested_os
            and manifest_platform.get("architecture") == requested_architecture
        ):
            return True
    return False


def docker_platform_parts(platform: str) -> tuple[str, str]:
    parts = platform.split("/")
    if len(parts) < 2 or not parts[0] or not parts[1]:
        return platform, ""
    return parts[0], parts[1]


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
    optional_docker_bundle = build_docker_image_bundles_from_config(
        root=root,
        config=input.config,
        bundle_path=settings.docker_bundle,
        platform=input.docker_platform,
        compression_threads=input.compression_threads,
        include_optional=False,
    )
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
        docker_bundle=settings.docker_bundle,
        rootfs_base=resolve_path(root, input.rootfs_base),
        golden_runtime_dir=resolve_path(root, input.golden_runtime_dir),
        guest_deploy_plan=guest_deploy_plan(
            root=root,
            runtime_dir=runtime_dir,
            deploy_dir=package_vm_home / "data/deploy",
            vm_home=package_vm_home,
            config=settings.guest_deploy,
            docker_bundle=settings.docker_bundle,
            optional_docker_bundle=optional_docker_bundle,
            include_optional=False,
        ),
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


def build_docker_image_bundles_from_config(
    *,
    root: Path,
    config: Path,
    bundle_path: Path,
    platform: str | None,
    compression_threads: int | None,
    include_optional: bool,
) -> Path | None:
    build_config = load_config(config)
    docker_config = load_docker_images_config(build_config, root)
    plan = docker_image_bundle_build_plan(
        root=root,
        docker_config=docker_config,
        bundle_path=bundle_path,
        platform=platform,
        compression_threads=compression_threads,
    )
    run_docker_image_bundle(
        plan=plan.image_plan,
        bundle_path=plan.bundle_path,
        compression_threads_value=plan.compression_threads,
    )
    if (
        not include_optional
        or not docker_config.optional_images
        or docker_config.optional_bundle_path is None
    ):
        return None

    optional_config = replace(docker_config, images=docker_config.optional_images)
    optional_plan = docker_image_bundle_build_plan(
        root=root,
        docker_config=optional_config,
        bundle_path=docker_config.optional_bundle_path,
        platform=platform,
        compression_threads=compression_threads,
    )
    run_docker_image_bundle(
        plan=optional_plan.image_plan,
        bundle_path=optional_plan.bundle_path,
        compression_threads_value=optional_plan.compression_threads,
    )
    return optional_plan.bundle_path

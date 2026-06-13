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
    attached_disk_images,
    attached_image_mount_points,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_package import (
    build_dmg as run_build_dmg,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_package import (
    build_pkg as run_build_pkg,
)
from tirosh_vitalserver.devtools.adapters.macos_release.installer_package import (
    build_reset_installer_pkg as run_build_reset_installer_pkg,
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
    ReleasePackageInput,
    ReleaseResetInstallerPackageInput,
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
    DockerImagePlan,
    RootfsInputMetadataPlan,
    guest_deploy_plan,
)
from tirosh_vitalserver.devtools.core.macos_release.install_paths import (
    settings_install_home,
)
from tirosh_vitalserver.devtools.core.macos_release.models import PackageContext
from tirosh_vitalserver.devtools.core.macos_release.release_plans import (
    default_clean_uninstaller_pkg_output,
    default_pkg_output,
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
            include_optional="testkit" in release.optional_container_services,
        )
    )
    return PreflightReport(name=f"release-{output_kind}", checks=tuple(checks))


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


def docker_image_plan_preflight_checks(plan: DockerImagePlan) -> list[PreflightCheck]:
    docker_tool = check_required_tool("docker")
    checks = [docker_tool]
    checks.append(check_required_file(plan.app_dockerfile, "dockerfile:app"))
    if plan.audit_proxy_image in plan.images:
        checks.append(
            check_required_file(
                plan.audit_proxy_dockerfile,
                "dockerfile:audit-proxy",
            )
        )
    if plan.vitaldb_observer_image in plan.images:
        checks.append(
            check_required_file(
                plan.vitaldb_observer_dockerfile,
                "dockerfile:vitaldb-observer",
            )
        )
    if plan.testkit_image in plan.images:
        checks.append(
            check_required_file(
                plan.testkit_dockerfile,
                "dockerfile:testkit",
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
            detail=f"image={image} platform={platform}",
        )
    if result.returncode != 0:
        stderr = result.stderr.strip()
        return PreflightCheck(
            name=f"docker-manifest:{image}",
            status=PreflightStatus.UNAVAILABLE,
            message="docker image manifest is unavailable",
            detail=f"image={image} platform={platform} {stderr}".strip(),
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


def build_reset_installer_pkg(input: ReleaseResetInstallerPackageInput) -> int:
    root = repo_root()
    settings = load_macos_release_settings(input.config, root)
    runtime_dir = settings.runtime_dir
    release_file = resolve_path(root, input.release_file)
    release = load_release_manifest(release_file)
    pkg_output = (
        resolve_path(root, input.output)
        if input.output
        else default_clean_uninstaller_pkg_output(settings, release)
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
    run_build_reset_installer_pkg(
        settings=settings,
        release=release,
        runtime_dir=runtime_dir,
        runtime_cli=settings.runtime_cli,
        scripts_dir=settings.pkg_root.parent / "reset-installer-scripts",
        pkg_output=pkg_output,
    )
    print(f"reset-for-reinstall pkg is ready: {pkg_output}")
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
        print(f"installed runtime settings: {settings.install.install_settings_json}")
    run(["sudo", "installer", "-pkg", str(pkg_output), "-target", "/"])
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
        include_optional="testkit" in release.optional_container_services,
    )
    package_vm_home = settings.pkg_root / settings_install_home(settings).strip("/")

    return PackageContext(
        root=root,
        runtime_dir=runtime_dir,
        release=release,
        pkg_root=settings.pkg_root,
        pkg_scripts=settings.pkg_scripts,
        pkg_output=outputs.pkg_output,
        clean_uninstaller_pkg_output=outputs.clean_uninstaller_pkg_output,
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

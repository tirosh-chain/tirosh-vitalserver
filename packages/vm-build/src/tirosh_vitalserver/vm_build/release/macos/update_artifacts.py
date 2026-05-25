from __future__ import annotations

import shutil
from pathlib import Path

from tirosh_vitalserver.vm_build.config.macos.release_settings import (
    MacOSReleaseSettings,
    settings_install_value,
)
from tirosh_vitalserver.vm_build.release.macos.artifact_files import (
    copy_executable,
    copy_tree,
    install_file,
    tar_directory,
)
from tirosh_vitalserver.vm_build.release.macos.installer_templates import (
    render_packaging_executable,
)
from tirosh_vitalserver.vm_build.release.macos.models import StagedUpdateArtifacts


def stage_update_artifacts(
    *,
    root: Path,
    runtime_dir: Path,
    settings: MacOSReleaseSettings,
    artifact_dir: Path,
    app_bundle: Path,
    runtime_cli: Path,
    nginx_bundle: Path,
    docker_bundle: Path,
) -> StagedUpdateArtifacts:
    if artifact_dir.exists():
        shutil.rmtree(artifact_dir)
    runtime_tools_dir = artifact_dir / "runtime-tools"
    deploy_dir = artifact_dir / "deploy"
    runtime_tools_dir.mkdir(parents=True)
    deploy_dir.mkdir(parents=True)

    app_archive = artifact_dir / "app-bundle.tar.gz"
    tar_directory(app_archive, app_bundle.parent, app_bundle.name)

    packaging_dir = runtime_dir / "Support/Packaging"
    copy_executable(
        runtime_cli,
        runtime_tools_dir / Path(settings_install_value(settings, "vm_cli")).name,
    )
    render_packaging_executable(
        settings,
        packaging_dir / "proxy-run.template",
        runtime_tools_dir / Path(settings_install_value(settings, "proxy_runner")).name,
    )
    render_packaging_executable(
        settings,
        packaging_dir / "uninstall.template",
        runtime_tools_dir / Path(settings_install_value(settings, "uninstaller")).name,
    )
    runtime_tools_archive = artifact_dir / "runtime-tools.tar.gz"
    tar_directory(
        runtime_tools_archive,
        runtime_tools_dir,
        Path(settings_install_value(settings, "vm_cli")).name,
        Path(settings_install_value(settings, "proxy_runner")).name,
        Path(settings_install_value(settings, "uninstaller")).name,
    )

    nginx_dir = artifact_dir / "nginx"
    copy_tree(nginx_bundle, nginx_dir)
    nginx_archive = artifact_dir / "nginx-bundle.tar.gz"
    tar_directory(nginx_archive, artifact_dir, "nginx")

    stage_guest_deploy(root, runtime_dir, settings, deploy_dir, docker_bundle)
    guest_deploy_archive = artifact_dir / "guest-deploy.tar.gz"
    tar_directory(guest_deploy_archive, artifact_dir, "deploy")

    return StagedUpdateArtifacts(
        app_bundle=app_archive,
        runtime_tools=runtime_tools_archive,
        nginx_bundle=nginx_archive,
        guest_deploy=guest_deploy_archive,
    )


def stage_guest_deploy(
    root: Path,
    runtime_dir: Path,
    settings: MacOSReleaseSettings,
    deploy_dir: Path,
    docker_bundle: Path,
) -> None:
    copy_tree(runtime_dir / "Support/Guest", deploy_dir, merge=True)
    for entry in settings.guest_deploy.includes:
        source = root / entry.source
        destination = deploy_dir / entry.destination
        if source.is_dir():
            copy_tree(source, destination)
        elif source.is_file():
            install_file(source, destination)
        else:
            raise SystemExit(f"error: missing guest deploy include: {entry.source}")
    install_file(
        docker_bundle,
        deploy_dir / settings.guest_deploy.docker_image_bundle_destination,
    )

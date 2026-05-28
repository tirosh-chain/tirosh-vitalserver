from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.guest_deploy import GuestDeployConfig

VM_DATA_DIRS = ("data/deploy", "data/vital-files", "data/vr-release", "data/run")
IGNORED_NAMES = (".DS_Store", "._*", "__pycache__")


@dataclass(frozen=True)
class GuestDeployEntry:
    source: Path
    destination: Path


@dataclass(frozen=True)
class GuestDeployPlan:
    support_guest_source: Path
    deploy_dir: Path
    includes: list[GuestDeployEntry]
    docker_bundle_source: Path | None
    docker_bundle_destination: Path | None
    optional_docker_bundle_source: Path | None
    optional_docker_bundle_destination: Path | None
    vm_data_dirs: list[Path]


@dataclass(frozen=True)
class DockerImagePlan:
    build_context: Path
    platform: str
    images: list[str]
    pull_images: list[str]
    app_image: str
    app_dockerfile: Path
    audit_proxy_image: str
    audit_proxy_dockerfile: Path
    vitaldb_observer_image: str
    vitaldb_observer_dockerfile: Path
    testkit_image: str
    testkit_dockerfile: Path


@dataclass(frozen=True)
class DockerImagesConfig:
    platform: str
    bundle_path: Path
    optional_bundle_path: Path | None
    images: list[str]
    optional_images: list[str]
    app_dockerfile: str
    audit_proxy_image: str
    audit_proxy_dockerfile: str
    vitaldb_observer_image: str
    vitaldb_observer_dockerfile: str
    testkit_image: str
    testkit_dockerfile: str


def guest_deploy_plan(
    *,
    root: Path,
    runtime_dir: Path,
    deploy_dir: Path,
    vm_home: Path,
    config: GuestDeployConfig,
    docker_bundle: Path | None,
    optional_docker_bundle: Path | None = None,
) -> GuestDeployPlan:
    includes = [
        GuestDeployEntry(
            source=root / entry.source,
            destination=deploy_dir / entry.destination,
        )
        for entry in config.includes
    ]
    docker_destination = (
        deploy_dir / config.docker_image_bundle_destination if docker_bundle else None
    )
    optional_docker_destination = (
        deploy_dir / config.optional_docker_image_bundle_destination
        if docker_bundle and config.optional_docker_image_bundle_destination
        else None
    )
    return GuestDeployPlan(
        support_guest_source=runtime_dir / "Support/Guest",
        deploy_dir=deploy_dir,
        includes=includes,
        docker_bundle_source=docker_bundle,
        docker_bundle_destination=docker_destination,
        optional_docker_bundle_source=optional_docker_bundle,
        optional_docker_bundle_destination=optional_docker_destination,
        vm_data_dirs=[vm_home / relative for relative in VM_DATA_DIRS],
    )


def docker_image_plan(
    *,
    root: Path,
    platform: str,
    images: list[str],
    app_dockerfile: str,
    audit_proxy_image: str,
    audit_proxy_dockerfile: str,
    vitaldb_observer_image: str,
    vitaldb_observer_dockerfile: str,
    testkit_image: str,
    testkit_dockerfile: str,
) -> DockerImagePlan:
    if not images:
        raise DomainError("error: guest.docker_images.images must not be empty")
    app_image = images[0]
    local_build_images = {audit_proxy_image, vitaldb_observer_image, testkit_image}
    return DockerImagePlan(
        build_context=root,
        platform=platform,
        images=images,
        pull_images=[image for image in images[1:] if image not in local_build_images],
        app_image=app_image,
        app_dockerfile=root / app_dockerfile,
        audit_proxy_image=audit_proxy_image,
        audit_proxy_dockerfile=root / audit_proxy_dockerfile,
        vitaldb_observer_image=vitaldb_observer_image,
        vitaldb_observer_dockerfile=root / vitaldb_observer_dockerfile,
        testkit_image=testkit_image,
        testkit_dockerfile=root / testkit_dockerfile,
    )

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.guest_services import (
    DockerImagePlan,
    DockerImagesConfig,
    docker_image_plan,
)


@dataclass(frozen=True)
class DockerImageBundleBuildPlan:
    image_plan: DockerImagePlan
    bundle_path: Path
    compression_threads: int | None


def docker_image_bundle_build_plan(
    *,
    root: Path,
    docker_config: DockerImagesConfig,
    bundle_path: Path | None,
    platform: str | None,
    compression_threads: int | None,
) -> DockerImageBundleBuildPlan:
    image_plan = docker_image_plan(
        root=root,
        platform=platform or docker_config.platform,
        images=docker_config.images,
        app_dockerfile=docker_config.app_dockerfile,
        audit_proxy_image=docker_config.audit_proxy_image,
        audit_proxy_dockerfile=docker_config.audit_proxy_dockerfile,
        vitaldb_observer_image=docker_config.vitaldb_observer_image,
        vitaldb_observer_dockerfile=docker_config.vitaldb_observer_dockerfile,
    )
    return DockerImageBundleBuildPlan(
        image_plan=image_plan,
        bundle_path=bundle_path or docker_config.bundle_path,
        compression_threads=compression_threads,
    )

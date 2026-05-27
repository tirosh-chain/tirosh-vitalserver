from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.config.build_toml import (
    TomlTable,
    nested_section,
    optional_string,
    required_string,
    required_string_list,
)
from tirosh_vitalserver.devtools.config.paths import resolve_path
from tirosh_vitalserver.devtools.core.guest_services import DockerImagesConfig


def load_docker_images_config(config: TomlTable, root: Path) -> DockerImagesConfig:
    path = "guest.docker_images"
    docker_images = nested_section(config, path)
    return DockerImagesConfig(
        platform=optional_string(docker_images, "platform", "linux/arm64", path=path),
        bundle_path=resolve_path(
            root,
            required_string(docker_images, "bundle_path", path=path),
        ),
        images=required_string_list(docker_images, "images", path=path),
        app_dockerfile=required_string(docker_images, "app_dockerfile", path=path),
        audit_proxy_image=required_string(
            docker_images,
            "audit_proxy_image",
            path=path,
        ),
        audit_proxy_dockerfile=required_string(
            docker_images,
            "audit_proxy_dockerfile",
            path=path,
        ),
        vitaldb_observer_image=required_string(
            docker_images,
            "vitaldb_observer_image",
            path=path,
        ),
        vitaldb_observer_dockerfile=required_string(
            docker_images,
            "vitaldb_observer_dockerfile",
            path=path,
        ),
    )

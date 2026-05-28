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
        optional_bundle_path=optional_resolved_path(
            docker_images,
            root,
            "optional_bundle_path",
            path=path,
        ),
        images=required_string_list(docker_images, "images", path=path),
        optional_images=optional_string_list(
            docker_images,
            "optional_images",
            path=path,
        ),
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
        testkit_image=required_string(
            docker_images,
            "testkit_image",
            path=path,
        ),
        testkit_dockerfile=required_string(
            docker_images,
            "testkit_dockerfile",
            path=path,
        ),
    )


def optional_string_list(
    config: TomlTable,
    key: str,
    *,
    path: str,
) -> list[str]:
    value = config.get(key, [])
    if not isinstance(value, list) or not all(
        isinstance(item, str) and item for item in value
    ):
        raise SystemExit(f"error: invalid string list config value: {path}.{key}")
    return value


def optional_resolved_path(
    config: TomlTable,
    root: Path,
    key: str,
    *,
    path: str,
) -> Path | None:
    value = config.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: invalid string config value: {path}.{key}")
    return resolve_path(root, value)

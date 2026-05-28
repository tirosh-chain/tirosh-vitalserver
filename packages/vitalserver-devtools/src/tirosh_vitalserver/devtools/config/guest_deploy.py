from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.config.build_toml import (
    TomlTable,
    nested_section,
    required_string,
)
from tirosh_vitalserver.devtools.core.guest_deploy import (
    GuestDeployConfig,
    GuestDeployInclude,
    parse_guest_deploy_include,
)


def load_guest_deploy_config(config: TomlTable) -> GuestDeployConfig:
    path = "guest.deploy"
    deploy = nested_section(config, path)
    return GuestDeployConfig(
        docker_image_bundle_destination=Path(
            required_string(
                deploy,
                "docker_image_bundle_destination",
                path=path,
            )
        ),
        optional_docker_image_bundle_destination=optional_path(
            deploy,
            "optional_docker_image_bundle_destination",
            path=path,
        ),
        includes=load_guest_deploy_includes(deploy, path=path),
    )


def load_guest_deploy_includes(
    config: TomlTable,
    *,
    path: str = "guest.deploy",
) -> list[GuestDeployInclude]:
    value = config.get("include")
    if not isinstance(value, list) or not value:
        raise SystemExit(f"error: missing {path}.include list")
    return [parse_guest_deploy_include(item) for item in value]


def optional_path(config: TomlTable, key: str, *, path: str) -> Path | None:
    value = config.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: invalid string config value: {path}.{key}")
    return Path(value)

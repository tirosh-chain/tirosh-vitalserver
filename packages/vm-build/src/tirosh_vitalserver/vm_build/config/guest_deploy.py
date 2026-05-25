from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class GuestDeployInclude:
    source: Path
    destination: Path


@dataclass(frozen=True)
class GuestDeployConfig:
    docker_image_bundle_destination: Path
    includes: list[GuestDeployInclude]


def load_guest_deploy_config(config: dict[str, object]) -> GuestDeployConfig:
    destination = config.get("docker_image_bundle_destination")
    if not isinstance(destination, str) or not destination:
        raise SystemExit("error: missing guest_deploy docker_image_bundle_destination")
    return GuestDeployConfig(
        docker_image_bundle_destination=Path(destination),
        includes=load_guest_deploy_includes(config),
    )


def load_guest_deploy_includes(config: dict[str, object]) -> list[GuestDeployInclude]:
    value = config.get("include")
    if not isinstance(value, list) or not value:
        raise SystemExit("error: missing guest_deploy include list")
    return [parse_guest_deploy_include(item) for item in value]


def parse_guest_deploy_include(item: object) -> GuestDeployInclude:
    if isinstance(item, str):
        path = Path(item)
        return GuestDeployInclude(source=path, destination=path)
    return guest_deploy_include_from_table(item)


def guest_deploy_include_from_table(item: object) -> GuestDeployInclude:
    if not isinstance(item, dict):
        raise SystemExit("error: invalid guest_deploy include entry")
    source = item.get("source")
    destination = item.get("destination")
    if not isinstance(source, str) or not isinstance(destination, str):
        raise SystemExit("error: invalid guest_deploy include entry")
    return GuestDeployInclude(source=Path(source), destination=Path(destination))

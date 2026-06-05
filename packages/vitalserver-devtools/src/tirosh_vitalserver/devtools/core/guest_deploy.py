from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.devtools.core.errors import DomainError


@dataclass(frozen=True)
class GuestDeployInclude:
    source: Path
    destination: Path


@dataclass(frozen=True)
class GuestDeployConfig:
    docker_image_bundle_destination: Path
    optional_docker_image_bundle_destination: Path | None
    python_wheel_destination: Path
    python_wheel_projects: list[Path]
    includes: list[GuestDeployInclude]


def parse_guest_deploy_include(item: object) -> GuestDeployInclude:
    if isinstance(item, str):
        path = Path(item)
        return GuestDeployInclude(source=path, destination=path)
    return guest_deploy_include_from_table(item)


def guest_deploy_include_from_table(item: object) -> GuestDeployInclude:
    if not isinstance(item, dict):
        raise DomainError("error: invalid guest.deploy include entry")
    source = item.get("source")
    destination = item.get("destination")
    if not isinstance(source, str) or not isinstance(destination, str):
        raise DomainError("error: invalid guest.deploy include entry")
    return GuestDeployInclude(source=Path(source), destination=Path(destination))

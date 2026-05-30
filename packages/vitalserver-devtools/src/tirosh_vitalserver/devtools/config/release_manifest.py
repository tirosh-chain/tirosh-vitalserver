from __future__ import annotations

import json
from pathlib import Path

from tirosh_vitalserver.devtools.core.release_manifest import ReleaseManifest


def load_release_manifest(path: Path) -> ReleaseManifest:
    if not path.is_file():
        raise SystemExit(f"error: missing release manifest: {path}")
    try:
        release = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: invalid release manifest {path}: {exc}") from exc
    if not isinstance(release, dict):
        raise SystemExit(f"error: release manifest must be a JSON object: {path}")
    return ReleaseManifest(
        channel=required_release_string(release, "channel"),
        helper_version=required_release_string(release, "helperVersion"),
        release_label=required_release_string(release, "releaseLabel"),
        minimum_updater_version=required_release_string(release, "minUpdaterVersion"),
        vitalserver_version=required_release_string(release, "vitalServerVersion"),
        target_platform=required_release_string(release, "targetPlatform"),
        host_proxy_image=optional_service_string(release, "hostProxy", "image"),
        optional_container_services=optional_container_services(release),
    )


def required_release_string(release: dict[str, object], key: str) -> str:
    value = release.get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: missing release field: {key}")
    return value


def optional_service_string(
    release: dict[str, object],
    service: str,
    key: str,
) -> str | None:
    services = release.get("services")
    if services is None:
        return None
    if not isinstance(services, dict):
        raise SystemExit("error: release field services must be an object")
    service_value = services.get(service)
    if service_value is None:
        return None
    if not isinstance(service_value, dict):
        raise SystemExit(
            f"error: release service must be an object: services.{service}"
        )
    value = service_value.get(key)
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise SystemExit(
            f"error: invalid release field: services.{service}.{key}"
        )
    return value


def optional_container_services(release: dict[str, object]) -> tuple[str, ...]:
    bundle = release.get("bundle", {})
    if bundle is None:
        return ()
    if not isinstance(bundle, dict):
        raise SystemExit("error: release field bundle must be an object")
    value = bundle.get("optionalContainerServices", [])
    if not isinstance(value, list) or not all(
        isinstance(item, str) and item for item in value
    ):
        raise SystemExit(
            "error: release field bundle.optionalContainerServices must be "
            "a string list"
        )
    return tuple(value)

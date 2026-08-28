from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ReleaseManifest:
    channel: str
    helper_version: str
    release_label: str
    vitalserver_version: str
    target_platform: str
    host_proxy_image: str | None = None
    lab_image: str | None = None
    postgres_image: str | None = None
    optional_container_services: tuple[str, ...] = ()

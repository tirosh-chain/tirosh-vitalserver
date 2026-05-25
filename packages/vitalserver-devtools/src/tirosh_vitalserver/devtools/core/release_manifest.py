from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ReleaseManifest:
    channel: str
    helper_version: str
    release_label: str
    minimum_updater_version: str
    vitalserver_version: str
    target_platform: str

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ReleaseManifest:
    channel: str
    helper_version: str
    release_label: str
    minimum_updater_version: str
    vitalserver_version: str
    target_platform: str


def load_release_manifest(path: Path) -> ReleaseManifest:
    if not path.is_file():
        raise SystemExit(f"error: missing release manifest: {path}")
    release = json.loads(path.read_text(encoding="utf-8"))
    return ReleaseManifest(
        channel=required_release_string(release, "channel"),
        helper_version=required_release_string(release, "helperVersion"),
        release_label=required_release_string(release, "releaseLabel"),
        minimum_updater_version=required_release_string(release, "minUpdaterVersion"),
        vitalserver_version=required_release_string(release, "vitalServerVersion"),
        target_platform=required_release_string(release, "targetPlatform"),
    )


def required_release_string(release: dict[str, object], key: str) -> str:
    value = release.get(key)
    if not isinstance(value, str) or not value:
        raise SystemExit(f"error: missing release field: {key}")
    return value

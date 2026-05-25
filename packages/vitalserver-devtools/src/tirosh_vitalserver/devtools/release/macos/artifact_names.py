from __future__ import annotations

from tirosh_vitalserver.devtools.config.release_manifest import ReleaseManifest


def format_release_name(template: str, release: ReleaseManifest) -> str:
    return template.format(
        helperVersion=release.helper_version,
        releaseLabel=release.release_label,
        channel=release.channel,
    )

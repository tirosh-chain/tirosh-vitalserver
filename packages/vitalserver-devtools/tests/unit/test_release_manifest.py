from __future__ import annotations

import json
from pathlib import Path

from tirosh_vitalserver.devtools.config.release_manifest import load_release_manifest


def test_load_release_manifest_reads_host_proxy_image(tmp_path: Path) -> None:
    release_file = tmp_path / "release.json"
    release_file.write_text(
        json.dumps(
            {
                "channel": "dev",
                "helperVersion": "0.1.7",
                "releaseLabel": "0.1.7-dev",
                "minUpdaterVersion": "0.1.7",
                "targetPlatform": "macos-arm64",
                "vitalServerVersion": "2.3.4",
                "services": {
                    "hostProxy": {
                        "image": "nginx/1.31.1",
                    },
                },
            }
        ),
        encoding="utf-8",
    )

    release = load_release_manifest(release_file)

    assert release.host_proxy_image == "nginx/1.31.1"

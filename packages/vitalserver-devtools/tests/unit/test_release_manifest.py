from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.config.release_manifest import load_release_manifest


def test_load_release_manifest_reads_host_proxy_image(tmp_path: Path) -> None:
    release_file = tmp_path / "release.json"
    release_file.write_text(
        json.dumps(
            {
                "channel": "dev",
                "helperVersion": "0.1.7",
                "releaseLabel": "0.1.7-dev",
                "targetPlatform": "macos-arm64",
                "vitalServerVersion": "2.3.4",
                "bundle": {
                    "optionalContainerServices": ["redis-ui"],
                },
                "services": {
                    "lab": {
                        "image": "vitalserver-lab:0.2.0",
                    },
                    "postgres": {
                        "image": "postgres:16-alpine",
                    },
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
    assert release.lab_image == "vitalserver-lab:0.2.0"
    assert release.postgres_image == "postgres:16-alpine"
    assert release.optional_container_services == ("redis-ui",)
    assert not hasattr(release, "minimum_updater_version")


def test_load_release_manifest_rejects_legacy_minimum_updater_field(
    tmp_path: Path,
) -> None:
    release_file = tmp_path / "release.json"
    release_file.write_text(
        json.dumps(
            {
                "channel": "dev",
                "helperVersion": "0.2.2",
                "releaseLabel": "0.2.2-dev",
                "minUpdaterVersion": "0.1.15",
                "targetPlatform": "macos-arm64",
                "vitalServerVersion": "2.3.4",
                "bundle": {
                    "optionalContainerServices": [],
                },
                "services": {
                    "lab": {
                        "image": "vitalserver-lab:0.2.0",
                    },
                    "postgres": {
                        "image": "postgres:16-alpine",
                    },
                },
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(
        SystemExit,
        match=r"unsupported release field: minUpdaterVersion",
    ):
        load_release_manifest(release_file)


def test_load_release_manifest_requires_runtime_product_services(
    tmp_path: Path,
) -> None:
    release_file = tmp_path / "release.json"
    release_file.write_text(
        json.dumps(
            {
                "channel": "dev",
                "helperVersion": "0.2.0",
                "releaseLabel": "0.2.0-dev",
                "targetPlatform": "macos-arm64",
                "vitalServerVersion": "2.3.4",
                "bundle": {
                    "optionalContainerServices": [],
                },
                "services": {
                    "postgres": {
                        "image": "postgres:16-alpine",
                    },
                },
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(SystemExit, match=r"services\.lab\.image"):
        load_release_manifest(release_file)


def test_load_release_manifest_rejects_testkit_product_service(
    tmp_path: Path,
) -> None:
    release_file = tmp_path / "release.json"
    release_file.write_text(
        json.dumps(
            {
                "channel": "dev",
                "helperVersion": "0.2.0",
                "releaseLabel": "0.2.0-dev",
                "targetPlatform": "macos-arm64",
                "vitalServerVersion": "2.3.4",
                "bundle": {
                    "optionalContainerServices": [],
                },
                "services": {
                    "lab": {
                        "image": "vitalserver-lab:0.2.0",
                    },
                    "postgres": {
                        "image": "postgres:16-alpine",
                    },
                    "testkit": {
                        "image": "vitalserver-testkit:0.2.0",
                    },
                },
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(SystemExit, match="must not include testkit"):
        load_release_manifest(release_file)


def test_load_release_manifest_rejects_testkit_optional_service(
    tmp_path: Path,
) -> None:
    release_file = tmp_path / "release.json"
    release_file.write_text(
        json.dumps(
            {
                "channel": "dev",
                "helperVersion": "0.2.0",
                "releaseLabel": "0.2.0-dev",
                "targetPlatform": "macos-arm64",
                "vitalServerVersion": "2.3.4",
                "bundle": {
                    "optionalContainerServices": ["testkit"],
                },
                "services": {
                    "lab": {
                        "image": "vitalserver-lab:0.2.0",
                    },
                    "postgres": {
                        "image": "postgres:16-alpine",
                    },
                },
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(SystemExit, match="must not include testkit"):
        load_release_manifest(release_file)

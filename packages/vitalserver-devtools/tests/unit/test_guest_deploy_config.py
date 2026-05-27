from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.config.guest_deploy import load_guest_deploy_includes


def test_guest_deploy_include_strings_default_to_same_destination() -> None:
    mappings = load_guest_deploy_includes(
        {
            "include": [
                "apps/vitalserver/docker",
                "docs/openapi.yaml",
            ],
        }
    )

    assert [(item.source, item.destination) for item in mappings] == [
        (Path("apps/vitalserver/docker"), Path("apps/vitalserver/docker")),
        (Path("docs/openapi.yaml"), Path("docs/openapi.yaml")),
    ]


def test_guest_deploy_include_allows_destination_override() -> None:
    mappings = load_guest_deploy_includes(
        {
            "include": [
                {
                    "source": "docs/openapi.yaml",
                    "destination": "docs/api/vitalserver.openapi.yaml",
                },
            ],
        }
    )

    assert [(item.source, item.destination) for item in mappings] == [
        (Path("docs/openapi.yaml"), Path("docs/api/vitalserver.openapi.yaml")),
    ]

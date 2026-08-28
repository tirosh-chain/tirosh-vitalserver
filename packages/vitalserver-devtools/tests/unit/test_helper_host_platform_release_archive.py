from __future__ import annotations

import hashlib
import json
import tarfile
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release import (
    helper_host_platform_release_archive,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_host_platform_release import (
    HELPER_HOST_ARCHIVE_MEDIA_TYPE,
    HELPER_HOST_RELEASE_MANIFEST_SCHEMA,
)

compose_archive = (
    helper_host_platform_release_archive.compose_helper_host_platform_release_archive
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def tree_sha256(entries: dict[str, bytes]) -> str:
    digest = hashlib.sha256()
    for relative, data in sorted(entries.items()):
        digest.update(b"regular-file\0")
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256(data).encode("ascii"))
        digest.update(b"\0")
    return digest.hexdigest()


def write_contract(tmp_path: Path) -> tuple[Path, dict[str, object]]:
    release = tmp_path / "release-source"
    app_entries = {
        "Contents/Info.plist": b"info",
        "Contents/MacOS/VitalServer Helper": b"executable",
    }
    files = {
        "bin/vitalserver-vm": b"host-cli",
        **{
            f"Applications/VitalServer Helper.app/{relative}": data
            for relative, data in app_entries.items()
        },
    }
    for relative, data in files.items():
        path = release / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    services: list[dict[str, object]] = []
    sources: list[dict[str, object]] = []
    for role in ("runtime-provider", "proxy", "guest-log-sync"):
        source = tmp_path / f"{role}.plist"
        content = f"service:{role}".encode()
        source.write_bytes(content)
        services.append(
            {
                "role": role,
                "manager": "launchd",
                "name": f"com.tirosh.{role}",
                "definitionPath": f"/Library/LaunchDaemons/{role}.plist",
                "definitionSha256": sha256(content),
            }
        )
        sources.append({"role": role, "sourcePath": str(source)})
    bootstrap = tmp_path / "runtime-console-bootstrap.json"
    bootstrap.write_bytes(b'{"schemaVersion":"v1"}')
    manifest: dict[str, object] = {
        "schemaVersion": HELPER_HOST_RELEASE_MANIFEST_SCHEMA,
        "installationId": "installation-1",
        "release": {"id": "release-1", "version": "0.2.2"},
        "releaseCatalogPath": "/Library/Application Support/VitalServerHelper/releases",
        "releaseRootPath": (
            "/Library/Application Support/VitalServerHelper/releases/release-1"
        ),
        "currentReleaseLinkPath": (
            "/Library/Application Support/VitalServerHelper/current"
        ),
        "files": [
            {
                "relativePath": relative,
                "sha256": sha256(data),
                "executable": relative.endswith("vitalserver-vm")
                or "/MacOS/" in relative,
            }
            for relative, data in sorted(files.items())
        ],
        "operatorInterface": {
            "bootstrapConfigurationPath": (
                "/Library/Application Support/VitalServerHelper/"
                "runtime-console-bootstrap.json"
            ),
            "bootstrapConfigurationSha256": sha256(bootstrap.read_bytes()),
            "applicationBundlePath": "/Applications/VitalServer Helper.app",
            "applicationBundleRelativePath": ("Applications/VitalServer Helper.app"),
            "applicationBundleTreeSha256": tree_sha256(app_entries),
            "applicationBundleEntrypointRelativePath": (
                "Contents/MacOS/VitalServer Helper"
            ),
        },
        "replaceableServices": services,
        "stableComponents": [
            {
                "role": "host-installation-manager",
                "executablePath": (
                    "/usr/local/libexec/vitalserver-host-installation-manager"
                ),
                "serviceName": ("com.tirosh.vitalserver.host-installation-manager"),
            },
            {
                "role": "update-handoff-supervisor",
                "executablePath": (
                    "/usr/local/libexec/vitalserver-update-handoff-supervisor"
                ),
                "serviceName": "com.tirosh.vitalserver.update-handoff-supervisor",
            },
        ],
        "mutableStores": [
            {
                "id": "runtime-state",
                "path": (
                    "/Library/Application Support/VitalServerHelper/"
                    "runtime/runtime-state.sqlite"
                ),
                "kind": "sqlite",
                "owner": "host",
                "retention": "preserve",
            }
        ],
    }
    (release / "installation-manifest.json").write_text(
        json.dumps(manifest),
        encoding="utf-8",
    )
    composition = {
        "schemaVersion": (
            "vitalserver.helper-host-platform-release-archive-composition/v1"
        ),
        "releaseSourceDirectory": str(release),
        "serviceDefinitionSources": sources,
        "operatorInterfaceBootstrapSourcePath": str(bootstrap),
    }
    composition_path = tmp_path / "composition.json"
    composition_path.write_text(json.dumps(composition), encoding="utf-8")
    return composition_path, manifest


def test_compose_is_deterministic_and_contains_the_application_tree(
    tmp_path: Path,
) -> None:
    composition, _ = write_contract(tmp_path)
    first = tmp_path / "first.tar.gz"
    second = tmp_path / "second.tar.gz"

    first_result = compose_archive(
        composition,
        first,
    )
    second_result = compose_archive(
        composition,
        second,
    )

    assert first.read_bytes() == second.read_bytes()
    assert first_result[0] == second_result[0]
    assert first_result[2] == HELPER_HOST_ARCHIVE_MEDIA_TYPE
    with tarfile.open(first, "r:gz") as archive:
        names = set(archive.getnames())
    assert (
        "release/Applications/VitalServer Helper.app/Contents/MacOS/VitalServer Helper"
    ) in names
    assert "service-definitions/runtime-provider.plist" in names


def test_compose_rejects_application_bundle_tree_digest_mismatch(
    tmp_path: Path,
) -> None:
    composition, manifest = write_contract(tmp_path)
    manifest["operatorInterface"]["applicationBundleTreeSha256"] = "0" * 64
    release = Path(json.loads(composition.read_text())["releaseSourceDirectory"])
    (release / "installation-manifest.json").write_text(
        json.dumps(manifest),
        encoding="utf-8",
    )

    with pytest.raises(
        DomainError,
        match="application bundle tree digest differs",
    ):
        compose_archive(
            composition,
            tmp_path / "output.tar.gz",
        )


def test_compose_rejects_stable_owner_in_release_files(tmp_path: Path) -> None:
    composition, manifest = write_contract(tmp_path)
    release = Path(json.loads(composition.read_text())["releaseSourceDirectory"])
    relative = "bin/vitalserver-update-handoff-supervisor"
    (release / relative).write_bytes(b"must-not-replace")
    manifest["files"].append(
        {
            "relativePath": relative,
            "sha256": sha256(b"must-not-replace"),
            "executable": True,
        }
    )
    (release / "installation-manifest.json").write_text(
        json.dumps(manifest),
        encoding="utf-8",
    )

    with pytest.raises(DomainError, match="stable owner executable"):
        compose_archive(
            composition,
            tmp_path / "output.tar.gz",
        )

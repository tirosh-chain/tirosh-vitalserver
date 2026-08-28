from __future__ import annotations

import hashlib
import json
import tarfile
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.update_artifacts import (
    AtomicGuestRuntimeReleaseEffect,
)
from tirosh_guest_tools.application.initial_release_artifacts import (
    compose_initial_update_owner_artifacts,
)
from tirosh_guest_tools.domain.initial_update_owner_state import (
    load_initial_update_owner_state,
)


def test_composes_initial_owner_contract_from_staged_bytes(tmp_path: Path) -> None:
    deploy, release_identity, container, guest_tools = inputs(tmp_path)

    first = compose_initial_update_owner_artifacts(
        release_identity_path=release_identity,
        deploy_dir=deploy,
        container_archive=container,
        guest_tools_home=guest_tools,
    )
    first_bytes = first.read_bytes()
    first_archive = (
        deploy / "initial-owner-artifacts" / "guest-runtime-release.tar"
    ).read_bytes()
    second = compose_initial_update_owner_artifacts(
        release_identity_path=release_identity,
        deploy_dir=deploy,
        container_archive=container,
        guest_tools_home=guest_tools,
    )
    state = load_initial_update_owner_state(second)

    assert second.read_bytes() == first_bytes
    assert (
        deploy / "initial-owner-artifacts" / "guest-runtime-release.tar"
    ).read_bytes() == first_archive
    assert state.container_image_set.digest == (
        f"sha256:{hashlib.sha256(container.read_bytes()).hexdigest()}"
    )
    assert state.guest_runtime_release.digest == (
        f"sha256:{hashlib.sha256(first_archive).hexdigest()}"
    )
    assert state.container_image_set.identity == "container-image-set:0.2.2"
    assert state.guest_runtime_release.identity == (
        "guest-runtime-release:0.2.2"
    )


def test_guest_runtime_archive_rejects_symlinked_source(tmp_path: Path) -> None:
    deploy, release_identity, container, guest_tools = inputs(tmp_path)
    (guest_tools / "linked").symlink_to(guest_tools / "runtime.txt")

    with pytest.raises(RuntimeError, match="must not contain symlinks"):
        compose_initial_update_owner_artifacts(
            release_identity_path=release_identity,
            deploy_dir=deploy,
            container_archive=container,
            guest_tools_home=guest_tools,
        )


def test_first_boot_activation_replaces_directory_with_declared_slot(
    tmp_path: Path,
) -> None:
    deploy, release_identity, container, guest_tools = inputs(tmp_path)
    contract = compose_initial_update_owner_artifacts(
        release_identity_path=release_identity,
        deploy_dir=deploy,
        container_archive=container,
        guest_tools_home=guest_tools,
    )
    state = load_initial_update_owner_state(contract)
    archive = state.guest_runtime_artifact.source(deploy)
    releases = tmp_path / "guest-runtime-releases"

    AtomicGuestRuntimeReleaseEffect(
        releases_root=releases,
        active_link=guest_tools,
        reconcile=lambda: None,
    ).provision_initial(state.guest_runtime_release, archive)

    assert guest_tools.is_symlink()
    assert guest_tools.resolve() == releases / state.guest_runtime_release.identity
    assert (guest_tools / "runtime.txt").read_text(encoding="utf-8") == "runtime"
    with tarfile.open(archive, "r") as package:
        assert "runtime.txt" in package.getnames()


def inputs(tmp_path: Path) -> tuple[Path, Path, Path, Path]:
    deploy = tmp_path / "deploy"
    container = deploy / "docker-images" / "images.tar"
    container.parent.mkdir(parents=True)
    container.write_bytes(b"container bytes")
    release_identity = deploy / "build-metadata" / "fresh-install-release.json"
    release_identity.parent.mkdir(parents=True)
    release_identity.write_text(
        json.dumps(
            {
                "schemaVersion": (
                    "vitalserver.fresh-install-release-identity/v1"
                ),
                "releaseLabel": "0.2.2",
            }
        ),
        encoding="utf-8",
    )
    guest_tools = tmp_path / "guest-tools"
    guest_tools.mkdir()
    (guest_tools / "runtime.txt").write_text("runtime", encoding="utf-8")
    return deploy, release_identity, container, guest_tools

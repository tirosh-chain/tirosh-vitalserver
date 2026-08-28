from __future__ import annotations

import stat
from datetime import datetime
from pathlib import Path
from typing import BinaryIO, Protocol

from tirosh_guest_tools.domain.container_image_set import ContainerImageSet
from tirosh_guest_tools.domain.guest_runtime_release import GuestRuntimeRelease
from tirosh_guest_tools.domain.initial_update_owner_state import (
    InitialOwnerArtifact,
    load_initial_update_owner_state,
)


class InitialUpdateOwnerRepository(Protocol):
    def initial_update_owner_state_is_provisioned(
        self,
        *,
        contract_digest: str,
        container_image_set: ContainerImageSet,
        container_archive: str,
        guest_runtime_release: GuestRuntimeRelease,
    ) -> bool: ...

    def provision_initial_update_owner_state(
        self,
        *,
        container_image_set: ContainerImageSet,
        contract_digest: str,
        container_archive: str,
        guest_runtime_release: GuestRuntimeRelease,
        observed_at: datetime,
    ) -> None: ...


class InitialUpdateArtifactStore(Protocol):
    def import_stream(
        self,
        *,
        kind: str,
        digest: str,
        stream: BinaryIO,
        size_bytes: int,
    ) -> str: ...


class InitialGuestRuntimeActivator(Protocol):
    def provision_initial(
        self,
        release: GuestRuntimeRelease,
        archive: Path,
    ) -> None: ...


def provision_initial_update_owner_state(
    *,
    contract_path: Path,
    deploy_dir: Path,
    repository: InitialUpdateOwnerRepository,
    artifacts: InitialUpdateArtifactStore,
    guest_runtime_activator: InitialGuestRuntimeActivator,
    observed_at: datetime,
) -> None:
    state = load_initial_update_owner_state(contract_path)
    if repository.initial_update_owner_state_is_provisioned(
        contract_digest=state.contract_digest,
        container_image_set=state.container_image_set,
        container_archive=state.container_artifact.owner_reference,
        guest_runtime_release=state.guest_runtime_release,
    ):
        return
    _import_artifact(
        deploy_dir=deploy_dir,
        kind="container-image-set",
        declaration=state.container_artifact,
        artifacts=artifacts,
    )
    _import_artifact(
        deploy_dir=deploy_dir,
        kind="guest-runtime-release",
        declaration=state.guest_runtime_artifact,
        artifacts=artifacts,
    )
    guest_runtime_activator.provision_initial(
        state.guest_runtime_release,
        state.guest_runtime_artifact.source(deploy_dir),
    )
    repository.provision_initial_update_owner_state(
        container_image_set=state.container_image_set,
        contract_digest=state.contract_digest,
        container_archive=state.container_artifact.owner_reference,
        guest_runtime_release=state.guest_runtime_release,
        observed_at=observed_at,
    )


def _import_artifact(
    *,
    deploy_dir: Path,
    kind: str,
    declaration: InitialOwnerArtifact,
    artifacts: InitialUpdateArtifactStore,
) -> None:
    source = declaration.source(deploy_dir)
    try:
        source_status = source.lstat()
    except OSError as error:
        raise RuntimeError(
            f"Initial {kind} archive is unavailable: {source}: {error}"
        ) from error
    if not stat.S_ISREG(source_status.st_mode):
        raise RuntimeError(
            f"Initial {kind} archive must be a regular file: {source}."
        )
    with source.open("rb") as stream:
        observed_reference = artifacts.import_stream(
            kind=kind,
            digest=declaration.digest,
            stream=stream,
            size_bytes=source_status.st_size,
        )
    if observed_reference != declaration.owner_reference:
        raise RuntimeError(
            f"Initial {kind} archive owner reference mismatch "
            f"expected={declaration.owner_reference} "
            f"actual={observed_reference}."
        )

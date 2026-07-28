from __future__ import annotations

import hashlib
import json
import sqlite3
from datetime import UTC, datetime
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.sqlite_control import (
    SQLiteControlRepository,
)
from tirosh_guest_tools.adapters.outbound.update_artifacts import (
    ImmutableUpdateArtifactStore,
)
from tirosh_guest_tools.application.guest_control.initial_update_owner import (
    provision_initial_update_owner_state,
)
from tirosh_guest_tools.domain.container_image_set import (
    ContainerImageSetConflictError,
    ContainerImageSetDependencyError,
)
from tirosh_guest_tools.domain.guest_runtime_release import (
    GuestRuntimeReleaseDependencyError,
)
from tirosh_guest_tools.domain.initial_update_owner_state import (
    InitialUpdateOwnerStateContractError,
    load_initial_update_owner_state,
)


class RecordingActivator:
    def __init__(self) -> None:
        self.calls: list[tuple[object, Path]] = []

    def provision_initial(self, release: object, archive: Path) -> None:
        self.calls.append((release, archive))


def test_provisions_both_owners_from_verified_archives(tmp_path: Path) -> None:
    deploy, contract = write_contract(tmp_path)
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()

    activator = RecordingActivator()
    provision_initial_update_owner_state(
        contract_path=contract,
        deploy_dir=deploy,
        repository=repository,
        artifacts=ImmutableUpdateArtifactStore(tmp_path / "artifacts"),
        guest_runtime_activator=activator,
        observed_at=datetime(2026, 7, 29, tzinfo=UTC),
    )

    assert repository.read_current().identity == "container-image-set:0.2.2-dev"
    active = repository.read_active_guest_runtime_release()
    assert active.identity == "guest-runtime-release:0.2.2-dev"
    assert active.archive.startswith("guest-runtime-release/")
    assert len(activator.calls) == 1


def test_digest_mismatch_provisions_neither_owner(tmp_path: Path) -> None:
    deploy, contract = write_contract(tmp_path)
    document = json.loads(contract.read_text(encoding="utf-8"))
    document["containerImageSet"]["artifact"]["digest"] = "sha256:" + "0" * 64
    document["containerImageSet"]["artifact"]["ownerReference"] = (
        "container-image-set/" + "0" * 64 + ".archive"
    )
    contract.write_text(json.dumps(document), encoding="utf-8")
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()

    with pytest.raises(RuntimeError, match="digest mismatch"):
        provision_initial_update_owner_state(
            contract_path=contract,
            deploy_dir=deploy,
            repository=repository,
            artifacts=ImmutableUpdateArtifactStore(tmp_path / "artifacts"),
            guest_runtime_activator=RecordingActivator(),
            observed_at=datetime(2026, 7, 29, tzinfo=UTC),
        )

    with pytest.raises(ContainerImageSetDependencyError):
        repository.read_current()
    with pytest.raises(GuestRuntimeReleaseDependencyError):
        repository.read_active_guest_runtime_release()


def test_atomic_repository_rejects_partial_existing_state(tmp_path: Path) -> None:
    _, contract = write_contract(tmp_path)
    state = load_initial_update_owner_state(contract)
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    repository.provision_current_container_image_set(
        state.container_image_set,
        observed_at=datetime(2026, 7, 29, tzinfo=UTC),
    )

    with pytest.raises(
        ContainerImageSetConflictError,
        match="without its provisioning receipt",
    ):
        repository.provision_initial_update_owner_state(
            contract_digest=state.contract_digest,
            container_image_set=state.container_image_set,
            container_archive=state.container_artifact.owner_reference,
            guest_runtime_release=state.guest_runtime_release,
            observed_at=datetime(2026, 7, 29, tzinfo=UTC),
        )

    with pytest.raises(GuestRuntimeReleaseDependencyError):
        repository.read_active_guest_runtime_release()


def test_exact_provisioning_receipt_is_idempotent_without_reactivation(
    tmp_path: Path,
) -> None:
    deploy, contract = write_contract(tmp_path)
    state = load_initial_update_owner_state(contract)
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    activator = RecordingActivator()

    for _ in range(2):
        provision_initial_update_owner_state(
            contract_path=contract,
            deploy_dir=deploy,
            repository=repository,
            artifacts=ImmutableUpdateArtifactStore(tmp_path / "artifacts"),
            guest_runtime_activator=activator,
            observed_at=datetime(2026, 7, 29, tzinfo=UTC),
        )

    assert repository.read_current() == state.container_image_set
    assert repository.read_active_guest_runtime_release() == (
        state.guest_runtime_release
    )
    assert len(activator.calls) == 1


def test_receipt_preserves_updated_current_and_active_state_on_reboot(
    tmp_path: Path,
) -> None:
    deploy, contract = write_contract(tmp_path)
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    activator = RecordingActivator()
    provision_initial_update_owner_state(
        contract_path=contract,
        deploy_dir=deploy,
        repository=repository,
        artifacts=ImmutableUpdateArtifactStore(tmp_path / "artifacts"),
        guest_runtime_activator=activator,
        observed_at=datetime(2026, 7, 29, tzinfo=UTC),
    )
    with sqlite3.connect(tmp_path / "control.sqlite") as connection:
        connection.execute(
            "INSERT INTO container_image_sets VALUES (?, ?, ?)",
            ("container-image-set:0.2.3", "sha256:" + "1" * 64, "2026-07-29"),
        )
        connection.execute(
            "UPDATE current_container_image_set SET identity = ?",
            ("container-image-set:0.2.3",),
        )
        connection.execute(
            "INSERT INTO guest_runtime_releases VALUES (?, ?, ?, ?)",
            (
                "guest-runtime-release:0.2.3",
                "guest-runtime-release/" + "2" * 64 + ".archive",
                "sha256:" + "2" * 64,
                "2026-07-29",
            ),
        )
        connection.execute(
            "UPDATE active_guest_runtime_release SET identity = ?",
            ("guest-runtime-release:0.2.3",),
        )

    provision_initial_update_owner_state(
        contract_path=contract,
        deploy_dir=deploy,
        repository=repository,
        artifacts=ImmutableUpdateArtifactStore(tmp_path / "artifacts"),
        guest_runtime_activator=activator,
        observed_at=datetime(2026, 7, 30, tzinfo=UTC),
    )

    assert repository.read_current().identity == "container-image-set:0.2.3"
    assert (
        repository.read_active_guest_runtime_release().identity
        == "guest-runtime-release:0.2.3"
    )
    assert len(activator.calls) == 1


def test_tampered_contract_is_rejected_by_existing_receipt(tmp_path: Path) -> None:
    deploy, contract = write_contract(tmp_path)
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    activator = RecordingActivator()
    provision_initial_update_owner_state(
        contract_path=contract,
        deploy_dir=deploy,
        repository=repository,
        artifacts=ImmutableUpdateArtifactStore(tmp_path / "artifacts"),
        guest_runtime_activator=activator,
        observed_at=datetime(2026, 7, 29, tzinfo=UTC),
    )
    document = json.loads(contract.read_text(encoding="utf-8"))
    document["releaseLabel"] = "0.2.2-tampered"
    document["containerImageSet"]["identity"] = (
        "container-image-set:0.2.2-tampered"
    )
    document["guestRuntimeRelease"]["identity"] = (
        "guest-runtime-release:0.2.2-tampered"
    )
    contract.write_text(json.dumps(document), encoding="utf-8")

    with pytest.raises(
        ContainerImageSetConflictError,
        match="receipt disagrees",
    ):
        provision_initial_update_owner_state(
            contract_path=contract,
            deploy_dir=deploy,
            repository=repository,
            artifacts=ImmutableUpdateArtifactStore(tmp_path / "artifacts"),
            guest_runtime_activator=activator,
            observed_at=datetime(2026, 7, 30, tzinfo=UTC),
        )

    assert len(activator.calls) == 1


def test_receipt_does_not_hide_missing_current_owner_pointer(
    tmp_path: Path,
) -> None:
    deploy, contract = write_contract(tmp_path)
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    provision_initial_update_owner_state(
        contract_path=contract,
        deploy_dir=deploy,
        repository=repository,
        artifacts=ImmutableUpdateArtifactStore(tmp_path / "artifacts"),
        guest_runtime_activator=RecordingActivator(),
        observed_at=datetime(2026, 7, 29, tzinfo=UTC),
    )
    with sqlite3.connect(database) as connection:
        connection.execute("DELETE FROM current_container_image_set")

    with pytest.raises(
        ContainerImageSetDependencyError,
        match="owner pointers are missing",
    ):
        provision_initial_update_owner_state(
            contract_path=contract,
            deploy_dir=deploy,
            repository=repository,
            artifacts=ImmutableUpdateArtifactStore(tmp_path / "artifacts"),
            guest_runtime_activator=RecordingActivator(),
            observed_at=datetime(2026, 7, 30, tzinfo=UTC),
        )


def test_repository_rolls_back_all_initial_rows_on_archive_conflict(
    tmp_path: Path,
) -> None:
    _, contract = write_contract(tmp_path)
    state = load_initial_update_owner_state(contract)
    database = tmp_path / "control.sqlite"
    repository = SQLiteControlRepository(database)
    repository.migrate_schema()
    with sqlite3.connect(database) as connection:
        connection.execute(
            "INSERT INTO guest_runtime_releases VALUES (?, ?, ?, ?)",
            (
                "guest-runtime-release:conflict",
                state.guest_runtime_release.archive,
                "sha256:" + "3" * 64,
                "2026-07-29",
            ),
        )

    with pytest.raises(Exception, match="archive"):
        repository.provision_initial_update_owner_state(
            contract_digest=state.contract_digest,
            container_image_set=state.container_image_set,
            container_archive=state.container_artifact.owner_reference,
            guest_runtime_release=state.guest_runtime_release,
            observed_at=datetime(2026, 7, 29, tzinfo=UTC),
        )

    with sqlite3.connect(database) as connection:
        assert connection.execute(
            "SELECT COUNT(*) FROM current_container_image_set"
        ).fetchone() == (0,)
        assert connection.execute(
            "SELECT COUNT(*) FROM active_guest_runtime_release"
        ).fetchone() == (0,)
        assert connection.execute(
            "SELECT COUNT(*) FROM initial_update_owner_provisioning"
        ).fetchone() == (0,)
        assert connection.execute(
            "SELECT COUNT(*) FROM container_image_sets"
        ).fetchone() == (0,)


def test_contract_rejects_unknown_and_unsafe_archive_path(tmp_path: Path) -> None:
    _, contract = write_contract(tmp_path)
    document = json.loads(contract.read_text(encoding="utf-8"))
    document["containerImageSet"]["artifact"]["relativePath"] = "../image.tar"
    document["inferredFromCompose"] = True
    contract.write_text(json.dumps(document), encoding="utf-8")

    with pytest.raises(InitialUpdateOwnerStateContractError):
        load_initial_update_owner_state(contract)


def write_contract(tmp_path: Path) -> tuple[Path, Path]:
    deploy = tmp_path / "deploy"
    container = deploy / "initial-owner-artifacts" / "container.tar"
    guest = deploy / "initial-owner-artifacts" / "guest-runtime.tar"
    container.parent.mkdir(parents=True)
    container.write_bytes(b"container archive")
    guest.write_bytes(b"guest runtime archive")
    container_digest = hashlib.sha256(container.read_bytes()).hexdigest()
    guest_digest = hashlib.sha256(guest.read_bytes()).hexdigest()
    contract = deploy / "initial-update-owner-state.json"
    contract.write_text(
        json.dumps(
            {
                "schemaVersion": "vitalserver.initial-update-owner-state/v1",
                "releaseLabel": "0.2.2-dev",
                "containerImageSet": {
                    "identity": "container-image-set:0.2.2-dev",
                    "artifact": {
                        "relativePath": "initial-owner-artifacts/container.tar",
                        "digest": f"sha256:{container_digest}",
                        "ownerReference": (
                            f"container-image-set/{container_digest}.archive"
                        ),
                    },
                },
                "guestRuntimeRelease": {
                    "identity": "guest-runtime-release:0.2.2-dev",
                    "artifact": {
                        "relativePath": "initial-owner-artifacts/guest-runtime.tar",
                        "digest": f"sha256:{guest_digest}",
                        "ownerReference": (
                            f"guest-runtime-release/{guest_digest}.archive"
                        ),
                    },
                },
            }
        ),
        encoding="utf-8",
    )
    return deploy, contract

import sqlite3
from dataclasses import replace
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from tirosh_vitalserver.recorder_recovery.adapters.inbound.api.app import (
    create_recorder_recovery_app,
)
from tirosh_vitalserver.recorder_recovery.adapters.outbound import (
    RecoveryArtifactRegistryConflict,
    RecoveryArtifactRegistryInvalid,
    SqliteRecoveryArtifactRegistry,
)
from tirosh_vitalserver.recorder_recovery.application.ports import IndexedVitalArtifact
from tirosh_vitalserver.recorder_recovery.domain import (
    ArtifactPublishEvent,
    ArtifactPublishState,
    RecoveryArtifactOrigin,
    RecoveryArtifactReceipt,
    transition_artifact_publish,
)


def test_registry_persists_and_reads_private_artifact_path(tmp_path: Path) -> None:
    registry = SqliteRecoveryArtifactRegistry(tmp_path / "registry.sqlite3")
    receipt = artifact_receipt(tmp_path)

    registry.register_export(receipt)

    assert registry.get(receipt.artifact_id) == receipt
    assert registry.list() == (receipt,)


def test_registry_accepts_same_receipt_idempotently(tmp_path: Path) -> None:
    registry = SqliteRecoveryArtifactRegistry(tmp_path / "registry.sqlite3")
    receipt = artifact_receipt(tmp_path)

    registry.register_export(receipt)
    registry.register_export(replace(receipt, created_at=4.0))

    assert registry.list() == (receipt,)


def test_registry_persists_explicit_publish_operation_state(tmp_path: Path) -> None:
    registry = SqliteRecoveryArtifactRegistry(tmp_path / "registry.sqlite3")
    receipt = artifact_receipt(tmp_path)
    registry.register_export(receipt)
    initial = registry.get_record(receipt.artifact_id)
    assert initial is not None

    requested = transition_artifact_publish(
        initial,
        ArtifactPublishEvent.REQUEST,
        occurred_at=10.0,
        attempt_id="attempt-a",
    )
    registry.save_publish(requested)

    restored = registry.get_record(receipt.artifact_id)
    assert restored == requested
    assert restored.publish_state is ArtifactPublishState.REQUESTED


def test_registry_rejects_same_artifact_id_with_different_receipt(
    tmp_path: Path,
) -> None:
    registry = SqliteRecoveryArtifactRegistry(tmp_path / "registry.sqlite3")
    receipt = artifact_receipt(tmp_path)
    conflicting = replace(receipt, sha256="c" * 64)

    registry.register_export(receipt)

    with pytest.raises(RecoveryArtifactRegistryConflict):
        registry.register_export(conflicting)


def test_registry_rejects_unknown_schema_version(tmp_path: Path) -> None:
    path = tmp_path / "registry.sqlite3"
    registry = SqliteRecoveryArtifactRegistry(path)
    registry.register_export(artifact_receipt(tmp_path))
    with sqlite3.connect(path) as connection:
        connection.execute(
            "UPDATE recovery_artifact_registry_metadata SET schema_version = 99"
        )

    with pytest.raises(RecoveryArtifactRegistryInvalid):
        registry.list()


def test_artifact_read_api_does_not_expose_private_path(tmp_path: Path) -> None:
    registry = SqliteRecoveryArtifactRegistry(tmp_path / "registry.sqlite3")
    receipt = artifact_receipt(tmp_path)
    registry.register_export(receipt)
    client = TestClient(create_recorder_recovery_app(registry=registry))

    response = client.get(f"/artifacts/{receipt.artifact_id}")

    assert response.status_code == 200
    document = response.json()
    assert document["exportState"] == "exported"
    assert document["publishState"] == "notRequested"
    assert document["receipt"]["artifactId"] == receipt.artifact_id
    assert "path" not in document["receipt"]


def test_artifact_publish_api_persists_vitalserver_index_proof(tmp_path: Path) -> None:
    registry = SqliteRecoveryArtifactRegistry(tmp_path / "registry.sqlite3")
    receipt = artifact_receipt(tmp_path)
    registry.register_export(receipt)

    class Publisher:
        def find_indexed(self, filename: str) -> None:
            assert filename == receipt.filename
            return None

        def upload(self, selected: RecoveryArtifactReceipt) -> None:
            assert selected == receipt

        def wait_until_indexed(
            self,
            filename: str,
            *,
            size_bytes: int,
        ) -> IndexedVitalArtifact:
            assert filename == receipt.filename
            assert size_bytes == receipt.size_bytes
            return IndexedVitalArtifact(
                filename=filename,
                relative_path=f"VR_A/202601/260101/{filename}",
                size_bytes=size_bytes,
            )

    client = TestClient(
        create_recorder_recovery_app(registry=registry, publisher=Publisher())
    )

    response = client.post(f"/artifacts/{receipt.artifact_id}/publish")

    assert response.status_code == 200
    assert response.json()["publishState"] == "published"
    restored = client.get(f"/artifacts/{receipt.artifact_id}").json()
    assert restored["indexedSizeBytes"] == receipt.size_bytes
    assert restored["publishAttemptId"]


def artifact_receipt(tmp_path: Path) -> RecoveryArtifactReceipt:
    return RecoveryArtifactReceipt(
        artifact_id="a" * 64,
        origin=RecoveryArtifactOrigin.COLD_PATH_RECOVERY,
        producer="recorder-recovery",
        writer_version="3",
        vrcode="VR_A",
        room_names=("OR-A",),
        source_archive_id="raw-a",
        source_start_offset=0,
        source_end_offset=10,
        coverage_started_at=1.0,
        coverage_ended_at=2.0,
        format_version=3,
        sha256="b" * 64,
        path=str(tmp_path / "VR_A_260101_000000.vital"),
        filename="VR_A_260101_000000.vital",
        size_bytes=10,
        created_at=3.0,
        track_count=1,
    )

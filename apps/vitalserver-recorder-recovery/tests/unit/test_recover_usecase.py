from collections.abc import Iterable
from pathlib import Path
from typing import Any

from tirosh_vitalserver.core.domain.vital_file.models import PayloadFile
from tirosh_vitalserver.recorder_recovery.application.usecases import recover as module
from tirosh_vitalserver.recorder_recovery.domain import (
    RecoveryArtifactOrigin,
    RecoveryArtifactReceipt,
)


class RecordingRegistry:
    def __init__(self) -> None:
        self.receipts: list[RecoveryArtifactReceipt] = []

    def register_export(self, receipt: RecoveryArtifactReceipt) -> None:
        self.receipts.append(receipt)

    def get(self, artifact_id: str) -> RecoveryArtifactReceipt | None:
        return next(
            (
                receipt
                for receipt in self.receipts
                if receipt.artifact_id == artifact_id
            ),
            None,
        )

    def list(self) -> tuple[RecoveryArtifactReceipt, ...]:
        return tuple(self.receipts)


def test_recovery_uploads_only_artifacts_created_by_current_job(
    tmp_path: Path, monkeypatch: Any
) -> None:
    output_dir = tmp_path / "exports"
    output_dir.mkdir()
    stale = output_dir / "STALE_260101_000000_auto_export.vital"
    stale.write_bytes(b"stale")
    current = output_dir / "VR_A_260101_000001_auto_export.vital"

    class FakeExporter:
        def __init__(self, **kwargs: Any) -> None:
            assert kwargs == {}

        def export_raw_archive(self, *args: Any, **kwargs: Any) -> tuple[Any, ...]:
            current.write_bytes(b"current")
            return (
                RecoveryArtifactReceipt(
                    artifact_id="a" * 64,
                    origin=RecoveryArtifactOrigin.COLD_PATH_RECOVERY,
                    producer="test",
                    writer_version="1",
                    vrcode="VR_A",
                    room_names=("OR-A",),
                    source_archive_id="raw-a",
                    source_start_offset=10,
                    source_end_offset=20,
                    coverage_started_at=1.0,
                    coverage_ended_at=2.0,
                    format_version=3,
                    sha256="b" * 64,
                    path=str(current),
                    filename=current.name,
                    size_bytes=current.stat().st_size,
                    created_at=1.0,
                    track_count=1,
                ),
            )

    uploaded: list[Path] = []

    def fake_upload(
        client: object, payloads: Iterable[PayloadFile], **kwargs: object
    ) -> module.TransferSummary:
        del client
        del kwargs
        uploaded.extend(payload.path for payload in payloads)
        return module.TransferSummary(results=(), elapsed_seconds=0.0)

    monkeypatch.setattr(module, "RawArchiveVitalFileExporter", FakeExporter)
    monkeypatch.setattr(module, "VitalServerClient", lambda *args, **kwargs: object())
    monkeypatch.setattr(module, "upload_vital_files", fake_upload)
    monkeypatch.setattr(module, "assert_transfer_success", lambda *args, **kwargs: None)

    registry = RecordingRegistry()
    module.recover_raw_archive_vital(
        module.RawArchiveVitalRecoveryRequest(
            raw_archive_path=tmp_path / "raw.jsonl",
            output_dir=output_dir,
            vitalserver_url="http://app",
            vrcode="VR_A",
            start_offset=10,
            end_offset=20,
            skip_filename_check=True,
        ),
        registry=registry,
    )

    assert uploaded == [current]
    assert registry.receipts[0].artifact_id == "a" * 64


def test_export_only_does_not_construct_vitalserver_client(
    tmp_path: Path,
    monkeypatch: Any,
) -> None:
    receipt = RecoveryArtifactReceipt(
        artifact_id="a" * 64,
        origin=RecoveryArtifactOrigin.COLD_PATH_RECOVERY,
        producer="test",
        writer_version="1",
        vrcode="VR_A",
        room_names=("OR-A",),
        source_archive_id="raw-a",
        source_start_offset=0,
        source_end_offset=10,
        coverage_started_at=1.0,
        coverage_ended_at=2.0,
        format_version=3,
        sha256="b" * 64,
        path=str(tmp_path / "artifact.vital"),
        filename="VR_A_260101_000000.vital",
        size_bytes=10,
        created_at=3.0,
        track_count=1,
    )

    class FakeExporter:
        def __init__(self, **kwargs: Any) -> None:
            assert kwargs == {}

        def export_raw_archive(self, *args: Any, **kwargs: Any) -> tuple[Any, ...]:
            return (receipt,)

    monkeypatch.setattr(module, "RawArchiveVitalFileExporter", FakeExporter)
    monkeypatch.setattr(
        module,
        "VitalServerClient",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            AssertionError("export-only must not construct a VitalServer client")
        ),
    )

    registry = RecordingRegistry()
    result = module.export_raw_archive_vital(
        module.RawArchiveVitalExportRequest(
            raw_archive_path=tmp_path / "raw.jsonl",
            output_dir=tmp_path / "exports",
            vrcode="VR_A",
            start_offset=0,
            end_offset=10,
        ),
        registry=registry,
    )

    assert result.artifacts == (receipt,)
    assert registry.receipts == [receipt]
    document = module.export_result_to_document(result)
    assert document["operation"] == "export"
    assert document["artifacts"][0]["origin"] == "coldPathRecovery"

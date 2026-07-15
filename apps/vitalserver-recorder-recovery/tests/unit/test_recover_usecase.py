from collections.abc import Iterable
from pathlib import Path
from typing import Any

from tirosh_vitalserver.core.domain.vital_file.models import PayloadFile
from tirosh_vitalserver.recorder_recovery.application.usecases import recover as module


def test_recovery_uploads_only_artifacts_created_by_current_job(
    tmp_path: Path, monkeypatch: Any
) -> None:
    output_dir = tmp_path / "exports"
    output_dir.mkdir()
    stale = output_dir / "STALE_260101_000000_auto_export.vital"
    stale.write_bytes(b"stale")
    current = output_dir / "VR_A_260101_000001_auto_export.vital"

    class FakeExporter:
        def export_raw_archive(self, *args: Any, **kwargs: Any) -> tuple[Any, ...]:
            current.write_bytes(b"current")
            return (
                module.RawArchiveVitalArtifact(
                    vrcode="VR_A",
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

    module.recover_raw_archive_vital(
        module.RawArchiveVitalRecoveryRequest(
            raw_archive_path=tmp_path / "raw.jsonl",
            output_dir=output_dir,
            vitalserver_url="http://app",
            vrcode="VR_A",
            start_offset=10,
            end_offset=20,
            skip_filename_check=True,
        )
    )

    assert uploaded == [current]

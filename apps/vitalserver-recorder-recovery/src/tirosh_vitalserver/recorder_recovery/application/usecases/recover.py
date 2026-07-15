"""Use case for raw archive to `.vital` recovery."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.core.domain.vital_file import (
    assert_vital_filenames,
    iter_vital_files,
)
from tirosh_vitalserver.recorder_recovery.adapters.outbound import (
    RawArchiveVitalArtifact,
    RawArchiveVitalFileExporter,
    VitalServerClient,
)
from tirosh_vitalserver.recorder_recovery.application.assertions import (
    assert_transfer_success,
)
from tirosh_vitalserver.recorder_recovery.application.metrics import (
    transfer_failed_requests,
    transfer_successful_requests,
)
from tirosh_vitalserver.recorder_recovery.application.results import TransferSummary
from tirosh_vitalserver.recorder_recovery.application.usecases.upload import (
    upload_vital_files,
)


@dataclass(frozen=True)
class RawArchiveVitalRecoveryRequest:
    """Explicit inputs for one raw archive recovery operation."""

    raw_archive_path: Path
    output_dir: Path
    vitalserver_url: str
    endpoint: str = "/upload"
    vrcode: str | None = None
    timeout: float = 30.0
    concurrency: int = 1
    repeat: int = 1
    max_failure_rate: float = 0.0
    skip_filename_check: bool = False
    start_offset: int = 0
    end_offset: int | None = None


@dataclass(frozen=True)
class RawArchiveVitalRecoveryResult:
    """Artifacts and upload summary from one recovery operation."""

    artifacts: tuple[RawArchiveVitalArtifact, ...]
    upload: TransferSummary


def recover_raw_archive_vital(
    request: RawArchiveVitalRecoveryRequest,
) -> RawArchiveVitalRecoveryResult:
    """Export recorder raw archive payloads as `.vital` files and upload them."""

    exporter = RawArchiveVitalFileExporter()
    artifacts = exporter.export_raw_archive(
        request.raw_archive_path,
        request.output_dir,
        vrcode=request.vrcode,
        start_offset=request.start_offset,
        end_offset=request.end_offset,
    )
    payloads = tuple(
        payload
        for artifact in artifacts
        for payload in iter_vital_files(artifact.path)
    )
    if not request.skip_filename_check:
        assert_vital_filenames(payloads)

    client = VitalServerClient(request.vitalserver_url, timeout=request.timeout)
    summary = upload_vital_files(
        client,
        payloads,
        vrcode=request.vrcode,
        concurrency=request.concurrency,
        repeat=request.repeat,
        endpoint=request.endpoint,
    )
    assert_transfer_success(summary, max_failure_rate=request.max_failure_rate)

    return RawArchiveVitalRecoveryResult(artifacts=artifacts, upload=summary)


def recovery_result_to_document(
    result: RawArchiveVitalRecoveryResult,
) -> dict[str, object]:
    """Return a JSON-serializable recovery result document."""

    return {
        "artifacts": [
            {
                "vrcode": artifact.vrcode,
                "path": artifact.path,
                "filename": artifact.filename,
                "sizeBytes": artifact.size_bytes,
                "createdAt": artifact.created_at,
                "trackCount": artifact.track_count,
            }
            for artifact in result.artifacts
        ],
        "upload": transfer_summary_to_document(result.upload),
    }


def transfer_summary_to_document(summary: TransferSummary) -> dict[str, object]:
    """Return a JSON-serializable upload summary document."""

    return {
        "elapsedSeconds": summary.elapsed_seconds,
        "totalRequests": len(summary.results),
        "successfulRequests": transfer_successful_requests(summary),
        "failedRequests": transfer_failed_requests(summary),
        "results": [
            {
                "path": str(result.path),
                "bytesSent": result.bytes_sent,
                "statusCode": result.response.status_code,
                "elapsedSeconds": result.response.elapsed_seconds,
                "error": result.error,
            }
            for result in summary.results
        ],
    }

"""Use case for raw archive to `.vital` recovery."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from tirosh_vitalserver.core.domain.vital_file import (
    assert_vital_filenames,
    iter_vital_files,
)
from tirosh_vitalserver.recorder_recovery.adapters.outbound import (
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
from tirosh_vitalserver.recorder_recovery.application.ports import (
    RecoveryArtifactRegistryPort,
)
from tirosh_vitalserver.recorder_recovery.application.results import TransferSummary
from tirosh_vitalserver.recorder_recovery.application.usecases.upload import (
    upload_vital_files,
)
from tirosh_vitalserver.recorder_recovery.domain import (
    RecoveryArtifactOrigin,
    RecoveryArtifactReceipt,
    recovery_artifact_receipt_to_document,
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

    artifacts: tuple[RecoveryArtifactReceipt, ...]
    upload: TransferSummary


@dataclass(frozen=True)
class RawArchiveVitalExportRequest:
    """Explicit inputs for an export-only cold-path operation."""

    raw_archive_path: Path
    output_dir: Path
    vrcode: str | None = None
    start_offset: int = 0
    end_offset: int | None = None
    origin: RecoveryArtifactOrigin = RecoveryArtifactOrigin.COLD_PATH_RECOVERY


@dataclass(frozen=True)
class RawArchiveVitalExportResult:
    """Receipts created without publishing to VitalServer."""

    artifacts: tuple[RecoveryArtifactReceipt, ...]


def export_raw_archive_vital(
    request: RawArchiveVitalExportRequest,
    *,
    registry: RecoveryArtifactRegistryPort,
) -> RawArchiveVitalExportResult:
    """Export raw archive artifacts without invoking a library upload."""

    artifacts = RawArchiveVitalFileExporter().export_raw_archive(
        request.raw_archive_path,
        request.output_dir,
        vrcode=request.vrcode,
        start_offset=request.start_offset,
        end_offset=request.end_offset,
        origin=request.origin,
    )
    for artifact in artifacts:
        registry.register_export(artifact)
    return RawArchiveVitalExportResult(artifacts=artifacts)


def recover_raw_archive_vital(
    request: RawArchiveVitalRecoveryRequest,
    *,
    registry: RecoveryArtifactRegistryPort,
) -> RawArchiveVitalRecoveryResult:
    """Export recorder raw archive payloads as `.vital` files and upload them."""

    export = export_raw_archive_vital(
        RawArchiveVitalExportRequest(
            raw_archive_path=request.raw_archive_path,
            output_dir=request.output_dir,
            vrcode=request.vrcode,
            start_offset=request.start_offset,
            end_offset=request.end_offset,
        ),
        registry=registry,
    )
    artifacts = export.artifacts
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
            recovery_artifact_receipt_to_document(artifact)
            for artifact in result.artifacts
        ],
        "upload": transfer_summary_to_document(result.upload),
    }


def export_result_to_document(
    result: RawArchiveVitalExportResult,
) -> dict[str, object]:
    """Return an export-only result without publish state."""

    return {
        "operation": "export",
        "artifacts": [
            recovery_artifact_receipt_to_document(artifact)
            for artifact in result.artifacts
        ],
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

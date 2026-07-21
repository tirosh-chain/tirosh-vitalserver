"""FastAPI app for product recorder raw archive recovery."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse

from tirosh_vitalserver.recorder_recovery.adapters.outbound import (
    RecoveryArtifactRegistryConflict,
    RecoveryArtifactRegistryInvalid,
    RecoveryArtifactRegistryUnavailable,
    SqliteRecoveryArtifactRegistry,
    VitalServerArtifactPublisher,
)
from tirosh_vitalserver.recorder_recovery.application.ports import (
    ArtifactPublisherPort,
    RecoveryArtifactRegistryPort,
)
from tirosh_vitalserver.recorder_recovery.application.usecases import (
    RecoveryArtifactNotFound,
    publish_recovery_artifact,
    recovery_artifact_record_to_document,
)
from tirosh_vitalserver.recorder_recovery.application.usecases.recover import (
    RawArchiveVitalExportRequest,
    RawArchiveVitalRecoveryRequest,
    export_raw_archive_vital,
    export_result_to_document,
    recover_raw_archive_vital,
    recovery_result_to_document,
)
from tirosh_vitalserver.recorder_recovery.schemas.api import (
    ExportRawArchiveVitalRequest,
    RecoverRawArchiveVitalRequest,
)

DEFAULT_ARTIFACT_REGISTRY_PATH = Path(
    "/var/lib/vitalserver-recorder-ingress/recovery/recovery-artifacts.sqlite3"
)


def create_recorder_recovery_app(
    *,
    registry: RecoveryArtifactRegistryPort | None = None,
    publisher: ArtifactPublisherPort | None = None,
) -> FastAPI:
    """Build the recorder recovery FastAPI application."""

    artifact_registry = registry or SqliteRecoveryArtifactRegistry(
        Path(
            os.environ.get(
                "RECORDER_RECOVERY_ARTIFACT_REGISTRY_PATH",
                str(DEFAULT_ARTIFACT_REGISTRY_PATH),
            )
        )
    )
    app = FastAPI(title="VitalServer Recorder Recovery API", version="0.2.0")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/raw-archive/export-vital")
    def export_raw_archive_vital_endpoint(
        request: ExportRawArchiveVitalRequest,
    ) -> dict[str, Any]:
        try:
            result = export_raw_archive_vital(
                RawArchiveVitalExportRequest(
                    raw_archive_path=Path(request.raw_archive_path),
                    output_dir=Path(request.output_dir),
                    vrcode=request.vrcode,
                    start_offset=request.start_offset,
                    end_offset=request.end_offset,
                ),
                registry=artifact_registry,
            )
        except RecoveryArtifactRegistryConflict as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except (
            RecoveryArtifactRegistryInvalid,
            RecoveryArtifactRegistryUnavailable,
        ) as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except RuntimeError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc

        return export_result_to_document(result)

    @app.post("/raw-archive/recover-vital")
    def recover_raw_archive_vital_endpoint(
        request: RecoverRawArchiveVitalRequest,
    ) -> dict[str, Any]:
        try:
            result = recover_raw_archive_vital(
                RawArchiveVitalRecoveryRequest(
                    raw_archive_path=Path(request.raw_archive_path),
                    output_dir=Path(request.output_dir),
                    vitalserver_url=request.vitalserver_url,
                    endpoint=request.endpoint,
                    vrcode=request.vrcode,
                    timeout=request.timeout,
                    concurrency=request.concurrency,
                    repeat=request.repeat,
                    max_failure_rate=request.max_failure_rate,
                    skip_filename_check=request.skip_filename_check,
                    start_offset=request.start_offset,
                    end_offset=request.end_offset,
                ),
                registry=artifact_registry,
            )
        except RecoveryArtifactRegistryConflict as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except (
            RecoveryArtifactRegistryInvalid,
            RecoveryArtifactRegistryUnavailable,
        ) as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except RuntimeError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except AssertionError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc

        return recovery_result_to_document(result)

    @app.get("/artifacts")
    def list_recovery_artifacts() -> dict[str, object]:
        try:
            records = artifact_registry.list_records()
        except (
            RecoveryArtifactRegistryInvalid,
            RecoveryArtifactRegistryUnavailable,
        ) as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        return {
            "artifacts": [
                recovery_artifact_record_to_document(record) for record in records
            ]
        }

    @app.get("/artifacts/{artifact_id}")
    def get_recovery_artifact(artifact_id: str) -> dict[str, object]:
        try:
            record = artifact_registry.get_record(artifact_id)
        except (
            RecoveryArtifactRegistryInvalid,
            RecoveryArtifactRegistryUnavailable,
        ) as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        if record is None:
            raise HTTPException(status_code=404, detail="recovery artifact not found")
        return recovery_artifact_record_to_document(record)

    @app.post("/artifacts/{artifact_id}/publish")
    def publish_artifact(artifact_id: str) -> JSONResponse:
        try:
            selected_publisher = publisher or _publisher_from_environment()
            record = publish_recovery_artifact(
                artifact_id,
                registry=artifact_registry,
                publisher=selected_publisher,
            )
        except RecoveryArtifactNotFound as exc:
            raise HTTPException(status_code=404, detail=str(exc)) from exc
        except RecoveryArtifactRegistryConflict as exc:
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except (
            RecoveryArtifactRegistryInvalid,
            RecoveryArtifactRegistryUnavailable,
        ) as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except RuntimeError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        document = recovery_artifact_record_to_document(record)
        status_code = 200
        if record.failure is not None:
            status_code = 409 if record.failure.code == "filenameCollision" else 502
        return JSONResponse(status_code=status_code, content=document)

    return app


def _publisher_from_environment() -> VitalServerArtifactPublisher:
    base_url = os.environ.get("RECORDER_RECOVERY_VITALSERVER_URL")
    admin_password = os.environ.get("VITALSERVER_ADMIN_PASSWORD")
    if not base_url:
        raise RuntimeError("RECORDER_RECOVERY_VITALSERVER_URL is unavailable")
    if not admin_password:
        raise RuntimeError("VITALSERVER_ADMIN_PASSWORD is unavailable")
    return VitalServerArtifactPublisher(
        base_url=base_url,
        admin_password=admin_password,
    )


app = create_recorder_recovery_app()

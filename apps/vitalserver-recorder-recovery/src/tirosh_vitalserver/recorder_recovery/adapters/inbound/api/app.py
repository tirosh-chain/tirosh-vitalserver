"""FastAPI app for product recorder raw archive recovery."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException

from tirosh_vitalserver.recorder_recovery.application.usecases.recover import (
    RawArchiveVitalRecoveryRequest,
    recover_raw_archive_vital,
    recovery_result_to_document,
)
from tirosh_vitalserver.recorder_recovery.schemas.api import (
    RecoverRawArchiveVitalRequest,
)


def create_recorder_recovery_app() -> FastAPI:
    """Build the recorder recovery FastAPI application."""

    app = FastAPI(title="VitalServer Recorder Recovery API", version="0.1.0")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

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
                )
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except RuntimeError as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        except AssertionError as exc:
            raise HTTPException(status_code=502, detail=str(exc)) from exc

        return recovery_result_to_document(result)

    return app


app = create_recorder_recovery_app()

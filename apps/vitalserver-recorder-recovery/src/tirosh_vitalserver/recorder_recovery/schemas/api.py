"""HTTP API contracts for recorder recovery."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class RecoverySchema(BaseModel):
    """Base schema for recorder recovery API documents."""

    model_config = ConfigDict(populate_by_name=True, strict=False)


class RecoverRawArchiveVitalRequest(RecoverySchema):
    """Request body for raw archive `.vital` export/upload recovery."""

    raw_archive_path: str = Field(alias="rawArchivePath", min_length=1)
    output_dir: str = Field(alias="outputDir", min_length=1)
    vitalserver_url: str = Field(alias="vitalserverUrl", min_length=1)
    endpoint: str = "/upload"
    vrcode: str | None = None
    timeout: float = Field(default=30.0, gt=0)
    concurrency: int = Field(default=1, ge=1)
    repeat: int = Field(default=1, ge=1)
    max_failure_rate: float = Field(default=0.0, alias="maxFailureRate", ge=0.0)
    skip_filename_check: bool = Field(default=False, alias="skipFilenameCheck")

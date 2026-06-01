from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Any


class OperationStatus(StrEnum):
    SKIPPED = "skipped"
    RUNNING = "running"
    READY = "ready"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass(frozen=True)
class GuestOperationRequest:
    request_id: str
    version: str = ""


@dataclass(frozen=True)
class GuestOperationResult:
    operation: str
    request_id: str
    schema_version: int
    status: OperationStatus
    message: str
    updated_at: str
    step: str = ""
    reason_codes: tuple[str, ...] = ()
    archive: str = ""
    redis_backup_path: str = ""

    def as_json(self) -> dict[str, Any]:
        document: dict[str, Any] = {
            "operation": self.operation,
            "requestId": self.request_id,
            "schemaVersion": self.schema_version,
            "message": self.message,
            "status": self.status.value,
            "updatedAt": self.updated_at,
        }
        if self.step:
            document["step"] = self.step
        if self.reason_codes:
            document["reasonCodes"] = list(self.reason_codes)
        if self.archive:
            document["archive"] = self.archive
        if self.redis_backup_path:
            document["redisBackupPath"] = self.redis_backup_path
        return document

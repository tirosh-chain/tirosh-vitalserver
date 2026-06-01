from __future__ import annotations

from tirosh_guest_tools.domain.operations import (
    GuestOperationResult,
    OperationStatus,
)


def test_guest_operation_result_keeps_missing_fields_absent() -> None:
    result = GuestOperationResult(
        operation="activate-update",
        request_id="req-1",
        schema_version=2,
        status=OperationStatus.RUNNING,
        message="running",
        updated_at="2026-06-01T00:00:00Z",
    )

    document = result.as_json()

    assert document["operation"] == "activate-update"
    assert document["status"] == "running"
    assert "reasonCodes" not in document
    assert "redisBackupPath" not in document


def test_guest_operation_result_reports_explicit_failure_details() -> None:
    result = GuestOperationResult(
        operation="prepare-update-shutdown",
        request_id="req-2",
        schema_version=1,
        status=OperationStatus.FAILED,
        message="failed",
        updated_at="2026-06-01T00:00:00Z",
        step="failed",
        reason_codes=("guest-update-shutdown-failed",),
        redis_backup_path="/mnt/tirosh/backups/redis/redis.tar.gz",
    )

    document = result.as_json()

    assert document["status"] == "failed"
    assert document["step"] == "failed"
    assert document["reasonCodes"] == ["guest-update-shutdown-failed"]
    assert document["redisBackupPath"] == "/mnt/tirosh/backups/redis/redis.tar.gz"

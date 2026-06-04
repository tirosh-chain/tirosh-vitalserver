from __future__ import annotations

from tirosh_guest_tools.domain.operations import (
    GuestOperationResult,
    OperationName,
    OperationStatus,
    ShutdownPhase,
)


def test_guest_operation_result_keeps_missing_fields_absent() -> None:
    result = GuestOperationResult(
        operation=OperationName.ACTIVATE_UPDATE,
        request_id="req-1",
        schema_version=2,
        status=OperationStatus.RUNNING,
        message="running",
        updated_at="2026-06-01T00:00:00Z",
    )

    document = result.as_json()

    assert document["operation"] == OperationName.ACTIVATE_UPDATE.value
    assert document["status"] == OperationStatus.RUNNING.value
    assert "reasonCodes" not in document
    assert "redisBackupPath" not in document


def test_guest_operation_result_reports_explicit_failure_details() -> None:
    result = GuestOperationResult(
        operation=OperationName.PREPARE_UPDATE_SHUTDOWN,
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

    assert document["status"] == OperationStatus.FAILED.value
    assert document["step"] == OperationStatus.FAILED.value
    assert document["reasonCodes"] == ["guest-update-shutdown-failed"]
    assert document["redisBackupPath"] == "/mnt/tirosh/backups/redis/redis.tar.gz"


def test_guest_operation_result_reports_explicit_shutdown_phase() -> None:
    result = GuestOperationResult(
        operation=OperationName.PREPARE_UPDATE_SHUTDOWN,
        request_id="req-3",
        schema_version=1,
        status=OperationStatus.READY,
        message="poweroff requested",
        updated_at="2026-06-01T00:00:00Z",
        shutdown_phase=ShutdownPhase.POWEROFF_REQUESTED,
    )

    document = result.as_json()

    assert document["shutdownPhase"] == ShutdownPhase.POWEROFF_REQUESTED.value

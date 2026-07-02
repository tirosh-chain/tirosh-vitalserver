from __future__ import annotations

import subprocess
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

from tirosh_guest_tools.contracts import RootfsSmokeStatus
from tirosh_guest_tools.infrastructure.common import utc_now

RUNTIME_BOOT_SMOKE_SCHEMA_VERSION = 1
RUNTIME_BOOT_SMOKE_MANIFEST = "runtime-boot-smoke-manifest.json"


@dataclass(frozen=True)
class RuntimeBootSmokeContext:
    runtime_dir: Path
    deploy_dir: Path
    manifest_path: Path
    run_id: str
    max_runtime_state_age_seconds: int
    compose_ready_timeout_seconds: float
    dev_build: bool


@dataclass(frozen=True)
class RuntimeBootSmokeOperations:
    mount_runtime_share: Callable[[], None]
    read_json: Callable[[Path], dict[str, Any]]
    write_json: Callable[[Path, dict[str, Any]], None]
    run: Callable[..., subprocess.CompletedProcess[str]]
    http_status: Callable[[str, float], int]
    http_json: Callable[
        [str, str, float, dict[str, Any] | None],
        dict[str, Any],
    ]
    now: Callable[[], datetime]
    sleep: Callable[[float], None]


@dataclass(frozen=True)
class RuntimeBootSmokeStage:
    name: str
    status: RootfsSmokeStatus
    started_at: str
    completed_at: str
    message: str
    details: dict[str, Any] = field(default_factory=dict)

    def as_json(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status.value,
            "startedAt": self.started_at,
            "completedAt": self.completed_at,
            "message": self.message,
            "details": self.details,
        }


@dataclass
class RuntimeBootSmokeRun:
    context: RuntimeBootSmokeContext
    operations: RuntimeBootSmokeOperations
    created_at: str = field(default_factory=utc_now)
    stages: list[RuntimeBootSmokeStage] = field(default_factory=list)

    def write_manifest(self) -> None:
        self.operations.write_json(self.context.manifest_path, self.as_json())

    def as_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": RUNTIME_BOOT_SMOKE_SCHEMA_VERSION,
            "runId": self.context.run_id,
            "createdAt": self.created_at,
            "updatedAt": utc_now(),
            "status": overall_status(self.stages),
            "stages": [stage.as_json() for stage in self.stages],
        }


def overall_status(stages: Sequence[RuntimeBootSmokeStage]) -> str:
    if not stages:
        return RootfsSmokeStatus.NOT_RUN.value
    if any(stage.status == RootfsSmokeStatus.FAILED for stage in stages):
        return RootfsSmokeStatus.FAILED.value
    if all(stage.status == RootfsSmokeStatus.PASSED for stage in stages):
        return RootfsSmokeStatus.PASSED.value
    return RootfsSmokeStatus.RUNNING.value

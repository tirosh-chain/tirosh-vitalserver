from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass
class PrepareUpdateShutdownContext:
    request_id: str
    version: str
    redis_backup_path: str = ""


@dataclass(frozen=True)
class RedisBackupOutcome:
    archive: Path


@dataclass(frozen=True)
class RedisRestoreOutcome:
    restored_archive: Path

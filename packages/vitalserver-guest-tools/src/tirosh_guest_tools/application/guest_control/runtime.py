from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4


class SystemClock:
    def now(self) -> datetime:
        return datetime.now(UTC)


class UUIDOperationIdFactory:
    def new_operation_id(self, *, service: str, command: str) -> str:
        return f"op_{service}_{command}_{uuid4().hex}"

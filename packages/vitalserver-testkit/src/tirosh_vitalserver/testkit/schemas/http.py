"""Pydantic schemas for VitalServer HTTP responses."""

from __future__ import annotations

from tirosh_vitalserver.testkit.schemas.base import ExternalSchema


class HttpResponse(ExternalSchema):
    """HTTP response returned from VitalServer adapters."""

    status_code: int
    headers: dict[str, str]
    body: bytes
    elapsed_seconds: float

    @property
    def ok(self) -> bool:
        return 200 <= self.status_code < 300

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")

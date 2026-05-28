"""Pydantic schemas for data entering the testkit from external boundaries."""

from tirosh_vitalserver.testkit.schemas.base import ExternalSchema
from tirosh_vitalserver.testkit.schemas.http import HttpResponse
from tirosh_vitalserver.testkit.schemas.payloads import (
    RealtimeMessageDocument,
    RecorderPayloadDocument,
)
from tirosh_vitalserver.testkit.schemas.testkit_api import (
    CreateBedsRequest,
    DeleteVirtualRecorderRequest,
    RestartVirtualRecorderSessionRequest,
    StartVirtualRecordersRequest,
)

__all__ = [
    "CreateBedsRequest",
    "DeleteVirtualRecorderRequest",
    "ExternalSchema",
    "HttpResponse",
    "RealtimeMessageDocument",
    "RecorderPayloadDocument",
    "RestartVirtualRecorderSessionRequest",
    "StartVirtualRecordersRequest",
]

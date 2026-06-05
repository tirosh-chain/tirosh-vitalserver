"""Pydantic schemas for data entering the testkit from external boundaries."""

from tirosh_vitalserver.testkit.schemas.base import ExternalSchema
from tirosh_vitalserver.testkit.schemas.http import HttpResponse
from tirosh_vitalserver.testkit.schemas.payloads import (
    RealtimeMessageDocument,
    RecorderPayloadDocument,
)
from tirosh_vitalserver.testkit.schemas.testkit_api import (
    CreateBedsRequest,
    DeleteBedsRequest,
    DeleteVirtualRecorderRequest,
    RestartVirtualRecorderSessionRequest,
    StartVirtualRecordersRequest,
)

__all__ = [
    "CreateBedsRequest",
    "DeleteBedsRequest",
    "DeleteVirtualRecorderRequest",
    "ExternalSchema",
    "HttpResponse",
    "RealtimeMessageDocument",
    "RecorderPayloadDocument",
    "RestartVirtualRecorderSessionRequest",
    "StartVirtualRecordersRequest",
]

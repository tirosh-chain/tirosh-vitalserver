from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Literal, Protocol
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

LabArchiveFinalizationReason = Literal[
    "lab_session_finished",
]


@dataclass(frozen=True)
class LabArchiveFinalizationReceipt:
    state: Literal["accepted"]
    request_ids: tuple[str, ...]

    def as_json(self) -> dict[str, object]:
        return {"state": self.state, "requestIds": list(self.request_ids)}


LabArchiveFinalizationProgressState = Literal[
    "queued",
    "processing",
    "retrying",
    "uploaded",
    "failed",
    "partial",
    "missing",
]


@dataclass(frozen=True)
class LabArchiveFinalizationProgress:
    """Read-only recorder-ingress projection for one accepted finish request."""

    state: LabArchiveFinalizationProgressState
    request_ids: tuple[str, ...]
    requests: tuple[dict[str, object], ...]
    updated_at: str | None

    def as_json(self) -> dict[str, object]:
        return {
            "state": self.state,
            "updatedAt": self.updated_at,
            "readError": None,
        }


class LabRecorderArchiveFinalizer(Protocol):
    def request_finalization(
        self,
        *,
        vrcodes: tuple[str, ...],
        reason: LabArchiveFinalizationReason,
    ) -> LabArchiveFinalizationReceipt:
        """Request durable recorder-ingress archive finalization."""

    def read_finalization(
        self,
        *,
        request_ids: tuple[str, ...],
    ) -> LabArchiveFinalizationProgress:
        """Read recorder-ingress-owned progress for accepted request IDs."""


class LabArchiveFinalizationError(RuntimeError):
    pass


class RecorderIngressArchiveFinalizer:
    def __init__(self, *, url: str, timeout_seconds: float = 10.0) -> None:
        if not url:
            raise ValueError("recorder ingress archive finalization URL is required")
        if not url.endswith("/finalize"):
            raise ValueError(
                "recorder ingress archive finalization URL must end with /finalize"
            )
        self.url = url
        self.timeout_seconds = timeout_seconds

    def request_finalization(
        self,
        *,
        vrcodes: tuple[str, ...],
        reason: LabArchiveFinalizationReason,
    ) -> LabArchiveFinalizationReceipt:
        if not vrcodes:
            raise LabArchiveFinalizationError(
                "recorder archive finalization requires at least one vrcode"
            )
        body = json.dumps(
            {"vrcodes": list(vrcodes), "reason": reason},
            separators=(",", ":"),
        ).encode("utf-8")
        request = Request(
            self.url,
            data=body,
            method="POST",
            headers={"Content-Type": "application/json"},
        )
        try:
            with urlopen(request, timeout=self.timeout_seconds) as response:
                document = json.loads(response.read().decode("utf-8"))
        except HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise LabArchiveFinalizationError(
                "recorder ingress archive finalization rejected "
                f"status={error.code} body={detail}"
            ) from error
        except (URLError, TimeoutError, json.JSONDecodeError) as error:
            raise LabArchiveFinalizationError(
                f"recorder ingress archive finalization failed: {error}"
            ) from error
        if not isinstance(document, dict) or document.get("state") != "accepted":
            raise LabArchiveFinalizationError(
                "recorder ingress archive finalization response is invalid"
            )
        request_ids = document.get("requestIds")
        if not isinstance(request_ids, list) or not request_ids or not all(
            isinstance(value, str) and value for value in request_ids
        ):
            raise LabArchiveFinalizationError(
                "recorder ingress archive finalization response is missing requestIds"
            )
        return LabArchiveFinalizationReceipt(
            state="accepted",
            request_ids=tuple(request_ids),
        )

    def read_finalization(
        self,
        *,
        request_ids: tuple[str, ...],
    ) -> LabArchiveFinalizationProgress:
        if not request_ids or any(not request_id for request_id in request_ids):
            raise LabArchiveFinalizationError(
                "recorder archive finalization status requires requestIds"
            )
        status_url = self.url.removesuffix("/finalize") + "/finalizations"
        request = Request(
            f"{status_url}?{urlencode([('requestId', request_id) for request_id in request_ids])}",
            method="GET",
        )
        try:
            with urlopen(request, timeout=self.timeout_seconds) as response:
                document = json.loads(response.read().decode("utf-8"))
        except HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            raise LabArchiveFinalizationError(
                "recorder ingress archive finalization status rejected "
                f"status={error.code} body={detail}"
            ) from error
        except (URLError, TimeoutError, json.JSONDecodeError) as error:
            raise LabArchiveFinalizationError(
                f"recorder ingress archive finalization status failed: {error}"
            ) from error
        return _progress_from_document(document, request_ids=request_ids)


def _progress_from_document(
    document: object,
    *,
    request_ids: tuple[str, ...],
) -> LabArchiveFinalizationProgress:
    if not isinstance(document, dict) or document.get("state") != "loaded":
        raise LabArchiveFinalizationError(
            "recorder ingress archive finalization status response is invalid"
        )
    finalization = document.get("finalization")
    if not isinstance(finalization, dict):
        raise LabArchiveFinalizationError(
            "recorder ingress archive finalization status is missing finalization"
        )
    state = finalization.get("state")
    if state not in {
        "queued",
        "processing",
        "retrying",
        "uploaded",
        "failed",
        "partial",
        "missing",
    }:
        raise LabArchiveFinalizationError(
            "recorder ingress archive finalization status has invalid state"
        )
    reported_request_ids = _request_ids(finalization.get("requestIds"))
    if reported_request_ids != request_ids:
        raise LabArchiveFinalizationError(
            "recorder ingress archive finalization status requestIds do not match"
        )
    requests = finalization.get("requests")
    if not isinstance(requests, list) or not all(
        isinstance(item, dict)
        and isinstance(item.get("requestId"), str)
        and item.get("requestId") in request_ids
        and item.get("state")
        in {"queued", "processing", "retrying", "uploaded", "failed", "missing"}
        for item in requests
    ):
        raise LabArchiveFinalizationError(
            "recorder ingress archive finalization status requests are invalid"
        )
    if {item["requestId"] for item in requests} != set(request_ids):
        raise LabArchiveFinalizationError(
            "recorder ingress archive finalization status requests are incomplete"
        )
    updated_at = finalization.get("updatedAt")
    if updated_at is not None and not isinstance(updated_at, str):
        raise LabArchiveFinalizationError(
            "recorder ingress archive finalization status updatedAt is invalid"
        )
    return LabArchiveFinalizationProgress(
        state=state,
        request_ids=reported_request_ids,
        requests=tuple(dict(item) for item in requests),
        updated_at=updated_at,
    )


def _request_ids(value: object) -> tuple[str, ...]:
    if not isinstance(value, list) or not value or not all(
        isinstance(item, str) and item for item in value
    ):
        raise LabArchiveFinalizationError(
            "recorder ingress archive finalization status requestIds are invalid"
        )
    return tuple(value)

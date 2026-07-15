from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Literal, Protocol
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

LabArchiveFinalizationReason = Literal[
    "lab_session_stopped",
    "lab_recorder_stopped",
]


@dataclass(frozen=True)
class LabArchiveFinalizationReceipt:
    state: Literal["accepted"]
    request_ids: tuple[str, ...]

    def as_json(self) -> dict[str, object]:
        return {"state": self.state, "requestIds": list(self.request_ids)}


class LabRecorderArchiveFinalizer(Protocol):
    def request_finalization(
        self,
        *,
        vrcodes: tuple[str, ...],
        reason: LabArchiveFinalizationReason,
    ) -> LabArchiveFinalizationReceipt:
        """Request durable recorder-ingress archive finalization."""


class LabArchiveFinalizationError(RuntimeError):
    pass


class RecorderIngressArchiveFinalizer:
    def __init__(self, *, url: str, timeout_seconds: float = 10.0) -> None:
        if not url:
            raise ValueError("recorder ingress archive finalization URL is required")
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

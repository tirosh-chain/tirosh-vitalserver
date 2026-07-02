from __future__ import annotations

import json
import os
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from tirosh_guest_tools.domain.guest_control.models import (
    RecorderIngressDependencyError,
)

DEFAULT_RECORDER_INGRESS_STATUS_URL = (
    "http://127.0.0.1:18083/recorder-ingress/status"
)
RECORDER_INGRESS_STATUS_URL_ENV = "TIROSH_RECORDER_INGRESS_STATUS_URL"


class RecorderIngressStatusServiceAdapter:
    def __init__(
        self,
        *,
        status_url: str | None = None,
        timeout_seconds: float = 5.0,
    ) -> None:
        self._status_url = status_url or os.environ.get(
            RECORDER_INGRESS_STATUS_URL_ENV,
            DEFAULT_RECORDER_INGRESS_STATUS_URL,
        )
        self._timeout_seconds = timeout_seconds

    def status(self) -> dict[str, Any]:
        request = Request(
            self._status_url,
            method="GET",
            headers={"Accept": "application/json"},
        )
        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                http_status = str(response.status)
                data = response.read()
        except HTTPError as error:
            raise RecorderIngressDependencyError(
                f"Recorder ingress status request failed: status={error.code}",
                kind="recorder-ingress-http-error",
            ) from error
        except URLError as error:
            raise RecorderIngressDependencyError(
                f"Recorder ingress status is unavailable: {error.reason}",
                kind="recorder-ingress-unavailable",
            ) from error
        except TimeoutError as error:
            raise RecorderIngressDependencyError(
                "Recorder ingress status request timed out.",
                kind="recorder-ingress-timeout",
            ) from error

        try:
            document = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RecorderIngressDependencyError(
                f"Recorder ingress status returned invalid JSON: {error}",
                kind="recorder-ingress-contract-invalid",
            ) from error

        if not isinstance(document, dict):
            raise RecorderIngressDependencyError(
                "Recorder ingress status returned a non-object JSON document.",
                kind="recorder-ingress-contract-invalid",
            )

        return {
            "readState": "loaded",
            "httpStatus": http_status,
            "document": document,
            "readError": None,
        }

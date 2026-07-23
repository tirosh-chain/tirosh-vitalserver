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
DEFAULT_RECORDER_INGRESS_NATIVE_UPLOADS_URL = (
    "http://127.0.0.1:18083/recorder-ingress/vital-files/uploads"
)
RECORDER_INGRESS_NATIVE_UPLOADS_URL_ENV = (
    "TIROSH_RECORDER_INGRESS_NATIVE_UPLOADS_URL"
)


class RecorderIngressStatusServiceAdapter:
    def __init__(
        self,
        *,
        status_url: str | None = None,
        native_uploads_url: str | None = None,
        timeout_seconds: float = 5.0,
    ) -> None:
        self._status_url = status_url or os.environ.get(
            RECORDER_INGRESS_STATUS_URL_ENV,
            DEFAULT_RECORDER_INGRESS_STATUS_URL,
        )
        self._native_uploads_url = native_uploads_url or os.environ.get(
            RECORDER_INGRESS_NATIVE_UPLOADS_URL_ENV,
            DEFAULT_RECORDER_INGRESS_NATIVE_UPLOADS_URL,
        )
        self._timeout_seconds = timeout_seconds

    def status(self) -> dict[str, Any]:
        http_status, document = self._read_document(
            self._status_url,
            operation="status",
        )
        return {
            "readState": "loaded",
            "httpStatus": http_status,
            "document": document,
            "readError": None,
        }

    def native_vital_uploads(self) -> dict[str, Any]:
        _http_status, document = self._read_document(
            self._native_uploads_url,
            operation="native vital uploads",
        )
        return document

    def _read_document(
        self,
        url: str,
        *,
        operation: str,
    ) -> tuple[str, dict[str, Any]]:
        request = Request(
            url,
            method="GET",
            headers={"Accept": "application/json"},
        )
        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                http_status = str(response.status)
                data = response.read()
        except HTTPError as error:
            raise RecorderIngressDependencyError(
                f"Recorder ingress {operation} request failed: status={error.code}",
                kind="recorder-ingress-http-error",
            ) from error
        except URLError as error:
            raise RecorderIngressDependencyError(
                f"Recorder ingress {operation} is unavailable: {error.reason}",
                kind="recorder-ingress-unavailable",
            ) from error
        except TimeoutError as error:
            raise RecorderIngressDependencyError(
                f"Recorder ingress {operation} request timed out.",
                kind="recorder-ingress-timeout",
            ) from error

        try:
            document = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RecorderIngressDependencyError(
                f"Recorder ingress {operation} returned invalid JSON: {error}",
                kind="recorder-ingress-contract-invalid",
            ) from error

        if not isinstance(document, dict):
            raise RecorderIngressDependencyError(
                f"Recorder ingress {operation} returned a non-object JSON document.",
                kind="recorder-ingress-contract-invalid",
            )

        return http_status, document

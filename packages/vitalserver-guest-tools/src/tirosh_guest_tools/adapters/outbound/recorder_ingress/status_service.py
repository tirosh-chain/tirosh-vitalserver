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
DEFAULT_RECORDER_INGRESS_OBSERVABILITY_URL = (
    "http://127.0.0.1:18083/runtime/vitaldb/recorders"
)
RECORDER_INGRESS_OBSERVABILITY_URL_ENV = (
    "TIROSH_RECORDER_INGRESS_OBSERVABILITY_URL"
)


class RecorderIngressStatusServiceAdapter:
    def __init__(
        self,
        *,
        status_url: str | None = None,
        native_uploads_url: str | None = None,
        observability_url: str | None = None,
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
        self._observability_url = observability_url or os.environ.get(
            RECORDER_INGRESS_OBSERVABILITY_URL_ENV,
            DEFAULT_RECORDER_INGRESS_OBSERVABILITY_URL,
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

    def recorder_observability(self) -> dict[str, Any]:
        _http_status, document = self._read_document(
            self._observability_url,
            operation="Recorder observability list",
        )
        return _validated_observability_list(document)

    def recorder_observability_detail(self, vrcode: str) -> dict[str, Any]:
        from urllib.parse import quote

        url = f"{self._observability_url}/{quote(vrcode, safe='')}/observability"
        try:
            _http_status, document = self._read_document(
                url,
                operation=f"Recorder observability detail for {vrcode}",
            )
            return _validated_observability_detail(document, vrcode)
        except RecorderIngressDependencyError as error:
            if error.kind == "recorder-ingress-not-found":
                return _empty_observability(
                    state="notReported",
                    vrcode=vrcode,
                    report_state="notEvaluated",
                    read_error=None,
                )
            raise

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
            if error.code == 404:
                raise RecorderIngressDependencyError(
                    f"Recorder ingress {operation} has no matching resource.",
                    kind="recorder-ingress-not-found",
                ) from error
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


def _validated_observability_list(document: dict[str, Any]) -> dict[str, Any]:
    if document.get("state") != "loaded" or not isinstance(
        document.get("recorders"), list
    ):
        raise _observability_contract_error("list state or recorders is invalid")
    for summary in document["recorders"]:
        _validate_observability_summary(summary)
    return document


def _validated_observability_detail(
    document: dict[str, Any],
    vrcode: str,
) -> dict[str, Any]:
    if document.get("state") != "loaded" or document.get("vrcode") != vrcode:
        raise _observability_contract_error("detail state or VRCODE is invalid")
    _validate_observability_summary(document)
    if "resources" not in document or (
        document["resources"] is not None
        and not isinstance(document["resources"], dict)
    ):
        raise _observability_contract_error("detail resources is invalid")
    return document


def _validate_observability_summary(summary: object) -> None:
    if not isinstance(summary, dict) or not isinstance(summary.get("vrcode"), str):
        raise _observability_contract_error("summary VRCODE is invalid")
    if summary.get("supportState") not in {"supported", "unsupported", "unknown"}:
        raise _observability_contract_error("summary supportState is invalid")
    if summary.get("reportState") not in {
        "notEvaluated",
        "awaitingFirstReport",
        "current",
        "stale",
        "missing",
        "readFailed",
    }:
        raise _observability_contract_error("summary reportState is invalid")
    nullable_strings = (
        "supportSource",
        "profileState",
        "collectionState",
        "latestObservationReceivedAt",
        "lastBootStartedAt",
        "expectedSince",
        "recorderVersion",
        "producerVersion",
        "protocolVersion",
    )
    for field in nullable_strings:
        if field not in summary or (
            summary[field] is not None and not isinstance(summary[field], str)
        ):
            raise _observability_contract_error(f"summary {field} is invalid")
    read_issue_count = summary.get("readIssueCount")
    if (
        not isinstance(read_issue_count, int)
        or isinstance(read_issue_count, bool)
        or read_issue_count < 0
    ):
        raise _observability_contract_error("summary readIssueCount is invalid")


def _empty_observability(
    *,
    state: str,
    vrcode: str,
    report_state: str,
    read_error: str | None,
) -> dict[str, Any]:
    return {
        "state": state,
        "vrcode": vrcode,
        "supportState": "unknown",
        "supportSource": None,
        "reportState": report_state,
        "profileState": None,
        "collectionState": None,
        "latestObservationReceivedAt": None,
        "lastBootStartedAt": None,
        "readIssueCount": None,
        "expectedSince": None,
        "recorderVersion": None,
        "producerVersion": None,
        "protocolVersion": None,
        "readError": read_error,
    }


def _observability_contract_error(detail: str) -> RecorderIngressDependencyError:
    return RecorderIngressDependencyError(
        f"Recorder ingress observability contract is invalid: {detail}.",
        kind="recorder-ingress-contract-invalid",
    )

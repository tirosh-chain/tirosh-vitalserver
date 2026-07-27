from __future__ import annotations

import json
import os
from pathlib import Path
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
DEFAULT_RECORDER_INGRESS_EXPECTATION_COMMAND_URL = (
    "http://127.0.0.1:18083/internal/recorder-observability/expectations"
)
RECORDER_INGRESS_EXPECTATION_COMMAND_URL_ENV = (
    "TIROSH_RECORDER_INGRESS_EXPECTATION_COMMAND_URL"
)
DEFAULT_RECORDER_INGRESS_EXPECTATION_CONTROL_TOKEN_FILE = Path(
    "/mnt/runtime/recorder-ingress-expectation-control-token"
)


class RecorderIngressStatusServiceAdapter:
    def __init__(
        self,
        *,
        status_url: str | None = None,
        native_uploads_url: str | None = None,
        observability_url: str | None = None,
        expectation_command_url: str | None = None,
        expectation_control_token: str | None = None,
        expectation_control_token_file: Path = (
            DEFAULT_RECORDER_INGRESS_EXPECTATION_CONTROL_TOKEN_FILE
        ),
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
        self._expectation_command_url = expectation_command_url or os.environ.get(
            RECORDER_INGRESS_EXPECTATION_COMMAND_URL_ENV,
            DEFAULT_RECORDER_INGRESS_EXPECTATION_COMMAND_URL,
        )
        self._expectation_control_token = expectation_control_token
        self._expectation_control_token_file = expectation_control_token_file
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
                return _empty_observability_detail(
                    state="notReported",
                    vrcode=vrcode,
                    read_error=None,
                )
            raise

    def recorder_observability_timeline(
        self,
        vrcode: str,
        query: dict[str, str],
    ) -> dict[str, Any]:
        return self._recorder_observability_history(
            vrcode,
            "timeline",
            query,
        )

    def recorder_observability_incidents(
        self,
        vrcode: str,
        query: dict[str, str],
    ) -> dict[str, Any]:
        return self._recorder_observability_history(
            vrcode,
            "incidents",
            query,
        )

    def _recorder_observability_history(
        self,
        vrcode: str,
        resource: str,
        query: dict[str, str],
    ) -> dict[str, Any]:
        from urllib.parse import quote, urlencode

        url = (
            f"{self._observability_url}/{quote(vrcode, safe='')}"
            f"/observability/{resource}?{urlencode(query)}"
        )
        _http_status, document = self._read_document(
            url,
            operation=f"Recorder observability {resource} for {vrcode}",
        )
        if (
            document.get("vrcode") != vrcode
            or document.get("timeBasis") != "receivedAt"
            or document.get("readError") is not None
        ):
            raise _observability_contract_error(
                f"{resource} identity or read state is invalid"
            )
        if resource == "timeline":
            state = document.get("state")
            support_state = document.get("supportState")
            buckets = document.get("buckets")
            if (
                state not in {"loaded", "notReported", "unsupported"}
                or support_state not in {"supported", "unsupported", "unknown"}
                or not isinstance(buckets, list)
                or (state == "loaded" and not buckets)
                or (state == "unsupported" and support_state != "unsupported")
            ):
                raise _observability_contract_error("timeline is invalid")
        elif document.get("state") != "loaded" or not isinstance(
            document.get("incidents"), list
        ):
            raise _observability_contract_error("incidents are invalid")
        return document

    def apply_recorder_observability_expectation(
        self,
        command: dict[str, Any],
    ) -> dict[str, Any]:
        token = self._load_expectation_control_token()
        request = Request(
            self._expectation_command_url,
            data=json.dumps(
                command,
                ensure_ascii=False,
                separators=(",", ":"),
            ).encode("utf-8"),
            method="POST",
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                data = response.read()
        except HTTPError as error:
            if error.code in {409, 422}:
                return _validated_expectation_receipt(
                    _decoded_object(
                        error.read(),
                        operation="Recorder expectation command",
                    )
                )
            kind = (
                "recorder-ingress-control-unauthorized"
                if error.code == 401
                else "recorder-ingress-control-unavailable"
            )
            raise RecorderIngressDependencyError(
                "Recorder ingress expectation command failed: "
                f"status={error.code}",
                kind=kind,
            ) from error
        except URLError as error:
            raise RecorderIngressDependencyError(
                "Recorder ingress expectation command is unavailable: "
                f"{error.reason}",
                kind="recorder-ingress-unavailable",
            ) from error
        except TimeoutError as error:
            raise RecorderIngressDependencyError(
                "Recorder ingress expectation command timed out.",
                kind="recorder-ingress-timeout",
            ) from error
        return _validated_expectation_receipt(
            _decoded_object(data, operation="Recorder expectation command")
        )

    def _load_expectation_control_token(self) -> str:
        if self._expectation_control_token is not None:
            token = self._expectation_control_token.strip()
            if token:
                return token
            raise RecorderIngressDependencyError(
                "Recorder expectation control credential is empty.",
                kind="recorder-ingress-control-credential-unavailable",
            )
        try:
            token = self._expectation_control_token_file.read_text(
                encoding="utf-8"
            ).strip()
        except OSError as error:
            raise RecorderIngressDependencyError(
                "Recorder expectation control credential could not be read: "
                f"{self._expectation_control_token_file}: {error}",
                kind="recorder-ingress-control-credential-unavailable",
            ) from error
        if not token:
            raise RecorderIngressDependencyError(
                "Recorder expectation control credential file is empty: "
                f"{self._expectation_control_token_file}",
                kind="recorder-ingress-control-credential-unavailable",
            )
        return token

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


def _decoded_object(data: bytes, *, operation: str) -> dict[str, Any]:
    try:
        document = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RecorderIngressDependencyError(
            f"{operation} returned invalid JSON: {error}",
            kind="recorder-ingress-contract-invalid",
        ) from error
    if not isinstance(document, dict):
        raise RecorderIngressDependencyError(
            f"{operation} returned a non-object JSON document.",
            kind="recorder-ingress-contract-invalid",
        )
    return document


def _validated_expectation_receipt(
    document: dict[str, Any],
) -> dict[str, Any]:
    state = document.get("state")
    if state not in {
        "accepted",
        "idempotent",
        "revisionConflict",
        "rejected",
    }:
        raise _observability_contract_error(
            "expectation receipt state is invalid"
        )
    if not isinstance(document.get("commandId"), str):
        raise _observability_contract_error(
            "expectation receipt commandId is invalid"
        )
    if not isinstance(document.get("vrcode"), str):
        raise _observability_contract_error(
            "expectation receipt VRCODE is invalid"
        )
    if not isinstance(document.get("currentRevision"), int):
        raise _observability_contract_error(
            "expectation receipt currentRevision is invalid"
        )
    if state in {"accepted", "idempotent"}:
        if not isinstance(document.get("eventId"), str) or (
            document.get("failure") is not None
        ):
            raise _observability_contract_error(
                "accepted expectation receipt evidence is invalid"
            )
    elif document.get("eventId") is not None or not isinstance(
        document.get("failure"), str
    ):
        raise _observability_contract_error(
            "failed expectation receipt evidence is invalid"
        )
    return document


def _validated_observability_detail(
    document: dict[str, Any],
    vrcode: str,
) -> dict[str, Any]:
    if document.get("state") != "loaded" or document.get("vrcode") != vrcode:
        raise _observability_contract_error("detail state or VRCODE is invalid")
    support = document.get("support")
    report = document.get("report")
    profile = document.get("profile")
    boot = document.get("boot")
    evidence_health = document.get("evidenceHealth")
    incident_state = document.get("incidentState")
    operational_health = document.get("operationalHealth")
    readings = document.get("readings")
    read_issues = document.get("readIssues")
    if not isinstance(support, dict) or support.get("state") not in {
        "supported",
        "unsupported",
        "unknown",
    }:
        raise _observability_contract_error("detail support is invalid")
    if not isinstance(report, dict) or report.get("state") not in {
        "notEvaluated",
        "awaitingFirstReport",
        "current",
        "stale",
        "missing",
        "readFailed",
    }:
        raise _observability_contract_error("detail report is invalid")
    if not isinstance(profile, dict) or profile.get("state") not in {
        "associated",
        "unassociated",
        "missing",
        "invalid",
    }:
        raise _observability_contract_error("detail profile is invalid")
    if (
        not isinstance(boot, dict)
        or boot.get("state")
        not in {"notReported", "started", "shutdownClean", "nonOrderable"}
        or boot.get("orderingState")
        not in {"ordered", "nonOrderable", "unknown"}
        or not {
            "bootId",
            "startedAt",
            "cleanShutdownAt",
        }.issubset(boot)
    ):
        raise _observability_contract_error("detail boot is invalid")
    _validate_evidence_health(evidence_health)
    _validate_incident_state(incident_state)
    _validate_operational_health(operational_health)
    if not isinstance(readings, dict):
        raise _observability_contract_error("detail readings is invalid")
    required_readings = {
        "temperatureCelsius",
        "memoryAvailableBytes",
        "memoryTotalBytes",
        "rootUsedPercent",
        "dataUsedPercent",
        "recorderActiveState",
        "publisherActiveState",
        "publisherBufferBytes",
        "publisherBufferLimitBytes",
        "networkInterfaces",
    }
    if not required_readings.issubset(readings):
        raise _observability_contract_error("detail readings are incomplete")
    for name in required_readings - {"networkInterfaces"}:
        _validate_observability_reading(readings[name], name)
    if not isinstance(readings["networkInterfaces"], list):
        raise _observability_contract_error(
            "detail networkInterfaces is invalid"
        )
    for index, network_interface in enumerate(readings["networkInterfaces"]):
        if (
            not isinstance(network_interface, dict)
            or not isinstance(network_interface.get("name"), str)
        ):
            raise _observability_contract_error(
                f"detail networkInterfaces[{index}] is invalid"
            )
        for field in ("operState", "carrier", "rxErrors", "txErrors"):
            _validate_observability_reading(
                network_interface.get(field),
                f"networkInterfaces[{index}].{field}",
            )
    if not isinstance(read_issues, list) or document.get("readError") is not None:
        raise _observability_contract_error("detail read result is invalid")
    if "resources" in document:
        raise _observability_contract_error("detail exposes raw resources")
    return document


def _validate_observability_reading(value: object, name: str) -> None:
    if not isinstance(value, dict) or value.get("state") not in {
        "ok",
        "missing",
        "invalid",
        "failed",
        "unsupported",
    }:
        raise _observability_contract_error(f"detail reading {name} is invalid")
    if not {"value", "detail", "observedAt"}.issubset(value):
        raise _observability_contract_error(
            f"detail reading {name} is incomplete"
        )


def _validate_operational_health(value: object) -> None:
    if (
        not isinstance(value, dict)
        or value.get("state") not in {"healthy", "warning", "critical", "unknown"}
        or not isinstance(value.get("issues"), list)
        or value.get("issueCount") != len(value["issues"])
        or (
            value.get("evaluatedAt") is not None
            and not isinstance(value.get("evaluatedAt"), str)
        )
    ):
        raise _observability_contract_error("operational health is invalid")
    for index, issue in enumerate(value["issues"]):
        if (
            not isinstance(issue, dict)
            or issue.get("severity") not in {"warning", "critical"}
            or not all(
                isinstance(issue.get(field), str)
                for field in ("code", "category", "title", "detail", "field")
            )
        ):
            raise _observability_contract_error(
                f"operational health issue {index} is invalid"
            )


def _validate_evidence_health(value: object) -> None:
    if not isinstance(value, dict) or value.get("state") not in {
        "notReported",
        "healthy",
        "degraded",
        "failed",
        "stale",
        "unsupported",
        "invalid",
    }:
        raise _observability_contract_error("evidence health is invalid")
    checked_at = value.get("checkedAt")
    check_count = value.get("checkCount")
    detail = value.get("detail")
    if (
        ("checkedAt" not in value or checked_at is not None)
        and not isinstance(checked_at, str)
    ) or (
        not isinstance(check_count, int)
        or isinstance(check_count, bool)
        or check_count < 0
    ) or (
        ("detail" not in value or detail is not None)
        and not isinstance(detail, str)
    ):
        raise _observability_contract_error("evidence health is invalid")


def _validate_incident_state(value: object) -> None:
    if not isinstance(value, dict) or value.get("state") not in {
        "notReported",
        "reported",
        "invalid",
    }:
        raise _observability_contract_error("incident state is invalid")
    nullable_strings = {
        "policyVersion": None,
        "bootLoopState": {"none", "warning", "critical", "unknown"},
        "repeatedUndervoltageState": {
            "none",
            "warning",
            "critical",
            "unknown",
        },
        "evidenceState": {
            "healthy",
            "degraded",
            "failed",
            "stale",
            "unsupported",
        },
    }
    for field, allowed in nullable_strings.items():
        field_value = value.get(field)
        if field not in value or (
            field_value is not None
            and (
                not isinstance(field_value, str)
                or (allowed is not None and field_value not in allowed)
            )
        ):
            raise _observability_contract_error("incident state is invalid")
    for field in ("consecutiveUnexpectedBoots", "undervoltageBootsConsidered"):
        field_value = value.get(field)
        if field not in value or (
            field_value is not None
            and (
                not isinstance(field_value, int)
                or isinstance(field_value, bool)
                or field_value < 0
            )
        ):
            raise _observability_contract_error("incident state is invalid")


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
    if summary.get("operationalHealthState") not in {
        "healthy",
        "warning",
        "critical",
        "unknown",
    }:
        raise _observability_contract_error(
            "summary operationalHealthState is invalid"
        )
    operational_issue_count = summary.get("operationalIssueCount")
    if (
        not isinstance(operational_issue_count, int)
        or isinstance(operational_issue_count, bool)
        or operational_issue_count < 0
    ):
        raise _observability_contract_error(
            "summary operationalIssueCount is invalid"
        )


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
        "operationalHealthState": "unknown",
        "operationalIssueCount": 0,
        "expectedSince": None,
        "recorderVersion": None,
        "producerVersion": None,
        "protocolVersion": None,
        "readError": read_error,
    }


def _empty_observability_detail(
    *,
    state: str,
    vrcode: str,
    read_error: str | None,
) -> dict[str, Any]:
    missing = {
        "state": "missing",
        "value": None,
        "detail": "health observation is absent",
        "observedAt": None,
    }
    return {
        "state": state,
        "vrcode": vrcode,
        "support": {
            "state": "unknown",
            "source": None,
            "expectedSince": None,
            "recorderVersion": None,
            "producerVersion": None,
            "protocolVersion": None,
        },
        "report": {
            "state": "notEvaluated" if read_error is None else "readFailed",
            "receivedAt": None,
            "deviceObservedAt": None,
            "collectionState": None,
            "readIssueCount": 0,
        },
        "profile": {
            "state": "missing",
            "receivedAt": None,
            "deviceObservedAt": None,
            "deviceId": None,
            "bootId": None,
            "software": {},
            "collection": None,
            "capabilities": {},
        },
        "boot": {
            "state": "notReported",
            "orderingState": "unknown",
            "bootId": None,
            "startedAt": None,
            "cleanShutdownAt": None,
        },
        "evidenceHealth": {
            "state": "notReported",
            "checkedAt": None,
            "checkCount": 0,
            "detail": None,
        },
        "incidentState": {
            "state": "notReported",
            "policyVersion": None,
            "bootLoopState": None,
            "repeatedUndervoltageState": None,
            "evidenceState": None,
            "consecutiveUnexpectedBoots": None,
            "undervoltageBootsConsidered": None,
        },
        "operationalHealth": {
            "state": "unknown",
            "evaluatedAt": None,
            "issueCount": 0,
            "issues": [],
        },
        "readings": {
            "temperatureCelsius": dict(missing),
            "memoryAvailableBytes": dict(missing),
            "memoryTotalBytes": dict(missing),
            "rootUsedPercent": dict(missing),
            "dataUsedPercent": dict(missing),
            "recorderActiveState": dict(missing),
            "publisherActiveState": dict(missing),
            "publisherBufferBytes": dict(missing),
            "publisherBufferLimitBytes": dict(missing),
            "networkInterfaces": [],
        },
        "readIssues": [],
        "readError": read_error,
    }


def _observability_contract_error(detail: str) -> RecorderIngressDependencyError:
    return RecorderIngressDependencyError(
        f"Recorder ingress observability contract is invalid: {detail}.",
        kind="recorder-ingress-contract-invalid",
    )

from __future__ import annotations

import json
import os
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

from tirosh_guest_tools.domain.guest_control.models import (
    ProductLabDependencyError,
    ProductLabReadModelResult,
    ProductLabSessionResult,
)

DEFAULT_PRODUCT_LAB_SERVICE_BASE_URL = "http://127.0.0.1:18085"
PRODUCT_LAB_SERVICE_BASE_URL_ENV = "TIROSH_PRODUCT_LAB_URL"


class ProductLabServiceAdapter:
    def __init__(
        self,
        *,
        base_url: str | None = None,
        timeout_seconds: float = 10.0,
    ) -> None:
        self._base_url = (
            base_url
            or os.environ.get(
                PRODUCT_LAB_SERVICE_BASE_URL_ENV,
                DEFAULT_PRODUCT_LAB_SERVICE_BASE_URL,
            )
        ).rstrip("/")
        self._timeout_seconds = timeout_seconds

    def list_scenarios(self) -> dict[str, Any]:
        document = self._request_json("GET", "/lab/scenarios")
        _require_state_document(document, expected_state="loaded")
        scenarios = document.get("scenarios")
        if not isinstance(scenarios, list):
            raise ProductLabDependencyError(
                "Product Lab service response is missing scenarios.",
                kind="product-lab-contract-invalid",
            )
        return document

    def list_beds(self) -> dict[str, Any]:
        document = self._request_json("GET", "/lab/beds")
        _require_state_document(document, expected_state="loaded")
        beds = document.get("beds")
        if not isinstance(beds, list):
            raise ProductLabDependencyError(
                "Product Lab service response is missing beds.",
                kind="product-lab-contract-invalid",
            )
        return document

    def list_recorders(self) -> dict[str, Any]:
        document = self._request_json("GET", "/lab/recorders")
        _require_state_document(document, expected_state="loaded")
        recorders = document.get("recorders")
        if not isinstance(recorders, list):
            raise ProductLabDependencyError(
                "Product Lab service response is missing recorders.",
                kind="product-lab-contract-invalid",
            )
        return document

    def create_session(self, request: dict[str, Any]) -> ProductLabSessionResult:
        return _session_from_response(
            self._request_json("POST", "/lab/sessions", request)
        )

    def get_session(self, session_id: str) -> ProductLabSessionResult:
        return _session_from_response(
            self._request_json("GET", f"/lab/sessions/{_path_segment(session_id)}")
        )

    def start_session(self, session_id: str) -> ProductLabSessionResult:
        return _session_from_response(
            self._request_json(
                "POST",
                f"/lab/sessions/{_path_segment(session_id)}/start",
            )
        )

    def stop_session(self, session_id: str) -> ProductLabSessionResult:
        return _session_from_response(
            self._request_json(
                "POST",
                f"/lab/sessions/{_path_segment(session_id)}/stop",
            )
        )

    def replay_vital_file(self, request: dict[str, Any]) -> ProductLabSessionResult:
        return _session_from_response(
            self._request_json("POST", "/lab/vital-files/replay", request)
        )

    def create_beds(self, request: dict[str, Any]) -> ProductLabReadModelResult:
        return _read_model_from_response(
            self._request_json("POST", "/lab/beds/create", request),
            collection="beds",
        )

    def delete_beds(self, request: dict[str, Any]) -> ProductLabReadModelResult:
        return _read_model_from_response(
            self._request_json("POST", "/lab/beds/delete", request),
            collection="beds",
        )

    def reset_beds(self) -> ProductLabReadModelResult:
        return _read_model_from_response(
            self._request_json("POST", "/lab/beds/reset", {}),
            collection="beds",
        )

    def create_recorders(self, request: dict[str, Any]) -> ProductLabReadModelResult:
        return _read_model_from_response(
            self._request_json("POST", "/lab/recorders/create", request),
            collection="recorders",
        )

    def delete_recorders(self, request: dict[str, Any]) -> ProductLabReadModelResult:
        return _read_model_from_response(
            self._request_json("POST", "/lab/recorders/delete", request),
            collection="recorders",
        )

    def reset_recorders(self) -> ProductLabReadModelResult:
        return _read_model_from_response(
            self._request_json("POST", "/lab/recorders/reset", {}),
            collection="recorders",
        )

    def _request_json(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        body = None if payload is None else json.dumps(payload).encode("utf-8")
        request = Request(
            f"{self._base_url}{path}",
            data=body,
            method=method,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                data = response.read()
        except HTTPError as error:
            detail = _http_error_detail(error)
            raise ProductLabDependencyError(
                f"Product Lab service request failed: {method} {path}: {detail}",
                kind="product-lab-http-error",
            ) from error
        except URLError as error:
            raise ProductLabDependencyError(
                f"Product Lab service is unavailable: {error.reason}",
                kind="product-lab-unavailable",
            ) from error
        except TimeoutError as error:
            raise ProductLabDependencyError(
                "Product Lab service request timed out.",
                kind="product-lab-timeout",
            ) from error

        try:
            document = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ProductLabDependencyError(
                f"Product Lab service returned invalid JSON: {error}",
                kind="product-lab-contract-invalid",
            ) from error

        if not isinstance(document, dict):
            raise ProductLabDependencyError(
                "Product Lab service returned a non-object JSON document.",
                kind="product-lab-contract-invalid",
            )
        return document


def _session_from_response(document: dict[str, Any]) -> ProductLabSessionResult:
    _require_state_document(document, expected_state="loaded")
    session = document.get("session")
    if not isinstance(session, dict):
        raise ProductLabDependencyError(
            "Product Lab service response is missing session.",
            kind="product-lab-contract-invalid",
        )
    operation_id = document.get("operationId")
    if operation_id is not None and not isinstance(operation_id, str):
        raise ProductLabDependencyError(
            "Product Lab service response operationId must be a string or null.",
            kind="product-lab-contract-invalid",
        )
    return ProductLabSessionResult(session=session, lab_operation_id=operation_id)


def _read_model_from_response(
    document: dict[str, Any],
    *,
    collection: str,
) -> ProductLabReadModelResult:
    _require_state_document(document, expected_state="loaded")
    value = document.get(collection)
    if not isinstance(value, list):
        raise ProductLabDependencyError(
            f"Product Lab service response is missing {collection}.",
            kind="product-lab-contract-invalid",
        )
    operation_id = document.get("operationId")
    if operation_id is not None and not isinstance(operation_id, str):
        raise ProductLabDependencyError(
            "Product Lab service response operationId must be a string or null.",
            kind="product-lab-contract-invalid",
        )
    return ProductLabReadModelResult(
        document=document,
        lab_operation_id=operation_id,
    )


def _require_state_document(
    document: dict[str, Any],
    *,
    expected_state: str,
) -> None:
    state = document.get("state")
    if state != expected_state:
        read_error = document.get("readError")
        detail = read_error if isinstance(read_error, str) else f"state={state}"
        raise ProductLabDependencyError(
            f"Product Lab service returned an unexpected state: {detail}",
            kind="product-lab-contract-invalid",
        )


def _path_segment(value: str) -> str:
    if not value.strip():
        raise ProductLabDependencyError(
            "Product Lab session ID is required.",
            kind="product-lab-contract-invalid",
        )
    return quote(value, safe="")


def _http_error_detail(error: HTTPError) -> str:
    try:
        data = error.read()
        document = json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return f"status={error.code}"
    if isinstance(document, dict) and isinstance(document.get("readError"), str):
        return f"status={error.code} detail={document['readError']}"
    if isinstance(document, dict) and isinstance(document.get("message"), str):
        return f"status={error.code} detail={document['message']}"
    return f"status={error.code}"

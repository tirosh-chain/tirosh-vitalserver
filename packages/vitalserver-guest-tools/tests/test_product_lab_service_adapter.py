from __future__ import annotations

import json
from http import HTTPStatus
from io import BytesIO
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request

import pytest

from tirosh_guest_tools.adapters.outbound.product_lab import (
    DEFAULT_PRODUCT_LAB_SERVICE_BASE_URL,
    ProductLabServiceAdapter,
    lab_service,
)
from tirosh_guest_tools.domain.guest_control.models import ProductLabDependencyError


def test_product_lab_service_adapter_default_url_uses_vm_loopback_port() -> None:
    assert DEFAULT_PRODUCT_LAB_SERVICE_BASE_URL == "http://127.0.0.1:18085"


def test_product_lab_service_adapter_maps_scenarios(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(lab_service, "urlopen", fake_urlopen)
    adapter = ProductLabServiceAdapter(base_url="http://lab")

    document = adapter.list_scenarios()

    assert document == {
        "state": "loaded",
        "scenarios": [
            {
                "scenarioId": "baseline-monitoring",
                "name": "Baseline Monitoring",
                "category": "generated",
                "description": "Stable vital signs",
            }
        ],
        "readError": None,
    }


def test_product_lab_service_adapter_maps_session_lifecycle(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(lab_service, "urlopen", fake_urlopen)
    adapter = ProductLabServiceAdapter(base_url="http://lab")

    created = adapter.create_session(
        {
            "scenarioId": "baseline-monitoring",
            "recorderCount": 2,
            "targetURL": "http://edge/",
        }
    )
    loaded = adapter.get_session("lab-session-1")
    started = adapter.start_session("lab-session-1")
    stopped = adapter.stop_session("lab-session-1")
    deleted = adapter.delete_session("lab-session-1")

    assert created.session["sessionId"] == "lab-session-1"
    assert created.session["state"] == "accepted"
    assert created.lab_operation_id == "lab-operation-1"
    assert loaded.session["sessionId"] == "lab-session-1"
    assert loaded.session["state"] == "accepted"
    assert loaded.lab_operation_id == "lab-operation-1"
    assert started.session["state"] == "running"
    assert stopped.session["state"] == "stopped"
    assert deleted.document == {
        "state": "loaded",
        "sessions": [],
        "readError": None,
    }


def test_product_lab_service_adapter_maps_beds_and_recorders(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(lab_service, "urlopen", fake_urlopen)
    adapter = ProductLabServiceAdapter(base_url="http://lab")

    beds = adapter.list_beds()
    recorders = adapter.list_recorders()

    assert beds["state"] == "loaded"
    assert beds["beds"][0]["bedId"] == "lab-session-1-bed-1"
    assert recorders["state"] == "loaded"
    assert recorders["recorders"][0]["vrcode"] == "LAB-lab-session-1-1"


def test_product_lab_service_adapter_maps_vital_files(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(lab_service, "urlopen", fake_urlopen)
    adapter = ProductLabServiceAdapter(base_url="http://lab")

    catalog = adapter.list_vital_files()

    assert catalog["state"] == "loaded"
    assert catalog["vitalFiles"][0]["relativePath"] == "MORA04/sample.vital"


def test_product_lab_service_adapter_maps_vital_file_replay(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(lab_service, "urlopen", fake_urlopen)
    adapter = ProductLabServiceAdapter(base_url="http://lab")

    result = adapter.replay_vital_file(
        {
            "vitalFileRelativePath": "sample.vital",
            "resourceSelection": {"mode": "quickCreate"},
            "repeatPolicy": {"mode": "once"},
        }
    )

    assert result.session["sessionId"] == "lab-replay-1"
    assert result.session["scenarioId"] == "vital-file-replay"
    assert result.session["name"] == "Vital File Replay"
    assert result.lab_operation_id == "lab-operation-1"


def test_product_lab_service_adapter_preserves_http_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setattr(lab_service, "urlopen", fake_urlopen)
    adapter = ProductLabServiceAdapter(base_url="http://lab")

    with pytest.raises(ProductLabDependencyError) as error:
        adapter.get_session("missing-session")

    assert error.value.kind == "product-lab-http-error"
    assert "Lab session is not available: missing-session" in error.value.message


def fake_urlopen(request: Request, timeout: float) -> FakeResponse:
    del timeout
    method = request.get_method()
    path = request.full_url.removeprefix("http://lab")
    if method == "GET" and path == "/lab/scenarios":
        return FakeResponse(
            {
                "state": "loaded",
                "scenarios": [
                    {
                        "scenarioId": "baseline-monitoring",
                        "name": "Baseline Monitoring",
                        "category": "generated",
                        "description": "Stable vital signs",
                    }
                ],
                "readError": None,
            }
        )
    if method == "GET" and path == "/lab/beds":
        return FakeResponse(
            {
                "state": "loaded",
                "beds": [
                    {
                        "bedId": "lab-session-1-bed-1",
                        "sessionId": "lab-session-1",
                        "name": "OR-A",
                        "state": "running",
                        "createdAt": "2026-07-01T00:00:00Z",
                        "updatedAt": "2026-07-01T00:00:01Z",
                    }
                ],
                "readError": None,
            }
        )
    if method == "GET" and path == "/lab/recorders":
        return FakeResponse(
            {
                "state": "loaded",
                "recorders": [
                    {
                        "recorderId": "lab-session-1-recorder-1",
                        "sessionId": "lab-session-1",
                        "bedId": "lab-session-1-bed-1",
                        "vrcode": "LAB-lab-session-1-1",
                        "state": "running",
                        "createdAt": "2026-07-01T00:00:00Z",
                        "updatedAt": "2026-07-01T00:00:01Z",
                    }
                ],
                "readError": None,
            }
        )
    if method == "GET" and path == "/lab/vital-files":
        return FakeResponse(
            {
                "state": "loaded",
                "vitalFiles": [
                    {
                        "displayName": "sample.vital",
                        "relativePath": "MORA04/sample.vital",
                        "guestPath": "/mnt/tirosh-vital-files/MORA04/sample.vital",
                        "sizeBytes": 123,
                        "modifiedAt": "2026-07-01T00:00:00Z",
                    }
                ],
                "readError": None,
            }
        )
    if method == "GET" and path == "/lab/sessions/lab-session-1":
        return FakeResponse(session_response(session_state="accepted"))
    if method == "POST" and path == "/lab/sessions":
        return FakeResponse(session_response(session_state="accepted"))
    if method == "POST" and path == "/lab/sessions/lab-session-1/start":
        return FakeResponse(session_response(session_state="running"))
    if method == "POST" and path == "/lab/sessions/lab-session-1/stop":
        return FakeResponse(session_response(session_state="stopped"))
    if method == "POST" and path == "/lab/sessions/lab-session-1/delete":
        return FakeResponse({"state": "loaded", "sessions": [], "readError": None})
    if method == "POST" and path == "/lab/vital-files/replay":
        return FakeResponse(
            session_response(
                session_id="lab-replay-1",
                scenario_id="vital-file-replay",
                name="Vital File Replay",
                session_state="accepted",
            )
        )
    raise HTTPError(
        request.full_url,
        HTTPStatus.NOT_FOUND.value,
        "not found",
        hdrs={},
        fp=BytesIO(
            json.dumps(
                {
                    "state": "failed",
                    "operationId": None,
                    "session": None,
                    "readError": "Lab session is not available: missing-session",
                }
            ).encode("utf-8")
        ),
    )


class FakeResponse:
    def __init__(self, payload: dict[str, Any]) -> None:
        self.payload = payload

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def read(self) -> bytes:
        return json.dumps(self.payload).encode("utf-8")


def session_response(
    *,
    session_id: str = "lab-session-1",
    scenario_id: str = "baseline-monitoring",
    name: str = "Baseline Monitoring",
    session_state: str,
) -> dict[str, Any]:
    return {
        "state": "loaded",
        "operationId": "lab-operation-1",
        "session": {
            "sessionId": session_id,
            "scenarioId": scenario_id,
            "name": name,
            "recorderCount": 1,
            "targetURL": "http://edge/",
            "state": session_state,
            "createdAt": "2026-07-01T00:00:00Z",
            "updatedAt": "2026-07-01T00:00:01Z",
        },
        "readError": None,
    }

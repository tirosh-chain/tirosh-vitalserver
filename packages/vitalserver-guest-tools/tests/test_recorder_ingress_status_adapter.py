from __future__ import annotations

from typing import Any

import pytest

from tirosh_guest_tools.adapters.outbound.recorder_ingress import status_service
from tirosh_guest_tools.adapters.outbound.recorder_ingress.status_service import (
    RecorderIngressStatusServiceAdapter,
)
from tirosh_guest_tools.domain.guest_control.models import (
    RecorderIngressDependencyError,
)


def test_recorder_ingress_status_adapter_wraps_status_document(
    monkeypatch: Any,
) -> None:
    requests: list[str] = []

    class Response:
        status = 200

        def __enter__(self) -> Response:
            return self

        def __exit__(self, *args: object) -> None:
            del args

        def read(self) -> bytes:
            return (
                b'{"activeRecorderConnections":2,'
                b'"recorders":[{"vrcode":"VR-001","activeConnections":1}]}'
            )

    def fake_urlopen(request: Any, *, timeout: float) -> Response:
        assert timeout == 5.0
        requests.append(request.full_url)
        return Response()

    monkeypatch.setattr(status_service, "urlopen", fake_urlopen)

    response = RecorderIngressStatusServiceAdapter(
        status_url="http://recorder-ingress:8080/recorder-ingress/status"
    ).status()

    assert requests == ["http://recorder-ingress:8080/recorder-ingress/status"]
    assert response == {
        "readState": "loaded",
        "httpStatus": "200",
        "document": {
            "activeRecorderConnections": 2,
            "recorders": [{"vrcode": "VR-001", "activeConnections": 1}],
        },
        "readError": None,
    }


def test_recorder_ingress_status_adapter_default_url_uses_vm_loopback_port(
    monkeypatch: Any,
) -> None:
    requests: list[str] = []

    class Response:
        status = 200

        def __enter__(self) -> Response:
            return self

        def __exit__(self, *args: object) -> None:
            del args

        def read(self) -> bytes:
            return b"{}"

    def fake_urlopen(request: Any, *, timeout: float) -> Response:
        del timeout
        requests.append(request.full_url)
        return Response()

    monkeypatch.setattr(status_service, "urlopen", fake_urlopen)

    RecorderIngressStatusServiceAdapter().status()

    assert requests == ["http://127.0.0.1:18083/recorder-ingress/status"]


def test_recorder_ingress_status_adapter_rejects_invalid_json(
    monkeypatch: Any,
) -> None:
    class Response:
        status = 200

        def __enter__(self) -> Response:
            return self

        def __exit__(self, *args: object) -> None:
            del args

        def read(self) -> bytes:
            return b"not-json"

    monkeypatch.setattr(status_service, "urlopen", lambda *args, **kwargs: Response())

    with pytest.raises(RecorderIngressDependencyError) as error:
        RecorderIngressStatusServiceAdapter().status()

    assert error.value.kind == "recorder-ingress-contract-invalid"
    assert error.value.message.startswith(
        "Recorder ingress status returned invalid JSON:"
    )

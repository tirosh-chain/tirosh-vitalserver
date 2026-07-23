from __future__ import annotations

from typing import Any
from io import BytesIO
from urllib.error import HTTPError

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


def test_recorder_ingress_adapter_reads_native_vital_upload_receipts(
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
                b'{"state":"loaded","uploads":[{'
                b'"origin":"nativeRecorderUpload","uploadId":"upload-001"'
                b'}],"readError":null}'
            )

    def fake_urlopen(request: Any, *, timeout: float) -> Response:
        assert timeout == 5.0
        requests.append(request.full_url)
        return Response()

    monkeypatch.setattr(status_service, "urlopen", fake_urlopen)

    response = RecorderIngressStatusServiceAdapter(
        native_uploads_url=(
            "http://recorder-ingress:8080/"
            "recorder-ingress/vital-files/uploads"
        )
    ).native_vital_uploads()

    assert requests == [
        "http://recorder-ingress:8080/recorder-ingress/vital-files/uploads"
    ]
    assert response["state"] == "loaded"
    assert response["uploads"] == [
        {"origin": "nativeRecorderUpload", "uploadId": "upload-001"}
    ]


def test_recorder_ingress_adapter_reads_observability_and_preserves_legacy_unknown(
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
            return b'{"state":"loaded","recorders":[],"readError":null}'

    def fake_urlopen(request: Any, *, timeout: float) -> Response:
        del timeout
        requests.append(request.full_url)
        return Response()

    monkeypatch.setattr(status_service, "urlopen", fake_urlopen)
    adapter = RecorderIngressStatusServiceAdapter(
        observability_url="http://recorder-ingress:8080/runtime/vitaldb/recorders"
    )

    assert adapter.recorder_observability()["state"] == "loaded"
    assert requests == [
        "http://recorder-ingress:8080/runtime/vitaldb/recorders"
    ]

    def not_found(request: Any, *, timeout: float) -> None:
        del timeout
        raise HTTPError(
            request.full_url,
            404,
            "not found",
            {},
            BytesIO(b'{"state":"not_found"}'),
        )

    monkeypatch.setattr(status_service, "urlopen", not_found)
    detail = adapter.recorder_observability_detail("VR legacy")
    assert detail == {
        "state": "notReported",
        "vrcode": "VR legacy",
        "supportState": "unknown",
        "supportSource": None,
        "reportState": "notEvaluated",
        "profileState": None,
        "collectionState": None,
        "latestObservationReceivedAt": None,
        "lastBootStartedAt": None,
        "readIssueCount": None,
        "expectedSince": None,
        "recorderVersion": None,
        "producerVersion": None,
        "protocolVersion": None,
        "readError": None,
    }


def test_recorder_ingress_adapter_rejects_incomplete_observability_summary(
    monkeypatch: Any,
) -> None:
    class Response:
        status = 200

        def __enter__(self) -> Response:
            return self

        def __exit__(self, *args: object) -> None:
            del args

        def read(self) -> bytes:
            return (
                b'{"state":"loaded","recorders":[{'
                b'"vrcode":"VR-001","supportState":"supported",'
                b'"supportSource":"accepted_report","reportState":"current"'
                b"}]}"
            )

    monkeypatch.setattr(
        status_service,
        "urlopen",
        lambda *args, **kwargs: Response(),
    )

    with pytest.raises(RecorderIngressDependencyError) as error:
        RecorderIngressStatusServiceAdapter().recorder_observability()

    assert error.value.kind == "recorder-ingress-contract-invalid"
    assert "profileState" in error.value.message

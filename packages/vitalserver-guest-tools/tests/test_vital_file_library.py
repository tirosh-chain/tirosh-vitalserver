import gzip
import json
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.vital_files import (
    VitalServerHTTPResponse,
    VitalServerVitalFileLibrary,
)
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError
from tirosh_guest_tools.domain.runtime_config import RuntimeConfig


class FakeTransport:
    def __init__(self, responses: list[VitalServerHTTPResponse]) -> None:
        self.responses = list(responses)
        self.requests: list[dict[str, object]] = []

    def request(self, **request: object) -> VitalServerHTTPResponse:
        self.requests.append(request)
        return self.responses.pop(0)


def response(body: bytes, status: int = 200) -> VitalServerHTTPResponse:
    return VitalServerHTTPResponse(status_code=status, headers={}, body=body)


def login_response() -> VitalServerHTTPResponse:
    return response(b'{"res":true,"access_token":"access-token"}')


def file_list_response(items: list[dict[str, object]]) -> VitalServerHTTPResponse:
    return response(gzip.compress(json.dumps(items).encode()))


def library(transport: FakeTransport) -> VitalServerVitalFileLibrary:
    return VitalServerVitalFileLibrary(
        base_url="http://127.0.0.1:18080",
        guest_mount=Path("/mnt/tirosh-vital-files"),
        runtime_config=lambda: RuntimeConfig(
            admin_password="secret",
            public_host="",
            public_port=18080,
            redis_host="redis",
            redis_port=6379,
            trust_proxy=False,
            vital_files_directory="/mnt/tirosh-vital-files",
        ),
        transport=transport,
    )


def indexed_file(filename: str, size: int) -> dict[str, object]:
    return {"filename": filename, "filesize": size, "dtupload": 1784102400}


def test_lists_vitalserver_index_as_replayable_guest_paths() -> None:
    filename = "OR-A_260715_120000.vital"
    transport = FakeTransport(
        [login_response(), file_list_response([indexed_file(filename, 123)])]
    )

    result = library(transport).list_files()

    assert result == [
        {
            "displayName": filename,
            "relativePath": f"OR-A/202607/260715/{filename}",
            "guestPath": f"/mnt/tirosh-vital-files/OR-A/202607/260715/{filename}",
            "sizeBytes": 123,
            "modifiedAt": "2026-07-15T08:00:00Z",
        }
    ]
    assert transport.requests[0]["url"] == "http://127.0.0.1:18080/api/login"
    assert "access_token=access-token" in str(transport.requests[1]["url"])


def test_uploads_each_selected_file_through_vitalserver_and_verifies_index() -> None:
    first = "OR-A_260715_120000.vital"
    second = "OR-B_260715_120001.vital"
    transport = FakeTransport(
        [
            login_response(),
            file_list_response([]),
            response(b"success"),
            response(b"success"),
            login_response(),
            file_list_response([indexed_file(first, 5), indexed_file(second, 6)]),
        ]
    )

    result = library(transport).import_files([(first, b"first"), (second, b"second")])

    assert [item["fileName"] for item in result] == [first, second]
    upload_requests = [
        request
        for request in transport.requests
        if str(request["url"]).endswith("/upload")
    ]
    assert len(upload_requests) == 2
    assert b'name="vitalfile"' in upload_requests[0]["body"]
    assert first.encode() in upload_requests[0]["body"]


def test_rejects_entire_batch_before_api_calls_when_one_file_is_not_vital() -> None:
    transport = FakeTransport([])

    with pytest.raises(GuestControlDependencyError) as raised:
        library(transport).import_files(
            [("OR-A_260715_120000.vital", b"vital"), ("rejected.txt", b"text")]
        )

    assert raised.value.kind == "vitalFileUploadInvalid"
    assert transport.requests == []


def test_rejects_unindexable_vitalserver_filename_before_api_calls() -> None:
    transport = FakeTransport([])

    with pytest.raises(GuestControlDependencyError) as raised:
        library(transport).import_files([("case.vital", b"vital")])

    assert raised.value.kind == "vitalFileUploadInvalid"
    assert "<bed>_YYMMDD_HHMMSS.vital" in raised.value.message
    assert transport.requests == []


def test_does_not_report_http_200_parser_error_as_upload_success() -> None:
    filename = "OR-A_260715_120000.vital"
    transport = FakeTransport(
        [login_response(), file_list_response([]), response(b"invalid vital header")]
    )

    with pytest.raises(GuestControlDependencyError) as raised:
        library(transport).import_files([(filename, b"invalid")])

    assert raised.value.kind == "vitalFileUploadFailed"
    assert "invalid vital header" in raised.value.message


def test_reports_successful_upload_that_is_missing_from_vitalserver_index() -> None:
    filename = "OR-A_260715_120000.vital"
    transport = FakeTransport(
        [
            login_response(),
            file_list_response([]),
            response(b"success"),
            login_response(),
            file_list_response([]),
        ]
    )

    with pytest.raises(GuestControlDependencyError) as raised:
        library(transport).import_files([(filename, b"content")])

    assert raised.value.kind == "vitalFileUploadNotIndexed"


def test_preserves_partial_batch_completion_when_later_upload_fails() -> None:
    first = "OR-A_260715_120000.vital"
    second = "OR-B_260715_120001.vital"
    transport = FakeTransport(
        [
            login_response(),
            file_list_response([]),
            response(b"success"),
            response(b"parse failed"),
        ]
    )

    with pytest.raises(GuestControlDependencyError) as raised:
        library(transport).import_files([(first, b"first"), (second, b"second")])

    assert raised.value.kind == "vitalFileUploadPartiallyCompleted"
    assert first in raised.value.message

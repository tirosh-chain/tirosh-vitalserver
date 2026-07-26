import gzip
import json
import struct
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path
from typing import cast

import pytest

from tirosh_guest_tools.adapters.outbound.vital_files import (
    VitalServerHTTPResponse,
    VitalServerVitalFileLibrary,
)
from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlDependencyError,
    VitalFileUploadResult,
)
from tirosh_guest_tools.domain.runtime_config import RuntimeConfig


class FakeTransport:
    def __init__(self, responses: list[VitalServerHTTPResponse]) -> None:
        self.responses = list(responses)
        self.requests: list[dict[str, object]] = []

    def request(self, **request: object) -> VitalServerHTTPResponse:
        self.requests.append(request)
        return self.responses.pop(0)


class ConnectionRefusedTransport(FakeTransport):
    def __init__(self) -> None:
        super().__init__([])

    def request(self, **request: object) -> VitalServerHTTPResponse:
        self.requests.append(request)
        raise ConnectionRefusedError(111, "Connection refused")


def response(body: bytes, status: int = 200) -> VitalServerHTTPResponse:
    return VitalServerHTTPResponse(status_code=status, headers={}, body=body)


def login_response() -> VitalServerHTTPResponse:
    return response(b'{"res":true,"access_token":"access-token"}')


def file_list_response(items: list[dict[str, object]]) -> VitalServerHTTPResponse:
    return response(gzip.compress(json.dumps(items).encode()))


def empty_file_list_response() -> VitalServerHTTPResponse:
    return response(b'{"message":"No result found"}', status=404)


def vital_content(payload: bytes = b"", *, version: int = 3) -> bytes:
    header = struct.pack("<hI4B", -540, 0, 0, 0, 0, 0)
    if version == 3:
        header += struct.pack("<ddB", 100.0, 101.0, 0)
    return gzip.compress(
        b"VITA" + struct.pack("<IH", version, len(header)) + header + payload
    )


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0
        self.sleeps: list[float] = []

    def monotonic(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.sleeps.append(seconds)
        self.now += seconds


@dataclass(frozen=True)
class MemoryUploadSource:
    file_name: str
    content: bytes

    @property
    def size_bytes(self) -> int:
        return len(self.content)

    def open(self) -> BytesIO:
        return BytesIO(self.content)


def library(
    transport: FakeTransport, **overrides: object
) -> VitalServerVitalFileLibrary:
    arguments: dict[str, object] = {"index_wait_seconds": 0.0}
    arguments.update(overrides)
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
        **arguments,
    )


def indexed_file(filename: str, size: int) -> dict[str, object]:
    return {"filename": filename, "filesize": size, "dtupload": 1784102400}


def import_files(
    target: VitalServerVitalFileLibrary,
    files: list[tuple[str, bytes]],
) -> VitalFileUploadResult:
    return target.import_sources(
        [MemoryUploadSource(file_name=name, content=content) for name, content in files]
    )


def request_body(request: dict[str, object]) -> bytes:
    body = request["body"]
    if isinstance(body, bytes):
        return body
    return b"".join(cast(tuple[bytes, ...], body))


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


def test_unavailable_error_identifies_the_failed_vitalserver_endpoint() -> None:
    transport = ConnectionRefusedTransport()

    with pytest.raises(GuestControlDependencyError) as raised:
        library(transport).list_files()

    assert raised.value.kind == "vitalFileLibraryUnavailable"
    assert "url=http://127.0.0.1:18080/api/login" in raised.value.message


def test_lists_empty_vitalserver_library_from_its_explicit_no_result_response() -> None:
    transport = FakeTransport([login_response(), empty_file_list_response()])

    assert library(transport).list_files() == []


def test_does_not_treat_an_unrelated_file_list_404_as_an_empty_library() -> None:
    transport = FakeTransport([login_response(), response(b"not found", status=404)])

    with pytest.raises(GuestControlDependencyError) as raised:
        library(transport).list_files()

    assert raised.value.kind == "vitalFileLibraryReadFailed"


def test_uploads_each_selected_file_through_vitalserver_and_verifies_index() -> None:
    first = "OR-A_260715_120000.vital"
    second = "OR-B_260715_120001.vital"
    first_content = vital_content(b"first")
    second_content = vital_content(b"second")
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

    result = import_files(
        library(transport), [(first, first_content), (second, second_content)]
    )

    assert result.state.value == "completed"
    assert [item.file_name for item in result.files] == [first, second]
    assert result.failed_files == ()
    upload_requests = [
        request
        for request in transport.requests
        if str(request["url"]).endswith("/upload")
    ]
    assert len(upload_requests) == 2
    first_body = request_body(upload_requests[0])
    second_body = request_body(upload_requests[1])
    assert b'name="vitalfile"' in first_body
    assert first.encode() in first_body
    assert second.encode() not in first_body
    assert b'name="vitalfile"' in second_body
    assert second.encode() in second_body
    assert first.encode() not in second_body
    headers = cast(dict[str, str], upload_requests[0]["headers"])
    assert headers["Content-Length"] == str(len(first_body))
    assert not isinstance(upload_requests[0]["body"], bytes)
    assert not isinstance(upload_requests[1]["body"], bytes)


def test_uploads_through_vitalserver_when_its_library_is_initially_empty() -> None:
    filename = "OR-A_260715_120000.vital"
    content = vital_content(b"first")
    transport = FakeTransport(
        [
            login_response(),
            empty_file_list_response(),
            response(b"success"),
            login_response(),
            file_list_response([indexed_file(filename, 5)]),
        ]
    )

    result = import_files(library(transport), [(filename, content)])

    assert result.as_json() == {
        "state": "completed",
        "files": [
            {
                "fileName": filename,
                "relativePath": f"OR-A/202607/260715/{filename}",
                "sizeBytes": len(content),
            }
        ],
        "failedFiles": [],
    }
    assert [request["url"] for request in transport.requests] == [
        "http://127.0.0.1:18080/api/login",
        "http://127.0.0.1:18080/api/filelist?access_token=access-token&unixtimestamp=1",
        "http://127.0.0.1:18080/upload",
        "http://127.0.0.1:18080/api/login",
        "http://127.0.0.1:18080/api/filelist?access_token=access-token&unixtimestamp=1",
    ]


def test_reports_invalid_file_without_blocking_other_uploads() -> None:
    filename = "OR-A_260715_120000.vital"
    transport = FakeTransport([])

    result = import_files(
        library(transport),
        [
            ("rejected.txt", b"text"),
            ("OR-A_260715_120000.vital", b"\x1f\x8b\x08\x00truncated"),
        ],
    )

    assert result.state.value == "failed"
    assert result.files == ()
    assert [item.file_name for item in result.failed_files] == [
        "rejected.txt",
        filename,
    ]
    assert "Only .vital files" in result.failed_files[0].reason
    assert "gzip stream is invalid" in result.failed_files[1].reason
    assert transport.requests == []


def test_reports_unindexable_filename_without_api_calls() -> None:
    transport = FakeTransport([])

    result = import_files(library(transport), [("case.vital", b"vital")])

    assert result.state.value == "failed"
    assert "<bed>_YYMMDD_HHMMSS.vital" in result.failed_files[0].reason
    assert transport.requests == []


def test_reports_truncated_vital_file_before_any_vitalserver_api_call() -> None:
    transport = FakeTransport([])

    result = import_files(
        library(transport), [("OR-A_260715_120000.vital", b"\x1f\x8b\x08\x00truncated")]
    )

    assert result.state.value == "failed"
    assert "gzip stream is invalid" in result.failed_files[0].reason
    assert transport.requests == []


@pytest.mark.parametrize("version", [1, 2, 3])
def test_upload_preflight_accepts_each_supported_vital_version(version: int) -> None:
    filename = f"OR-A_260715_12000{version}.vital"
    transport = FakeTransport(
        [
            login_response(),
            file_list_response([]),
            response(b"success"),
            login_response(),
            file_list_response([indexed_file(filename, 5)]),
        ]
    )

    result = import_files(
        library(transport), [(filename, vital_content(version=version))]
    )

    assert result.state.value == "completed"


def test_upload_preflight_rejects_future_version_before_vitalserver_api_call() -> None:
    transport = FakeTransport([])

    result = import_files(
        library(transport), [("OR-A_260715_120004.vital", vital_content(version=4))]
    )

    assert result.state.value == "failed"
    assert "code=unsupportedFormatVersion" in result.failed_files[0].reason
    assert transport.requests == []


def test_upload_preflight_rejects_truncated_declared_header() -> None:
    content = gzip.compress(b"VITA" + struct.pack("<IH", 3, 27) + b"short")
    transport = FakeTransport([])

    result = import_files(
        library(transport),
        [("OR-A_260715_120000.vital", content)],
    )

    assert result.state.value == "failed"
    assert "code=truncatedHeader" in result.failed_files[0].reason
    assert transport.requests == []


def test_reports_http_200_parser_error_as_file_failure() -> None:
    filename = "OR-A_260715_120000.vital"
    transport = FakeTransport(
        [login_response(), file_list_response([]), response(b"invalid vital header")]
    )

    result = import_files(
        library(transport),
        [(filename, vital_content(b"source"))],
    )

    assert result.state.value == "failed"
    assert "invalid vital header" in result.failed_files[0].reason


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

    result = import_files(
        library(transport),
        [(filename, vital_content(b"content"))],
    )

    assert result.state.value == "failed"
    assert "did not report the file in its index" in result.failed_files[0].reason


def test_waits_for_vitalserver_to_publish_uploaded_file_indexes() -> None:
    filename = "OR-A_260715_120000.vital"
    clock = FakeClock()
    content = vital_content(b"first")
    transport = FakeTransport(
        [
            login_response(),
            file_list_response([]),
            response(b"success"),
            login_response(),
            file_list_response([]),
            login_response(),
            file_list_response([indexed_file(filename, 5)]),
        ]
    )

    result = import_files(
        library(
            transport,
            index_wait_seconds=5.0,
            index_poll_interval_seconds=1.0,
            monotonic_clock=clock.monotonic,
            sleep_fn=clock.sleep,
        ),
        [(filename, content)],
    )

    assert result.as_json() == {
        "state": "completed",
        "files": [
            {
                "fileName": filename,
                "relativePath": f"OR-A/202607/260715/{filename}",
                "sizeBytes": len(content),
            }
        ],
        "failedFiles": [],
    }
    assert clock.sleeps == [1.0]


def test_attempts_later_files_when_an_earlier_upload_fails() -> None:
    first = "OR-A_260715_120000.vital"
    second = "OR-B_260715_120001.vital"
    transport = FakeTransport(
        [
            login_response(),
            file_list_response([]),
            response(b"success"),
            response(b"parse failed"),
            login_response(),
            file_list_response([indexed_file(first, 5)]),
        ]
    )

    result = import_files(
        library(transport),
        [(first, vital_content(b"first")), (second, vital_content(b"second"))],
    )

    assert result.state.value == "partial"
    assert [item.file_name for item in result.files] == [first]
    assert [item.file_name for item in result.failed_files] == [second]
    upload_requests = [
        request
        for request in transport.requests
        if str(request["url"]).endswith("/upload")
    ]
    assert len(upload_requests) == 2


def test_attempts_valid_files_when_another_file_has_invalid_gzip_content() -> None:
    first = "OR-A_260715_120000.vital"
    rejected = "OR-B_260715_120001.vital"
    second = "OR-C_260715_120002.vital"
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

    result = import_files(
        library(transport),
        [
            (first, vital_content(b"first")),
            (rejected, b"\x1f\x8b\x08\x00truncated"),
            (second, vital_content(b"second")),
        ],
    )

    assert result.state.value == "partial"
    assert [item.file_name for item in result.files] == [first, second]
    assert [item.file_name for item in result.failed_files] == [rejected]
    assert "gzip stream is invalid" in result.failed_files[0].reason
    assert (
        len(
            [
                request
                for request in transport.requests
                if str(request["url"]).endswith("/upload")
            ]
        )
        == 2
    )

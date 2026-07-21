from __future__ import annotations

import gzip
import hashlib
import json
from pathlib import Path

import pytest

from tirosh_vitalserver.recorder_recovery.adapters.outbound.artifact_publisher import (
    VitalServerArtifactPublisher,
)
from tirosh_vitalserver.recorder_recovery.application.ports import (
    ArtifactPublishDependencyError,
)
from tirosh_vitalserver.recorder_recovery.domain import (
    RecoveryArtifactOrigin,
    RecoveryArtifactReceipt,
)
from tirosh_vitalserver.recorder_recovery.schemas.http import HttpResponse


class FakeClient:
    def __init__(self, *, filelist_body: bytes) -> None:
        self.filelist_body = filelist_body
        self.uploaded: list[Path] = []

    def login(self, user_id: str, password: str) -> HttpResponse:
        assert (user_id, password) == ("admin", "secret")
        return _response(200, b'{"res":true,"access_token":"token"}')

    def filelist(self, access_token: str, **filters: str | int) -> HttpResponse:
        assert access_token == "token"
        assert filters == {"unixtimestamp": 1}
        return _response(200, self.filelist_body)

    def upload_vital_file(self, path: Path) -> HttpResponse:
        self.uploaded.append(path)
        return _response(200, b"success")


def test_publisher_validates_receipt_streams_upload_and_reads_index(
    tmp_path: Path,
) -> None:
    receipt = _receipt(tmp_path, b"complete vital bytes")
    filelist = gzip.compress(
        json.dumps(
            [{"filename": receipt.filename, "filesize": receipt.size_bytes}]
        ).encode()
    )
    client = FakeClient(filelist_body=filelist)
    publisher = VitalServerArtifactPublisher(
        base_url="http://app",
        admin_password="secret",
        index_wait_seconds=0,
    )
    publisher._client = client

    publisher.upload(receipt)
    indexed = publisher.wait_until_indexed(
        receipt.filename,
        size_bytes=receipt.size_bytes,
    )

    assert client.uploaded == [Path(receipt.path)]
    assert indexed is not None
    assert indexed.filename == receipt.filename


def test_publisher_rejects_artifact_hash_mismatch_before_upload(
    tmp_path: Path,
) -> None:
    receipt = _receipt(tmp_path, b"original")
    Path(receipt.path).write_bytes(b"modified")
    client = FakeClient(filelist_body=gzip.compress(b"[]"))
    publisher = VitalServerArtifactPublisher(
        base_url="http://app",
        admin_password="secret",
    )
    publisher._client = client

    with pytest.raises(ArtifactPublishDependencyError) as captured:
        publisher.upload(receipt)

    assert captured.value.stage == "artifactValidation"
    assert captured.value.code in {"artifactSizeMismatch", "artifactHashMismatch"}
    assert client.uploaded == []


def _receipt(tmp_path: Path, content: bytes) -> RecoveryArtifactReceipt:
    path = tmp_path / "VR_A_260101_000000.vital"
    path.write_bytes(content)
    return RecoveryArtifactReceipt(
        artifact_id="a" * 64,
        origin=RecoveryArtifactOrigin.COLD_PATH_RECOVERY,
        producer="recorder-recovery",
        writer_version="3",
        vrcode="VR_A",
        room_names=("OR-A",),
        source_archive_id="raw-a",
        source_start_offset=0,
        source_end_offset=10,
        coverage_started_at=1.0,
        coverage_ended_at=2.0,
        format_version=3,
        sha256=hashlib.sha256(content).hexdigest(),
        path=str(path),
        filename=path.name,
        size_bytes=len(content),
        created_at=3.0,
        track_count=1,
    )


def _response(status_code: int, body: bytes) -> HttpResponse:
    return HttpResponse(
        status_code=status_code,
        headers={},
        body=body,
        elapsed_seconds=0.0,
    )

from __future__ import annotations

from io import StringIO
from pathlib import Path
from typing import Any

from vitalserver_redis_relay import relay_loop
from vitalserver_redis_relay.status_owner import StatusOwnerPublishResult


class FakeStatusOwner:
    def __init__(self, *, published: bool = True) -> None:
        self.documents: list[dict[str, object]] = []
        self.published = published

    def publish(self, document: dict[str, Any]) -> StatusOwnerPublishResult:
        self.documents.append(document)
        return StatusOwnerPublishResult(
            published=self.published,
            error=None if self.published else "owner unavailable",
        )


def test_record_status_publishes_owner_when_artifact_write_fails(
    monkeypatch,
    tmp_path: Path,
) -> None:
    def fail_artifact_write(path: Path, document: dict[str, object]) -> None:
        del path
        del document
        raise OSError("permission denied")

    monkeypatch.setattr(relay_loop, "write_status_artifact", fail_artifact_write)
    stderr = StringIO()
    monkeypatch.setattr(relay_loop, "stderr", stderr)
    status_owner = FakeStatusOwner()
    document: dict[str, object] = {
        "observedAt": "2026-07-01T00:00:00Z",
        "state": "running",
    }

    relay_loop._record_status(
        status_owner=status_owner,
        status_path=tmp_path / "status.json",
        document=document,
    )

    assert status_owner.documents == [document]
    assert "redis relay status artifact write failed" in stderr.getvalue()


def test_record_status_writes_diagnostics_when_owner_publish_fails(
    monkeypatch,
    tmp_path: Path,
) -> None:
    stderr = StringIO()
    monkeypatch.setattr(relay_loop, "stderr", stderr)
    status_owner = FakeStatusOwner(published=False)
    status_path = tmp_path / "status.json"
    document: dict[str, object] = {
        "observedAt": "2026-07-01T00:00:00Z",
        "state": "running",
    }

    relay_loop._record_status(
        status_owner=status_owner,
        status_path=status_path,
        document=document,
    )

    assert status_owner.documents == [document]
    assert status_path.read_text().endswith("\n")
    assert "redis relay status owner publish skipped" in stderr.getvalue()

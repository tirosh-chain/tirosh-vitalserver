from __future__ import annotations

from io import StringIO
from typing import Any

import pytest

from vitalserver_redis_relay import relay_loop
from vitalserver_redis_relay.status_publisher import (
    CompositeStatusPublisher,
    StatusPublishError,
    StatusPublishOutcome,
    StatusPublishResult,
)


class FakeStatusPublisher:
    def __init__(
        self,
        name: str,
        *,
        published: bool = True,
        error: str | None = None,
    ) -> None:
        self.name = name
        self.documents: list[dict[str, object]] = []
        self.published = published
        self.error = error

    def publish(self, document: dict[str, Any]) -> StatusPublishResult:
        self.documents.append(document)
        return StatusPublishResult(
            outcomes=(
                StatusPublishOutcome(
                    publisher=self.name,
                    published=self.published,
                    error=None if self.published else self.error,
                ),
            )
        )


def test_record_status_publishes_owner_when_artifact_write_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    stderr = StringIO()
    monkeypatch.setattr(relay_loop, "stderr", stderr)
    file_publisher = FakeStatusPublisher(
        "file",
        published=False,
        error="permission denied",
    )
    owner = FakeStatusPublisher("http")
    document: dict[str, object] = {
        "observedAt": "2026-07-01T00:00:00Z",
        "state": "running",
    }

    relay_loop._record_status(
        status_publisher=CompositeStatusPublisher((file_publisher, owner)),
        document=document,
    )

    assert file_publisher.documents == [document]
    assert owner.documents == [document]
    assert "redis relay status publisher file failed: permission denied" in (
        stderr.getvalue()
    )
    assert "skipped" not in stderr.getvalue()


def test_record_status_writes_diagnostics_when_owner_publish_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    stderr = StringIO()
    monkeypatch.setattr(relay_loop, "stderr", stderr)
    file_publisher = FakeStatusPublisher("file")
    owner = FakeStatusPublisher("http", published=False, error="owner unavailable")
    document: dict[str, object] = {
        "observedAt": "2026-07-01T00:00:00Z",
        "state": "running",
    }

    relay_loop._record_status(
        status_publisher=CompositeStatusPublisher((file_publisher, owner)),
        document=document,
    )

    assert file_publisher.documents == [document]
    assert owner.documents == [document]
    assert "redis relay status publisher http failed: owner unavailable" in (
        stderr.getvalue()
    )
    assert "skipped" not in stderr.getvalue()


def test_record_status_calls_remaining_publishers_after_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    stderr = StringIO()
    monkeypatch.setattr(relay_loop, "stderr", stderr)
    first = FakeStatusPublisher("file", published=False, error="permission denied")
    second = FakeStatusPublisher("http")
    document: dict[str, object] = {"state": "running"}

    relay_loop._record_status(
        status_publisher=CompositeStatusPublisher((first, second)),
        document=document,
    )

    assert first.documents == [document]
    assert second.documents == [document]


def test_record_status_raises_when_all_publishers_fail(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    stderr = StringIO()
    monkeypatch.setattr(relay_loop, "stderr", stderr)
    file_publisher = FakeStatusPublisher(
        "file",
        published=False,
        error="permission denied",
    )
    owner = FakeStatusPublisher("http", published=False, error="owner unavailable")
    document: dict[str, object] = {"state": "running"}

    with pytest.raises(StatusPublishError, match="file: permission denied") as error:
        relay_loop._record_status(
            status_publisher=CompositeStatusPublisher((file_publisher, owner)),
            document=document,
        )

    assert file_publisher.documents == [document]
    assert owner.documents == [document]
    assert "http: owner unavailable" in str(error.value)
    assert "redis relay status publisher file failed: permission denied" in (
        stderr.getvalue()
    )
    assert "redis relay status publisher http failed: owner unavailable" in (
        stderr.getvalue()
    )
    assert "skipped" not in stderr.getvalue()

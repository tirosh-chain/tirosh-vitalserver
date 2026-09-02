from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any

import pytest

from vitalserver_redis_relay.__main__ import compose_status_publisher, main
from vitalserver_redis_relay.status import FileStatusPublisher, write_status_artifact
from vitalserver_redis_relay.status_owner import (
    HttpStatusOwnerPublisher,
    UnixSocketStatusOwnerPublisher,
)
from vitalserver_redis_relay.status_publisher import (
    CompositeStatusPublisher,
    StatusPublishContractError,
    StatusPublisherConfigurationError,
    StatusPublishError,
    StatusPublishOutcome,
    StatusPublishResult,
)


class RecordingPublisher:
    def __init__(self, name: str, *, published: bool, error: str | None = None) -> None:
        self.name = name
        self._published = published
        self._error = error
        self.documents: list[dict[str, object]] = []

    def publish(self, document: dict[str, object]) -> StatusPublishResult:
        self.documents.append(document)
        return StatusPublishResult(
            outcomes=(
                StatusPublishOutcome(
                    publisher=self.name,
                    published=self._published,
                    error=self._error,
                ),
            )
        )


def test_compose_status_publisher_allows_file_only(tmp_path: Path) -> None:
    publisher = compose_status_publisher(
        status_path=tmp_path / "status.json",
        status_owner_url=None,
        status_owner_socket=None,
    )

    assert isinstance(publisher, FileStatusPublisher)
    assert publisher.path == tmp_path / "status.json"


def test_compose_status_publisher_rejects_url_and_socket(tmp_path: Path) -> None:
    with pytest.raises(
        StatusPublisherConfigurationError,
        match="status owner URL and socket cannot be configured together",
    ):
        compose_status_publisher(
            status_path=tmp_path / "status.json",
            status_owner_url="http://guest-control:18330/runtime/redis-relay/status",
            status_owner_socket=tmp_path / "owner.sock",
        )


def test_compose_status_publisher_rejects_malformed_http_url(tmp_path: Path) -> None:
    with pytest.raises(StatusPublisherConfigurationError, match="is invalid"):
        compose_status_publisher(
            status_path=tmp_path / "status.json",
            status_owner_url="not-a-url",
            status_owner_socket=None,
        )


def test_compose_status_publisher_builds_file_and_https(tmp_path: Path) -> None:
    publisher = compose_status_publisher(
        status_path=tmp_path / "status.json",
        status_owner_url="https://guest-control:18330/runtime/redis-relay/status",
        status_owner_socket=None,
    )

    assert isinstance(publisher, CompositeStatusPublisher)
    assert [type(item) for item in publisher.publishers] == [
        FileStatusPublisher,
        HttpStatusOwnerPublisher,
    ]


def test_compose_status_publisher_builds_file_and_http(tmp_path: Path) -> None:
    publisher = compose_status_publisher(
        status_path=tmp_path / "status.json",
        status_owner_url="http://guest-control:18330/runtime/redis-relay/status",
        status_owner_socket=None,
    )

    assert isinstance(publisher, CompositeStatusPublisher)
    assert [type(item) for item in publisher.publishers] == [
        FileStatusPublisher,
        HttpStatusOwnerPublisher,
    ]


def test_compose_status_publisher_builds_file_and_unix(tmp_path: Path) -> None:
    publisher = compose_status_publisher(
        status_path=tmp_path / "status.json",
        status_owner_url=None,
        status_owner_socket=tmp_path / "owner.sock",
    )

    assert isinstance(publisher, CompositeStatusPublisher)
    assert [type(item) for item in publisher.publishers] == [
        FileStatusPublisher,
        UnixSocketStatusOwnerPublisher,
    ]


def test_main_file_only_starts_without_owner_transport(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    monkeypatch.delenv("REDIS_RELAY_STATUS_OWNER_URL", raising=False)
    monkeypatch.delenv("REDIS_RELAY_STATUS_OWNER_SOCKET", raising=False)
    captured: dict[str, Any] = {}

    def fake_run_forever(**kwargs: Any) -> None:
        captured.update(kwargs)

    monkeypatch.setattr(
        "vitalserver_redis_relay.__main__.run_forever",
        fake_run_forever,
    )
    monkeypatch.setattr(
        "sys.argv",
        [
            "vitalserver-redis-relay",
            "--config-path",
            str(tmp_path / "redis-relay.toml"),
            "--status-path",
            str(tmp_path / "status.json"),
        ],
    )

    main()

    assert captured["config_path"] == tmp_path / "redis-relay.toml"
    assert isinstance(captured["status_publisher"], FileStatusPublisher)
    assert captured["status_publisher"].path == tmp_path / "status.json"


def test_main_rejects_url_and_socket_together(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    monkeypatch.delenv("REDIS_RELAY_STATUS_OWNER_URL", raising=False)
    monkeypatch.delenv("REDIS_RELAY_STATUS_OWNER_SOCKET", raising=False)
    monkeypatch.setattr(
        "sys.argv",
        [
            "vitalserver-redis-relay",
            "--config-path",
            str(tmp_path / "redis-relay.toml"),
            "--status-path",
            str(tmp_path / "status.json"),
            "--status-owner-url",
            "http://guest-control:18330/runtime/redis-relay/status",
            "--status-owner-socket",
            str(tmp_path / "owner.sock"),
        ],
    )

    with pytest.raises(SystemExit) as error:
        main()

    assert error.value.code == 2


def test_main_rejects_malformed_status_owner_url(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.delenv("REDIS_RELAY_STATUS_OWNER_URL", raising=False)
    monkeypatch.delenv("REDIS_RELAY_STATUS_OWNER_SOCKET", raising=False)
    monkeypatch.setattr(
        "sys.argv",
        [
            "vitalserver-redis-relay",
            "--config-path",
            str(tmp_path / "redis-relay.toml"),
            "--status-path",
            str(tmp_path / "status.json"),
            "--status-owner-url",
            "ftp://user:secret@example.test/status",
        ],
    )

    with pytest.raises(SystemExit) as error:
        main()

    stderr = capsys.readouterr().err
    assert error.value.code == 2
    assert "status owner URL scheme must be http or https" in stderr
    assert "secret" not in stderr
    assert "ftp://" not in stderr


def test_write_status_artifact_uses_atomic_replace(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    status_path = tmp_path / "status.json"
    replaced: list[tuple[Path, Path]] = []
    original_replace = os.replace

    def spy_replace(
        source: str | os.PathLike[str],
        dest: str | os.PathLike[str],
    ) -> None:
        source_path = Path(source)
        dest_path = Path(dest)
        replaced.append((source_path, dest_path))
        payload = source_path.read_text()
        json.loads(payload)
        assert payload.endswith("\n")
        original_replace(source, dest)

    monkeypatch.setattr("vitalserver_redis_relay.status.os.replace", spy_replace)
    document = {"state": "running", "schemaVersion": 1}

    write_status_artifact(status_path, document)

    assert replaced == [(replaced[0][0], status_path)]
    assert json.loads(status_path.read_text()) == document
    assert list(tmp_path.glob(".status.json.*.tmp")) == []


def test_file_publisher_preserves_existing_status_and_cleans_temp_on_failure(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    status_path = tmp_path / "status.json"
    original = '{"state":"running"}\n'
    status_path.write_text(original)

    def fail_replace(
        source: str | os.PathLike[str],
        dest: str | os.PathLike[str],
    ) -> None:
        del source, dest
        raise OSError("replace failed")

    monkeypatch.setattr("vitalserver_redis_relay.status.os.replace", fail_replace)
    result = FileStatusPublisher(status_path).publish({"state": "relay_failed"})

    assert result.any_published is False
    assert result.outcomes[0].publisher == "file"
    assert result.outcomes[0].error is not None
    assert "replace failed" in result.outcomes[0].error
    assert status_path.read_text() == original
    assert list(tmp_path.glob(".status.json.*.tmp")) == []


def test_file_publisher_cleans_temp_when_fsync_fails(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    status_path = tmp_path / "status.json"
    original = '{"state":"disabled"}\n'
    status_path.write_text(original)

    def fail_fsync(fd: int) -> None:
        del fd
        raise OSError("fsync failed")

    monkeypatch.setattr("vitalserver_redis_relay.status.os.fsync", fail_fsync)
    failed_document: dict[str, object] = {"state": "running"}
    result = FileStatusPublisher(status_path).publish(failed_document)

    assert result.any_published is False
    assert status_path.read_text() == original
    assert list(tmp_path.glob(".status.json.*.tmp")) == []


def test_composite_calls_remaining_publishers_after_failure() -> None:
    first = RecordingPublisher("file", published=False, error="permission denied")
    second = RecordingPublisher("http", published=True)
    document: dict[str, object] = {"state": "running"}

    result = CompositeStatusPublisher((first, second)).publish(document)

    assert first.documents == [document]
    assert second.documents == [document]
    assert result.any_published is True
    assert result.failed_outcomes() == (
        StatusPublishOutcome(
            publisher="file",
            published=False,
            error="permission denied",
        ),
    )


def test_composite_all_failures_are_explicit() -> None:
    first = RecordingPublisher("file", published=False, error="permission denied")
    second = RecordingPublisher("http", published=False, error="owner unavailable")

    document: dict[str, object] = {"state": "running"}
    result = CompositeStatusPublisher((first, second)).publish(document)

    assert result.any_published is False
    error = StatusPublishError(result)
    assert "file: permission denied" in str(error)
    assert "http: owner unavailable" in str(error)


def test_successful_outcome_rejects_error() -> None:
    with pytest.raises(
        StatusPublishContractError,
        match="must not include an error",
    ):
        StatusPublishOutcome(publisher="file", published=True, error="boom")


def test_failed_outcome_requires_non_empty_error() -> None:
    with pytest.raises(
        StatusPublishContractError,
        match="requires a non-empty error",
    ):
        StatusPublishOutcome(publisher="file", published=False, error=None)
    with pytest.raises(
        StatusPublishContractError,
        match="requires a non-empty error",
    ):
        StatusPublishOutcome(publisher="file", published=False, error="  ")


def test_result_requires_at_least_one_outcome() -> None:
    with pytest.raises(
        StatusPublishContractError,
        match="requires at least one outcome",
    ):
        StatusPublishResult(outcomes=())


def test_valid_publish_outcomes_remain_usable() -> None:
    published = StatusPublishOutcome(publisher="file", published=True)
    failed = StatusPublishOutcome(
        publisher="http",
        published=False,
        error="owner unavailable",
    )
    result = StatusPublishResult(outcomes=(published, failed))

    assert result.any_published is True
    assert result.failed_outcomes() == (failed,)


def test_composite_rejects_empty_publisher_list() -> None:
    with pytest.raises(
        StatusPublisherConfigurationError,
        match="at least one status publisher is required",
    ):
        CompositeStatusPublisher(())

from __future__ import annotations

import json
from typing import Any

from vitalserver_redis_relay.status_owner import GuestControlStatusOwnerPublisher


class FakeResponse:
    def __init__(self, status: int) -> None:
        self.status = status

    def __enter__(self) -> FakeResponse:
        return self

    def __exit__(self, *args: object) -> None:
        return None


def test_status_owner_publisher_puts_status_document(monkeypatch) -> None:
    requests: list[Any] = []

    def fake_urlopen(request, timeout: float) -> FakeResponse:
        requests.append((request, timeout))
        return FakeResponse(200)

    monkeypatch.setattr("urllib.request.urlopen", fake_urlopen)

    result = GuestControlStatusOwnerPublisher(
        owner_url="http://guest-control:18330/v1/redis-relay/status",
        timeout_seconds=2.0,
    ).publish({"observedAt": "2026-07-01T00:00:00Z", "state": "running"})

    assert result.published is True
    assert result.error is None
    request, timeout = requests[0]
    assert request.full_url == "http://guest-control:18330/v1/redis-relay/status"
    assert request.get_method() == "PUT"
    assert timeout == 2.0
    assert json.loads(request.data.decode("utf-8")) == {
        "observedAt": "2026-07-01T00:00:00Z",
        "state": "running",
    }


def test_status_owner_publisher_reports_missing_owner_url() -> None:
    result = GuestControlStatusOwnerPublisher(owner_url=None).publish(
        {"observedAt": "2026-07-01T00:00:00Z"}
    )

    assert result.published is False
    assert result.error == "Redis relay status owner URL is not configured."

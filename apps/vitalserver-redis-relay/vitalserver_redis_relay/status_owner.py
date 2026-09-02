from __future__ import annotations

import http.client
import json
import socket
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from .status_publisher import (
    StatusPublisherConfigurationError,
    StatusPublishOutcome,
    StatusPublishResult,
)

REDIS_RELAY_STATUS_OWNER_PATH = "/runtime/redis-relay/status"


class HttpStatusOwnerPublisher:
    name = "http"

    def __init__(self, *, owner_url: str, timeout_seconds: float = 3.0) -> None:
        self._owner_url = _validated_http_owner_url(owner_url)
        self._timeout_seconds = timeout_seconds

    def publish(self, document: dict[str, Any]) -> StatusPublishResult:
        payload = json.dumps(document, sort_keys=True).encode("utf-8")
        request = urllib.request.Request(
            self._owner_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="PUT",
        )
        try:
            with urllib.request.urlopen(
                request,
                timeout=self._timeout_seconds,
            ) as response:
                if response.status < 200 or response.status >= 300:
                    return _failed(
                        self.name,
                        f"status owner returned HTTP {response.status}",
                    )
        except (OSError, urllib.error.URLError) as error:
            return _failed(self.name, f"status owner publish failed: {error}")
        return _published(self.name)


class UnixSocketStatusOwnerPublisher:
    name = "unix-socket"

    def __init__(
        self,
        *,
        owner_socket_path: Path,
        timeout_seconds: float = 3.0,
    ) -> None:
        self._owner_socket_path = owner_socket_path
        self._timeout_seconds = timeout_seconds

    def publish(self, document: dict[str, Any]) -> StatusPublishResult:
        payload = json.dumps(document, sort_keys=True).encode("utf-8")
        connection = _UnixSocketHTTPConnection(
            socket_path=self._owner_socket_path,
            timeout=self._timeout_seconds,
        )
        try:
            connection.request(
                "PUT",
                REDIS_RELAY_STATUS_OWNER_PATH,
                body=payload,
                headers={"Content-Type": "application/json"},
            )
            response = connection.getresponse()
            response.read()
            if response.status < 200 or response.status >= 300:
                return _failed(
                    self.name,
                    f"status owner returned HTTP {response.status}",
                )
        except (OSError, http.client.HTTPException) as error:
            return _failed(self.name, f"status owner publish failed: {error}")
        finally:
            connection.close()
        return _published(self.name)


class _UnixSocketHTTPConnection(http.client.HTTPConnection):
    def __init__(self, *, socket_path: Path, timeout: float) -> None:
        super().__init__("localhost", timeout=timeout)
        self._socket_path = socket_path

    def connect(self) -> None:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(self.timeout)
        connection.connect(str(self._socket_path))
        self.sock = connection


def _validated_http_owner_url(url: str) -> str:
    stripped = url.strip()
    if not stripped:
        raise StatusPublisherConfigurationError("status owner URL must not be empty")
    try:
        parsed = urlparse(stripped)
    except ValueError:
        raise StatusPublisherConfigurationError("status owner URL is invalid") from None
    scheme = parsed.scheme.lower()
    if scheme not in {"http", "https"}:
        if scheme == "":
            raise StatusPublisherConfigurationError("status owner URL is invalid")
        raise StatusPublisherConfigurationError(
            "status owner URL scheme must be http or https"
        )
    if not parsed.hostname:
        raise StatusPublisherConfigurationError("status owner URL host is required")
    try:
        _ = parsed.port
    except ValueError:
        raise StatusPublisherConfigurationError(
            "status owner URL port is invalid"
        ) from None
    try:
        urllib.request.Request(stripped, method="PUT")
    except ValueError:
        raise StatusPublisherConfigurationError("status owner URL is invalid") from None
    return stripped


def _published(publisher: str) -> StatusPublishResult:
    return StatusPublishResult(
        outcomes=(StatusPublishOutcome(publisher=publisher, published=True),)
    )


def _failed(publisher: str, error: str) -> StatusPublishResult:
    return StatusPublishResult(
        outcomes=(
            StatusPublishOutcome(
                publisher=publisher,
                published=False,
                error=error,
            ),
        )
    )

from __future__ import annotations

import http.client
import json
import socket
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REDIS_RELAY_STATUS_OWNER_PATH = "/runtime/redis-relay/status"


@dataclass(frozen=True)
class StatusOwnerPublishResult:
    published: bool
    error: str | None = None


class StatusOwnerConfigurationError(RuntimeError):
    pass


class GuestControlStatusOwnerPublisher:
    def __init__(
        self,
        *,
        owner_url: str | None = None,
        owner_socket_path: Path | None = None,
        timeout_seconds: float = 3.0,
    ) -> None:
        self._owner_url = owner_url.strip() if owner_url else ""
        self._owner_socket_path = owner_socket_path
        if bool(self._owner_url) == (self._owner_socket_path is not None):
            raise StatusOwnerConfigurationError(
                "Exactly one Redis relay status owner URL or socket path is required.",
            )
        self._timeout_seconds = timeout_seconds

    def publish(self, document: dict[str, Any]) -> StatusOwnerPublishResult:
        payload = json.dumps(document, sort_keys=True).encode("utf-8")
        if self._owner_socket_path is not None:
            return self._publish_via_socket(payload)
        return self._publish_via_url(payload)

    def _publish_via_url(self, payload: bytes) -> StatusOwnerPublishResult:
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
                    return StatusOwnerPublishResult(
                        published=False,
                        error=f"status owner returned HTTP {response.status}",
                    )
        except (OSError, urllib.error.URLError) as error:
            return StatusOwnerPublishResult(
                published=False,
                error=f"status owner publish failed: {error}",
            )
        return StatusOwnerPublishResult(published=True)

    def _publish_via_socket(self, payload: bytes) -> StatusOwnerPublishResult:
        assert self._owner_socket_path is not None
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
                return StatusOwnerPublishResult(
                    published=False,
                    error=f"status owner returned HTTP {response.status}",
                )
        except (OSError, http.client.HTTPException) as error:
            return StatusOwnerPublishResult(
                published=False,
                error=f"status owner publish failed: {error}",
            )
        finally:
            connection.close()
        return StatusOwnerPublishResult(published=True)


class _UnixSocketHTTPConnection(http.client.HTTPConnection):
    def __init__(self, *, socket_path: Path, timeout: float) -> None:
        super().__init__("localhost", timeout=timeout)
        self._socket_path = socket_path

    def connect(self) -> None:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.settimeout(self.timeout)
        connection.connect(str(self._socket_path))
        self.sock = connection

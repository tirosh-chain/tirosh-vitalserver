from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class StatusOwnerPublishResult:
    published: bool
    error: str | None = None


class GuestControlStatusOwnerPublisher:
    def __init__(self, *, owner_url: str | None, timeout_seconds: float = 3.0) -> None:
        self._owner_url = owner_url.strip() if owner_url else None
        self._timeout_seconds = timeout_seconds

    def publish(self, document: dict[str, Any]) -> StatusOwnerPublishResult:
        if self._owner_url is None:
            return StatusOwnerPublishResult(
                published=False,
                error="Redis relay status owner URL is not configured.",
            )

        request = urllib.request.Request(
            self._owner_url,
            data=json.dumps(document, sort_keys=True).encode("utf-8"),
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

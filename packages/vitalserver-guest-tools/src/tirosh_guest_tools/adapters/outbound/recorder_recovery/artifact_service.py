from __future__ import annotations

import json
import os
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from tirosh_guest_tools.domain.guest_control.models import (
    RecorderRecoveryDependencyError,
)

DEFAULT_RECORDER_RECOVERY_ARTIFACTS_URL = (
    "http://127.0.0.1:18086/artifacts"
)
RECORDER_RECOVERY_ARTIFACTS_URL_ENV = (
    "TIROSH_RECORDER_RECOVERY_ARTIFACTS_URL"
)


class RecorderRecoveryArtifactServiceAdapter:
    def __init__(
        self,
        *,
        artifacts_url: str | None = None,
        timeout_seconds: float = 5.0,
    ) -> None:
        self._artifacts_url = artifacts_url or os.environ.get(
            RECORDER_RECOVERY_ARTIFACTS_URL_ENV,
            DEFAULT_RECORDER_RECOVERY_ARTIFACTS_URL,
        )
        self._timeout_seconds = timeout_seconds

    def list_artifacts(self) -> dict[str, Any]:
        request = Request(
            self._artifacts_url,
            method="GET",
            headers={"Accept": "application/json"},
        )
        try:
            with urlopen(request, timeout=self._timeout_seconds) as response:
                data = response.read()
        except HTTPError as error:
            raise RecorderRecoveryDependencyError(
                f"Recorder recovery artifact request failed: status={error.code}",
                kind="recorder-recovery-http-error",
            ) from error
        except URLError as error:
            raise RecorderRecoveryDependencyError(
                f"Recorder recovery artifacts are unavailable: {error.reason}",
                kind="recorder-recovery-unavailable",
            ) from error
        except TimeoutError as error:
            raise RecorderRecoveryDependencyError(
                "Recorder recovery artifact request timed out.",
                kind="recorder-recovery-timeout",
            ) from error

        try:
            document = json.loads(data.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise RecorderRecoveryDependencyError(
                f"Recorder recovery artifacts returned invalid JSON: {error}",
                kind="recorder-recovery-contract-invalid",
            ) from error
        if not isinstance(document, dict) or not isinstance(
            document.get("artifacts"), list
        ):
            raise RecorderRecoveryDependencyError(
                "Recorder recovery artifacts response is invalid.",
                kind="recorder-recovery-contract-invalid",
            )
        return {
            "state": "loaded",
            "artifacts": document["artifacts"],
            "readError": None,
        }

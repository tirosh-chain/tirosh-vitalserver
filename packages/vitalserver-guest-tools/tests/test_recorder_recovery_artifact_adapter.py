from __future__ import annotations

from typing import Any

from tirosh_guest_tools.adapters.outbound.recorder_recovery import artifact_service
from tirosh_guest_tools.adapters.outbound.recorder_recovery.artifact_service import (
    RecorderRecoveryArtifactServiceAdapter,
)


def test_recorder_recovery_adapter_wraps_owner_artifact_collection(
    monkeypatch: Any,
) -> None:
    requests: list[str] = []

    class Response:
        def __enter__(self) -> Response:
            return self

        def __exit__(self, *args: object) -> None:
            del args

        def read(self) -> bytes:
            return b'{"artifacts":[{"publishState":"published"}]}'

    def fake_urlopen(request: Any, *, timeout: float) -> Response:
        assert timeout == 5.0
        requests.append(request.full_url)
        return Response()

    monkeypatch.setattr(artifact_service, "urlopen", fake_urlopen)

    result = RecorderRecoveryArtifactServiceAdapter(
        artifacts_url="http://recorder-recovery:8080/artifacts"
    ).list_artifacts()

    assert requests == ["http://recorder-recovery:8080/artifacts"]
    assert result == {
        "state": "loaded",
        "artifacts": [{"publishState": "published"}],
        "readError": None,
    }

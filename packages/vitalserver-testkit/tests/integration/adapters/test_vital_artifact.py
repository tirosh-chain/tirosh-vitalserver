from __future__ import annotations

from pathlib import Path

from tests.support import fake_socketio_connector
from tirosh_vitalserver.testkit.adapters.outbound.vital_artifact import (
    VitalDbSessionVitalFileExporter,
)
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionState,
)


def test_session_vital_export_writes_vitaldb_readable_file(tmp_path: Path) -> None:
    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        vital_file_exporter=VitalDbSessionVitalFileExporter(tmp_path),
    )
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url="http://example.test",
            vrcode="VR_FILE",
            bed_room_names=("OR-A",),
            interval_seconds=0.1,
            max_messages=2,
            shift_time=False,
            export_vital=True,
        )
    )

    assert manager.wait_session(snapshot.session_id, timeout=30)
    exported = manager.get_session(snapshot.session_id)

    assert exported is not None
    assert exported.state == VirtualRecorderSessionState.VITAL_READY
    assert exported.vital_state.artifact is not None

    from vitaldb import VitalFile

    vital_file = VitalFile(exported.vital_state.artifact.path, header_only=True)

    assert vital_file.dtstart > 0
    assert vital_file.dtend >= vital_file.dtstart
    assert "TestKit/METADATA" in vital_file.get_track_names()
    assert any(
        track_name.endswith("/HR")
        for track_name in vital_file.get_track_names()
    )

from __future__ import annotations

import gzip
import json
import os
import struct
import time
from collections.abc import Iterator
from contextlib import contextmanager
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
from typing import ClassVar, cast

import pytest

from tests.support import fake_socketio_connector
from tirosh_vitalserver.testkit.adapters.outbound.vital_artifact import (
    VitalDbSessionVitalFileExporter,
    VitalServerSessionVitalFileUploader,
    playback_bed_room_name,
)
from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.recorder_session import (
    RecorderSessionOutput,
    RecorderTestScenario,
    SessionRecorderPlayback,
    SessionVitalPlayback,
    VirtualRecorderSessionManager,
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionState,
)
from tirosh_vitalserver.testkit.application.recorder_session.recording import (
    SessionPlaybackEvent,
    SessionPlaybackEventType,
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
            bedroom_name="OR-A",
            interval_seconds=0.1,
            max_messages=2,
            shift_time=False,
            output=RecorderSessionOutput(export_vital=True),
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
    legacy_dtstart, legacy_dtend = legacy_vitalserver_dt_range(
        Path(exported.vital_state.artifact.path)
    )
    assert legacy_dtstart > 0
    assert legacy_dtend >= legacy_dtstart

    webview_dtstart, webview_dtend, webview_tracks = (
        legacy_vitalserver_webview_preview(Path(exported.vital_state.artifact.path))
    )
    assert webview_dtstart > 0
    assert webview_dtend >= webview_dtstart
    assert any(
        track.dname == "OR-A_Demo" and track.records > 0
        for track in webview_tracks
    )
    assert any(
        track.dname == "OR-A_Lab" and track.tname == "HCT" and track.records > 0
        for track in webview_tracks
    )

    montypes = {track.tname: track.montype for track in webview_tracks}
    assert montypes["ECG"] == 1
    assert montypes["HR"] == 2
    assert montypes["ART"] == 4
    assert montypes["ART_SBP"] == 5
    assert montypes["ART_DBP"] == 6
    assert montypes["ART_MBP"] == 7
    assert montypes["PLETH"] == 8
    assert montypes["PLETH_SPO2"] == 10
    assert montypes["CO2"] == 13
    assert montypes["RR"] == 14
    assert montypes["ETCO2"] == 15
    assert montypes["HCT"] == 0


def test_session_vital_export_uploads_to_vitalserver_success_response(
    tmp_path: Path,
) -> None:
    with vital_upload_http_server(response_body=b"success") as server:
        manager = VirtualRecorderSessionManager(
            connector=fake_socketio_connector,
            vital_file_exporter=VitalDbSessionVitalFileExporter(tmp_path),
            vital_file_uploader=VitalServerSessionVitalFileUploader(),
        )
        snapshot = manager.start_session(
            VirtualRecorderSessionRequest(
                target_url=server_url(server),
                vrcode="VR_UPLOAD",
                bedroom_name="OR-A",
                recorders=2,
                interval_seconds=0.1,
                max_messages=2,
                shift_time=False,
                output=RecorderSessionOutput(
                    export_vital=True,
                    upload_vital=True,
                ),
            )
        )

        assert manager.wait_session(snapshot.session_id, timeout=30)
        uploaded = manager.get_session(snapshot.session_id)

    assert uploaded is not None
    assert uploaded.state == VirtualRecorderSessionState.UPLOADED
    assert uploaded.vital_state.artifact is not None
    assert uploaded.vital_state.artifact.filename.startswith("OR-A_")
    assert uploaded.vital_state.upload_result is not None
    assert uploaded.vital_state.upload_result.response_text == "success"
    assert uploaded.vital_state.upload_error is None

    assert len(VitalUploadHttpHandler.requests) == 1
    path, content_type, content_length, body = VitalUploadHttpHandler.requests[0]
    assert path == "/upload"
    assert content_type.startswith("multipart/form-data; boundary=")
    assert content_length == len(body)
    assert b'name="vitalfile"; filename="OR-A_' in body
    assert b".vital" in body


def test_session_vital_upload_requires_vitalserver_success_body(
    tmp_path: Path,
) -> None:
    with vital_upload_http_server(response_body=b"parser failed") as server:
        manager = VirtualRecorderSessionManager(
            connector=fake_socketio_connector,
            vital_file_exporter=VitalDbSessionVitalFileExporter(tmp_path),
            vital_file_uploader=VitalServerSessionVitalFileUploader(),
        )
        snapshot = manager.start_session(
            VirtualRecorderSessionRequest(
                target_url=server_url(server),
                vrcode="VR_UPLOAD_FAIL",
                bedroom_name="OR-A",
                interval_seconds=0.1,
                max_messages=2,
                shift_time=False,
                output=RecorderSessionOutput(
                    export_vital=True,
                    upload_vital=True,
                ),
            )
        )

        assert manager.wait_session(snapshot.session_id, timeout=30)
        failed = manager.get_session(snapshot.session_id)

    assert failed is not None
    assert failed.state == VirtualRecorderSessionState.UPLOAD_FAILED
    assert failed.vital_state.artifact is not None
    assert failed.vital_state.upload_result is not None
    assert failed.vital_state.upload_result.ok is False
    assert failed.vital_state.upload_error == "parser failed"


def test_session_vital_filename_uses_playback_room_name() -> None:
    playback = SessionVitalPlayback(
        recorders=(
            SessionRecorderPlayback(
                vrcode="VR_REAL",
                payload={
                    "rooms": {
                        "internal-key": {
                            "roomname": "Attached OR",
                            "trks": [],
                        }
                    }
                },
                messages_sent=1,
            ),
        ),
        events=(
            SessionPlaybackEvent(type=SessionPlaybackEventType.STARTED, at=1000.0),
            SessionPlaybackEvent(type=SessionPlaybackEventType.STOPPED, at=1001.0),
        ),
        started_at=1000.0,
        stopped_at=1001.0,
        interval_seconds=1.0,
        generate_frames=False,
        scenario=RecorderTestScenario.NORMAL_MONITORING,
    )

    assert playback_bed_room_name(playback) == "Attached OR"


@pytest.mark.skipif(
    not os.environ.get("VITALSERVER_TEST_URL"),
    reason="set VITALSERVER_TEST_URL to run against a live VitalServer",
)
def test_session_vital_upload_is_visible_in_live_vitalserver_filelist(
    tmp_path: Path,
) -> None:
    target_url = os.environ["VITALSERVER_TEST_URL"]
    user_id = os.environ.get("VITALSERVER_TEST_USER", "admin")
    password = os.environ.get("VITALSERVER_TEST_PASSWORD", "admin")
    bed_name = f"TESTKITLIVE{int(time.time())}"

    manager = VirtualRecorderSessionManager(
        connector=fake_socketio_connector,
        vital_file_exporter=VitalDbSessionVitalFileExporter(tmp_path),
        vital_file_uploader=VitalServerSessionVitalFileUploader(),
    )
    snapshot = manager.start_session(
        VirtualRecorderSessionRequest(
            target_url=target_url,
            vrcode=f"VR_{bed_name}",
            bedroom_name=bed_name,
            interval_seconds=0.1,
            max_messages=2,
            shift_time=False,
            output=RecorderSessionOutput(
                export_vital=True,
                upload_vital=True,
            ),
        )
    )

    assert manager.wait_session(snapshot.session_id, timeout=30)
    uploaded = manager.get_session(snapshot.session_id)

    assert uploaded is not None
    assert uploaded.state == VirtualRecorderSessionState.UPLOADED
    assert uploaded.vital_state.artifact is not None

    client = VitalServerClient(target_url)
    access_token = live_vitalserver_access_token(client, user_id, password)
    file_records = live_vitalserver_file_records(
        client,
        access_token,
        bed_name=bed_name,
    )

    uploaded_records = tuple(
        record
        for record in file_records
        if record["filename"] == uploaded.vital_state.artifact.filename
    )
    assert len(uploaded_records) == 1
    dtstart = uploaded_records[0]["dtstart"]
    dtend = uploaded_records[0]["dtend"]
    assert isinstance(dtstart, int | float)
    assert isinstance(dtend, int | float)
    assert dtstart > 0
    assert dtend >= dtstart


class VitalUploadHttpHandler(BaseHTTPRequestHandler):
    requests: ClassVar[list[tuple[str, str, int, bytes]]] = []
    response_body: ClassVar[bytes] = b"success"

    def do_POST(self) -> None:
        content_length = int(self.headers["Content-Length"])
        body = self.rfile.read(content_length)
        VitalUploadHttpHandler.requests.append(
            (
                self.path,
                self.headers["Content-Type"],
                content_length,
                body,
            )
        )

        self.send_response(200)
        self.end_headers()
        self.wfile.write(self.response_body)

    def log_message(self, format: str, *args: object) -> None:
        return


@dataclass(frozen=True)
class LegacyWebviewTrack:
    dname: str
    tname: str
    montype: int
    records: int


@contextmanager
def vital_upload_http_server(
    *,
    response_body: bytes,
) -> Iterator[ThreadingHTTPServer]:
    VitalUploadHttpHandler.requests = []
    VitalUploadHttpHandler.response_body = response_body
    server = ThreadingHTTPServer(("127.0.0.1", 0), VitalUploadHttpHandler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        yield server
    finally:
        server.shutdown()
        thread.join(timeout=5)


def server_url(server: ThreadingHTTPServer) -> str:
    host, port = cast(tuple[str, int], server.server_address)

    return f"http://{host}:{port}"


def live_vitalserver_access_token(
    client: VitalServerClient,
    user_id: str,
    password: str,
) -> str:
    response = client.login(user_id, password)
    assert response.ok, response.text
    payload = json.loads(response.text)
    assert payload["res"] is True

    return str(payload["access_token"])


def live_vitalserver_file_records(
    client: VitalServerClient,
    access_token: str,
    *,
    bed_name: str,
) -> tuple[dict[str, object], ...]:
    response = client.filelist(
        access_token,
        bedname=bed_name,
        unixtimestamp="1",
    )
    assert response.ok, response.text

    payload = json.loads(gzip.decompress(response.body).decode("utf-8"))

    return tuple(cast(dict[str, object], record) for record in payload)


def legacy_vitalserver_dt_range(path: Path) -> tuple[float, float]:
    """Return the dt range as parsed by bundled VitalServer's old JS reader."""

    payload = gzip.decompress(path.read_bytes())
    assert payload[:4] == b"VITA"
    assert int.from_bytes(payload[8:10], byteorder="little") == 10

    offset = 20
    dtstart = 0.0
    dtend = 0.0
    while offset + 5 <= len(payload):
        packet_type = payload[offset]
        packet_len = int.from_bytes(
            payload[offset + 1 : offset + 5],
            byteorder="little",
        )
        assert packet_type in {0, 1, 6, 9}
        packet = payload[offset + 5 : offset + 5 + packet_len]
        assert len(packet) == packet_len

        if packet_type == 1:
            assert len(packet) >= 12
            dt = struct.unpack_from("<d", packet, 2)[0]
            if dtstart == 0.0 or (dt > 0 and dt < dtstart):
                dtstart = dt
            if dt > dtend:
                dtend = dt

        offset += 5 + packet_len

    return dtstart, dtend


def legacy_vitalserver_webview_preview(
    path: Path,
) -> tuple[float, float, tuple[LegacyWebviewTrack, ...]]:
    """Return tracks as parsed by bundled VitalServer's webview reader."""

    payload = gzip.decompress(path.read_bytes())
    assert payload[:4] == b"VITA"
    assert int.from_bytes(payload[8:10], byteorder="little") == 10

    devs: dict[int, str] = {}
    tracks: dict[int, tuple[int, str, int]] = {}
    tid_to_did: dict[int, int] = {}
    offset = 20
    while offset + 5 <= len(payload):
        packet_type = payload[offset]
        packet_len = int.from_bytes(
            payload[offset + 1 : offset + 5],
            byteorder="little",
        )
        packet = payload[offset + 5 : offset + 5 + packet_len]
        assert len(packet) == packet_len

        if packet_type == 9:
            did, dname = legacy_vitalserver_device(packet)
            devs[did] = dname
        elif packet_type == 0:
            tid, did, tname, montype = legacy_vitalserver_track(packet)
            tracks[tid] = (did, tname, montype)
            tid_to_did[tid] = did

        offset += 5 + packet_len

    dtstart = 0.0
    dtend = 0.0
    records_by_tid: dict[int, int] = {}
    offset = 20
    while offset + 5 <= len(payload):
        packet_type = payload[offset]
        packet_len = int.from_bytes(
            payload[offset + 1 : offset + 5],
            byteorder="little",
        )
        packet = payload[offset + 5 : offset + 5 + packet_len]

        if packet_type == 1:
            assert len(packet) >= 12
            dt = struct.unpack_from("<d", packet, 2)[0]
            tid = struct.unpack_from("<h", packet, 10)[0]
            if tid in tid_to_did and dt > 0:
                records_by_tid[tid] = records_by_tid.get(tid, 0) + 1
                if dtstart == 0.0 or dt < dtstart:
                    dtstart = dt
                if dt > dtend:
                    dtend = dt

        offset += 5 + packet_len

    webview_tracks = tuple(
        LegacyWebviewTrack(
            dname=devs[did],
            tname=tname,
            montype=montype,
            records=records_by_tid.get(tid, 0),
        )
        for tid, (did, tname, montype) in sorted(tracks.items())
        if devs.get(did)
    )

    return dtstart, dtend, webview_tracks


def legacy_vitalserver_device(packet: bytes) -> tuple[int, str]:
    offset = 0
    did = struct.unpack_from("<i", packet, offset)[0]
    offset += 4

    dtype_len = struct.unpack_from("<i", packet, offset)[0]
    offset += 4 + dtype_len

    dname_len = struct.unpack_from("<i", packet, offset)[0]
    offset += 4
    dname = packet[offset : offset + dname_len].decode("ascii")

    return did, dname


def legacy_vitalserver_track(packet: bytes) -> tuple[int, int, str, int]:
    offset = 0
    tid = struct.unpack_from("<h", packet, offset)[0]
    offset += 2
    offset += 1
    offset += 1

    tname_len = struct.unpack_from("<i", packet, offset)[0]
    offset += 4
    tname = packet[offset : offset + tname_len].decode("ascii")
    offset += tname_len

    unit_len = struct.unpack_from("<i", packet, offset)[0]
    offset += 4 + unit_len
    offset += 4
    offset += 4
    offset += 4
    offset += 4
    offset += 8
    offset += 8

    montype = packet[offset]
    offset += 1
    did = struct.unpack_from("<i", packet, offset)[0]

    return tid, did, tname, montype

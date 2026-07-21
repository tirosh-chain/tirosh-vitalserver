from __future__ import annotations

import json
import re
import sys
import time
import zlib
from pathlib import Path
from typing import Any

import pytest

from vitalserver_lab.archive_finalization import (
    LabArchiveFinalizationError,
    LabArchiveFinalizationProgress,
    LabArchiveFinalizationReceipt,
)
from vitalserver_lab.execution import (
    LabExecutionEngine,
    LabRecorderSendError,
    LabRecorderSendReceipt,
    VitalServerRecorderPayloadSender,
)
from vitalserver_lab.model import (
    DEFAULT_SCENARIOS,
    InMemoryLabSessionStore,
    LabBed,
    LabRecorder,
    LabSessionStore,
    LabSessionStoreUnavailable,
)
from vitalserver_lab.server import (
    build_execution_engine,
    build_session_store,
    route_lab_request,
)
from vitalserver_lab.settings import (
    LabSettings,
    LabSettingsConfigurationError,
    load_settings,
)
from vitalserver_lab.vital_replay import (
    LabVitalReplayFrame,
    VitalReplaySourceError,
)


def test_health_and_ready_are_explicit() -> None:
    with running_server() as address:
        health = request(address, "GET", "/health")
        ready = request(address, "GET", "/ready")

    assert health["status"] == 200
    assert health["body"]["status"] == "ok"
    assert ready["status"] == 200
    assert ready["body"]["ready"] is True
    assert ready["body"]["service"] == "vitalserver-lab"
    assert ready["body"]["dependency"] == "lab-session-store"
    assert ready["body"]["readError"] is None


def test_ready_reports_session_store_unavailable() -> None:
    settings = LabSettings(
        host="127.0.0.1",
        port=0,
        service_name="vitalserver-lab",
        session_store="memory",
        allow_memory_store=True,
        database_url=None,
        vital_files_mount=Path("/mnt/tirosh-vital-files"),
    )
    store = UnavailableStore()

    status, body = route_lab_request(
        method="GET",
        path="/ready",
        body=b"",
        settings=settings,
        scenarios=DEFAULT_SCENARIOS,
        session_store=store,
        execution_engine=LabExecutionEngine(sender=FakeSender()),
    )

    assert status.value == 503
    assert body["ready"] is False
    assert body["dependency"] == "lab-session-store"
    assert body["readError"] == "lab session store is unavailable"


def test_memory_session_store_requires_explicit_dev_override() -> None:
    settings = LabSettings(
        host="127.0.0.1",
        port=0,
        service_name="vitalserver-lab",
        session_store="memory",
        allow_memory_store=False,
        database_url=None,
        vital_files_mount=Path("/mnt/tirosh-vital-files"),
    )

    with pytest.raises(LabSessionStoreUnavailable) as error:
        build_session_store(settings)

    assert error.value.kind == "labSessionStoreConfigurationInvalid"
    assert "VITALSERVER_LAB_ALLOW_MEMORY_STORE" in error.value.message


def test_load_settings_reports_invalid_port_configuration(monkeypatch: Any) -> None:
    monkeypatch.setenv("VITALSERVER_LAB_PORT", "not-a-port")

    with pytest.raises(LabSettingsConfigurationError) as error:
        load_settings()

    assert error.value.kind == "labSettingsInvalidInteger"
    assert error.value.message == "VITALSERVER_LAB_PORT must be an integer."


def test_build_execution_engine_uses_socketio_sender() -> None:
    settings = load_settings()
    settings = LabSettings(
        host=settings.host,
        port=settings.port,
        service_name=settings.service_name,
        session_store=settings.session_store,
        allow_memory_store=True,
        database_url=None,
        vital_files_mount=settings.vital_files_mount,
    )
    engine = build_execution_engine(settings=settings)

    assert isinstance(engine.sender, VitalServerRecorderPayloadSender)


def test_socketio_payload_sender_reuses_recorder_connection_until_closed(
    monkeypatch: Any,
) -> None:
    client = FakeSocketIOClient()
    monkeypatch.setitem(sys.modules, "socketio", FakeSocketIOModule(client))
    sender = VitalServerRecorderPayloadSender(timeout_seconds=1)

    first_receipt = sender.send(
        target_url="http://edge/",
        payload={
            "vrcode": "LAB-VR-1",
            "ver": "vitalserver-lab",
            "rooms": {"OR-A": {"roomname": "OR-A"}},
        },
    )
    second_receipt = sender.send(
        target_url="http://edge/",
        payload={
            "vrcode": "LAB-VR-1",
            "ver": "vitalserver-lab",
            "rooms": {"OR-A": {"roomname": "OR-A", "seqid": 2}},
        },
    )

    assert first_receipt.transport == "socket.io"
    assert first_receipt.bytes_sent > 0
    assert second_receipt.bytes_sent > 0
    assert client.connected_url == "http://edge/"
    assert client.connect_count == 1
    assert client.emitted[0] == ("join_vr", "LAB-VR-1")
    event, encoded = client.emitted[1]
    assert event == "send_data"
    decoded = json.loads(zlib.decompress(encoded))
    assert decoded["vrcode"] == "LAB-VR-1"
    assert decoded["rooms"] == {"OR-A": {"roomname": "OR-A"}}
    assert [event for event, _ in client.emitted] == [
        "join_vr",
        "send_data",
        "send_data",
    ]
    assert client.disconnected is False

    client.connected = False
    sender.send(
        target_url="http://edge/",
        payload={
            "vrcode": "LAB-VR-1",
            "ver": "vitalserver-lab",
            "rooms": {"OR-A": {"roomname": "OR-A", "seqid": 3}},
        },
    )

    assert client.connect_count == 2
    assert client.emitted[-2] == ("join_vr", "LAB-VR-1")
    assert client.emitted[-1][0] == "send_data"

    sender.close_recorder(target_url="http://edge/", vrcode="LAB-VR-1")

    assert client.disconnected is True


def test_load_settings_reports_non_positive_port_configuration(
    monkeypatch: Any,
) -> None:
    monkeypatch.setenv("VITALSERVER_LAB_PORT", "0")

    with pytest.raises(LabSettingsConfigurationError) as error:
        load_settings()

    assert error.value.kind == "labSettingsInvalidInteger"
    assert error.value.message == "VITALSERVER_LAB_PORT must be greater than zero."


def test_scenarios_are_served_from_lab_product_api() -> None:
    with running_server() as address:
        response = request(address, "GET", "/lab/scenarios")

    assert response["status"] == 200
    assert response["body"]["state"] == "loaded"
    assert response["body"]["readError"] is None
    scenario_ids = [
        scenario["scenarioId"] for scenario in response["body"]["scenarios"]
    ]
    assert scenario_ids == [
        "baseline-monitoring",
        "postoperative-recovery",
        "hypotension-episode",
        "hypertension-episode",
        "tachycardia-response",
        "bradycardia-response",
        "desaturation-event",
        "respiratory-variation",
        "fever-trend",
        "arrhythmia-like-variation",
        "vital-file-replay",
    ]


def test_vital_files_are_served_from_configured_mount(tmp_path: Path) -> None:
    nested = tmp_path / "MORA04" / "202301"
    nested.mkdir(parents=True)
    vital_file = nested / "sample.vital"
    vital_file.write_bytes(b"vital")
    (nested / "ignore.txt").write_text("not vital", encoding="utf-8")

    with running_server(vital_files_mount=tmp_path) as address:
        response = request(address, "GET", "/lab/vital-files")

    assert response["status"] == 200
    assert response["body"]["state"] == "loaded"
    assert response["body"]["readError"] is None
    assert response["body"]["vitalFiles"] == [
        {
            "displayName": "sample.vital",
            "relativePath": "MORA04/202301/sample.vital",
            "guestPath": str(vital_file),
            "sizeBytes": 5,
            "modifiedAt": response["body"]["vitalFiles"][0]["modifiedAt"],
        }
    ]


def test_lab_vital_files_report_mount_missing(tmp_path: Path) -> None:
    missing_mount = tmp_path / "missing"
    with running_server(vital_files_mount=missing_mount) as address:
        response = request(address, "GET", "/lab/vital-files")

    assert response["status"] == 404
    assert response["body"]["state"] == "failed"
    assert response["body"]["vitalFiles"] == []
    assert (
        response["body"]["readError"]
        == "Configured vital files mount is not available."
    )


def test_create_session_returns_product_lab_session() -> None:
    with running_server() as address:
        response = request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Morning lab run",
                "recorderCount": 2,
                "targetURL": "http://edge/",
                "bedRoomNames": ["OR-A", "OR-B"],
            },
        )

    assert response["status"] == 202
    assert response["body"]["state"] == "loaded"
    assert response["body"]["operationId"] == "lab-session-create-lab_session_1"
    assert response["body"]["session"] == {
        "sessionId": "lab_session_1",
        "scenarioId": "baseline-monitoring",
        "name": "Morning lab run",
        "recorderCount": 2,
        "targetURL": "http://edge/",
        "bedRoomNames": ["OR-A", "OR-B"],
        "bedIds": [],
        "state": "accepted",
        "createdAt": response["body"]["session"]["createdAt"],
        "updatedAt": response["body"]["session"]["updatedAt"],
    }


def test_session_lifecycle_is_served_by_lab_product_api() -> None:
    with running_server(["lab_session_1"]) as address:
        created = request(
            address,
            "POST",
            "/lab/sessions",
            {"scenarioId": "baseline-monitoring", "recorderCount": 1},
        )
        loaded = request(address, "GET", "/lab/sessions/lab_session_1")
        started = request(address, "POST", "/lab/sessions/lab_session_1/start")
        stopped = request(address, "POST", "/lab/sessions/lab_session_1/stop")

    assert created["status"] == 202
    assert loaded["status"] == 200
    assert loaded["body"]["state"] == "loaded"
    assert loaded["body"]["operationId"] is None
    assert loaded["body"]["session"]["state"] == "accepted"
    assert started["status"] == 202
    assert started["body"]["operationId"] == "lab-session-start-lab_session_1"
    assert started["body"]["session"]["state"] == "running"
    assert stopped["status"] == 202
    assert stopped["body"]["operationId"] == "lab-session-stop-lab_session_1"
    assert stopped["body"]["session"]["state"] == "stopped"


def test_lab_sessions_are_listed_after_creation() -> None:
    with running_server(["lab_session_1", "lab_session_2"]) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {"scenarioId": "baseline-monitoring", "name": "First"},
        )
        request(
            address,
            "POST",
            "/lab/sessions",
            {"scenarioId": "baseline-monitoring", "name": "Second"},
        )
        response = request(address, "GET", "/lab/sessions")

    assert response["status"] == 200
    assert response["body"]["state"] == "loaded"
    assert response["body"]["readError"] is None
    assert {session["sessionId"] for session in response["body"]["sessions"]} == {
        "lab_session_1",
        "lab_session_2",
    }


def test_running_session_delete_stops_execution_and_removes_owned_read_models() -> None:
    sender = FakeSender()
    with running_server(
        ["lab_session_1"],
        sender=sender,
        frame_interval_seconds=0.01,
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Delete aggregate",
                "recorderCount": 1,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")
        recorder = address.store.list_recorders()[0]

        deleted = request(
            address,
            "POST",
            "/lab/sessions/lab_session_1/delete",
        )
        sessions = request(address, "GET", "/lab/sessions")
        beds = request(address, "GET", "/lab/beds")
        recorders = request(address, "GET", "/lab/recorders")

    assert deleted["status"] == 202
    assert deleted["body"] == {
        "state": "loaded",
        "sessions": [],
        "readError": None,
    }
    assert sessions["body"]["sessions"] == []
    assert beds["body"]["beds"] == []
    assert recorders["body"]["recorders"] == []
    assert ("http://edge/", recorder.vrcode) in sender.closed_recorders


def test_running_session_recorders_can_be_stopped_and_started_individually() -> None:
    sender = FakeSender()
    with running_server(
        ["lab_session_1"],
        sender=sender,
        frame_interval_seconds=0.01,
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Recorder control",
                "recorderCount": 2,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")
        recorders = request(address, "GET", "/lab/recorders")["body"]["recorders"]
        recorder = recorders[0]
        recorder_id = recorder["recorderId"]
        vrcode = recorder["vrcode"]
        session_case_started_at = next(
            next(iter(call["payload"]["rooms"].values()))["dtcase"]
            for call in sender.calls
            if call["payload"]["vrcode"] == vrcode
        )

        stopped = request(
            address,
            "POST",
            f"/lab/sessions/lab_session_1/recorders/{recorder_id}/stop",
        )
        sender.calls.clear()
        time.sleep(0.04)
        calls_while_stopped = list(sender.calls)

        started = request(
            address,
            "POST",
            f"/lab/sessions/lab_session_1/recorders/{recorder_id}/start",
        )
        time.sleep(0.02)
        restarted_case_started_at = next(
            next(iter(call["payload"]["rooms"].values()))["dtcase"]
            for call in sender.calls
            if call["payload"]["vrcode"] == vrcode
        )

    assert stopped["status"] == 202
    assert stopped["body"]["recorder"]["state"] == "stopped"
    assert ("http://edge/", vrcode) in sender.closed_recorders
    assert all(call["payload"]["vrcode"] != vrcode for call in calls_while_stopped)
    assert started["status"] == 202
    assert started["body"]["recorder"]["state"] == "running"
    assert any(call["payload"]["vrcode"] == vrcode for call in sender.calls)
    assert restarted_case_started_at == session_case_started_at


def test_running_recorder_can_be_stopped_when_session_state_is_inconsistent() -> None:
    sender = FakeSender()
    with running_server(["lab_session_1"], sender=sender) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Recorder recovery",
                "recorderCount": 1,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")
        recorder = address.store.list_recorders()[0]
        session = address.store.get("lab_session_1")
        assert session is not None
        session.state = "accepted"

        stopped = request(
            address,
            "POST",
            f"/lab/sessions/lab_session_1/recorders/{recorder.recorder_id}/stop",
        )

    assert stopped["status"] == 202
    assert stopped["body"]["recorder"]["state"] == "stopped"
    assert ("http://edge/", recorder.vrcode) in sender.closed_recorders


def test_lab_beds_and_recorders_are_served_from_product_read_model() -> None:
    with running_server(["lab_session_1"]) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Recovery",
                "recorderCount": 2,
                "bedRoomNames": ["OR-A", "OR-B"],
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")
        beds = request(address, "GET", "/lab/beds")
        recorders = request(address, "GET", "/lab/recorders")

    assert beds["status"] == 200
    assert beds["body"]["state"] == "loaded"
    assert beds["body"]["readError"] is None
    assert [bed["name"] for bed in beds["body"]["beds"]] == ["OR-A", "OR-B"]
    assert [bed["state"] for bed in beds["body"]["beds"]] == ["running", "running"]
    assert recorders["status"] == 200
    assert recorders["body"]["state"] == "loaded"
    assert [recorder["bedId"] for recorder in recorders["body"]["recorders"]] == [
        bed["bedId"] for bed in beds["body"]["beds"]
    ]
    assert [recorder["state"] for recorder in recorders["body"]["recorders"]] == [
        "running",
        "running",
    ]
    assert [
        recorder["lastSendState"] for recorder in recorders["body"]["recorders"]
    ] == [
        "skipped",
        "skipped",
    ]
    assert [
        recorder["lastSendError"] for recorder in recorders["body"]["recorders"]
    ] == [
        "targetURL is not configured",
        "targetURL is not configured",
    ]


def test_lab_bed_management_creates_and_deletes_product_read_model() -> None:
    with running_server(["manual_session_1"]) as address:
        created = request(
            address,
            "POST",
            "/lab/beds/create",
            {
                "roomNames": ["Lab-A", "Lab-B"],
                "prefix": "Manual lab",
            },
        )
        created_bed_id = created["body"]["beds"][0]["bedId"]
        deleted = request(
            address,
            "POST",
            "/lab/beds/delete",
            {"bedIds": [created_bed_id]},
        )
        recorders = request(address, "GET", "/lab/recorders")

    assert created["status"] == 202
    assert [bed["name"] for bed in created["body"]["beds"]] == ["Lab-A", "Lab-B"]
    assert recorders["status"] == 200
    assert recorders["body"]["recorders"] == []
    assert deleted["status"] == 202
    assert [bed["name"] for bed in deleted["body"]["beds"]] == ["Lab-B"]


def test_lab_bed_management_reset_removes_beds_and_attached_recorders() -> None:
    with running_server(["manual_session_1"]) as address:
        request(
            address,
            "POST",
            "/lab/beds/create",
            {"roomNames": ["Lab-A", "Lab-B"]},
        )
        reset = request(address, "POST", "/lab/beds/reset")
        recorders = request(address, "GET", "/lab/recorders")

    assert reset["status"] == 202
    assert reset["body"]["beds"] == []
    assert recorders["body"]["recorders"] == []


def test_lab_session_create_can_occupy_existing_lab_bed_and_recorder() -> None:
    with running_server(["manual_session_1", "lab_session_2"]) as address:
        beds_created = request(
            address,
            "POST",
            "/lab/beds/create",
            {"roomNames": ["Lab-A"]},
        )
        bed_id = beds_created["body"]["beds"][0]["bedId"]
        request(
            address,
            "POST",
            "/lab/recorders/create",
            {"bedIds": [bed_id]},
        )
        created = request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Occupy existing bed",
                "bedIds": [bed_id],
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_2/start")
        beds = request(address, "GET", "/lab/beds")
        recorders = request(address, "GET", "/lab/recorders")

    assert created["status"] == 202
    assert created["body"]["session"]["recorderCount"] == 1
    assert created["body"]["session"]["bedRoomNames"] == ["Lab-A"]
    assert created["body"]["session"]["bedIds"] == [bed_id]
    assert beds["body"]["beds"] == [
        {
            "bedId": bed_id,
            "sessionId": "lab_session_2",
            "name": "Lab-A",
            "state": "running",
            "createdAt": beds["body"]["beds"][0]["createdAt"],
            "updatedAt": beds["body"]["beds"][0]["updatedAt"],
        }
    ]
    assert re.fullmatch(
        r"rec_[A-Z0-9]{6}", recorders["body"]["recorders"][0]["recorderId"]
    )
    assert recorders["body"]["recorders"][0]["sessionId"] == "lab_session_2"
    assert recorders["body"]["recorders"][0]["bedId"] == bed_id
    assert recorders["body"]["recorders"][0]["state"] == "running"


def test_lab_beds_not_available_returns_failed_state() -> None:
    with running_server(session_store=UnavailableReadModelStore()) as address:
        response = request(address, "GET", "/lab/beds")

    assert response["status"] == 503
    assert response["body"]["state"] == "failed"
    assert response["body"]["beds"] == []
    assert response["body"]["readError"] == "lab session read model is unavailable"


def test_lab_recorders_not_available_returns_failed_state() -> None:
    with running_server(session_store=UnavailableReadModelStore()) as address:
        response = request(address, "GET", "/lab/recorders")

    assert response["status"] == 503
    assert response["body"]["state"] == "failed"
    assert response["body"]["recorders"] == []
    assert response["body"]["readError"] == "lab session read model is unavailable"


def test_lab_bed_create_failure_bubbles_as_service_unavailable() -> None:
    with running_server(session_store=UnavailableReadModelStore()) as address:
        response = request(
            address,
            "POST",
            "/lab/beds/create",
            {"roomNames": ["Bed-A"]},
        )

    assert response["status"] == 503
    assert response["body"]["state"] == "failed"
    assert response["body"]["readError"] == "lab session read model is unavailable"


def test_lab_session_start_returns_service_unavailable_if_read_model_is_broken() -> (
    None
):
    class ReadModelUnavailableAfterStartStore(InMemoryLabSessionStore):
        def list_beds(self) -> tuple[LabBed, ...]:
            raise LabSessionStoreUnavailable(
                "lab session read model is unavailable",
                kind="labReadModelUnavailable",
            )

        def list_recorders(self) -> tuple[LabRecorder, ...]:
            raise LabSessionStoreUnavailable(
                "lab session read model is unavailable",
                kind="labReadModelUnavailable",
            )

    with running_server(session_store=ReadModelUnavailableAfterStartStore()) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Session with unavailable read model",
                "recorderCount": 1,
            },
        )
        response = request(address, "POST", "/lab/sessions/lab_session_1/start")

    assert response["status"] == 503
    assert response["body"]["state"] == "failed"
    assert response["body"]["operationId"] == "lab-session-start-lab_session_1"
    assert response["body"]["readError"] == "lab session read model is unavailable"


def test_lab_recorder_management_creates_and_deletes_product_read_model() -> None:
    with running_server(["manual_session_1"]) as address:
        beds_created = request(
            address,
            "POST",
            "/lab/beds/create",
            {"roomNames": ["Lab-A"]},
        )
        bed_id = beds_created["body"]["beds"][0]["bedId"]
        created = request(
            address,
            "POST",
            "/lab/recorders/create",
            {"bedIds": [bed_id]},
        )
        recorder_id = created["body"]["recorders"][0]["recorderId"]
        deleted = request(
            address,
            "POST",
            "/lab/recorders/delete",
            {"recorderIds": [recorder_id]},
        )

    assert created["status"] == 202
    assert re.fullmatch(
        r"rec_[A-Z0-9]{6}", created["body"]["recorders"][0]["recorderId"]
    )
    assert deleted["status"] == 202
    assert deleted["body"]["recorders"] == []


def test_session_start_sends_lab_recorder_payloads_and_updates_read_model() -> None:
    sender = FakeSender()
    with running_server(["lab_session_1"], sender=sender) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Recovery",
                "recorderCount": 1,
                "targetURL": "http://edge/",
                "bedRoomNames": ["OR-A"],
            },
        )
        started = request(address, "POST", "/lab/sessions/lab_session_1/start")
        recorders = request(address, "GET", "/lab/recorders")

    assert started["status"] == 202
    assert sender.calls[0]["target_url"] == "http://edge/"
    assert re.fullmatch(r"LAB-[A-Z0-9]{6}", sender.calls[0]["payload"]["vrcode"])
    assert list(sender.calls[0]["payload"]["rooms"].keys()) == ["OR-A"]
    track_names = {
        track["name"] for track in sender.calls[0]["payload"]["rooms"]["OR-A"]["trks"]
    }
    assert track_names == {
        "HR",
        "PLETH_SPO2",
        "ART_SBP",
        "ART_DBP",
        "ART_MBP",
        "RR",
        "BT",
        "ECG",
        "PLETH",
        "CO2",
    }
    assert all(
        isinstance(track.get("montype"), str) and track["montype"]
        for track in sender.calls[0]["payload"]["rooms"]["OR-A"]["trks"]
    )
    tracks = {
        track["name"]: track
        for track in sender.calls[0]["payload"]["rooms"]["OR-A"]["trks"]
    }
    assert len(tracks["ECG"]["recs"][0]["val"]) == tracks["ECG"]["srate"]
    assert len(tracks["PLETH"]["recs"][0]["val"]) == tracks["PLETH"]["srate"]
    assert len(tracks["CO2"]["recs"][0]["val"]) == tracks["CO2"]["srate"]
    assert min(tracks["PLETH"]["recs"][0]["val"]) >= tracks["PLETH"]["mindisp"]
    assert max(tracks["PLETH"]["recs"][0]["val"]) <= tracks["PLETH"]["maxdisp"]
    recorder = recorders["body"]["recorders"][0]
    assert recorder["messagesSent"] == 1
    assert recorder["lastSendState"] == "sent"
    assert recorder["lastSendError"] is None
    assert recorder["lastSendAt"] is not None


def test_session_start_streams_until_session_stop() -> None:
    sender = FakeSender()
    with running_server(
        ["lab_session_1"],
        sender=sender,
        frame_interval_seconds=0.01,
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Streaming session",
                "recorderCount": 1,
                "targetURL": "http://edge/",
                "bedRoomNames": ["OR-A"],
            },
        )
        started = request(address, "POST", "/lab/sessions/lab_session_1/start")
        time.sleep(0.05)
        running_recorders = request(address, "GET", "/lab/recorders")
        stopped = request(address, "POST", "/lab/sessions/lab_session_1/stop")
        payloads_at_stop = [call["payload"] for call in sender.calls]
        sent_at_stop = len(sender.calls)
        vrcode = running_recorders["body"]["recorders"][0]["vrcode"]
        time.sleep(0.03)
        sent_after_stop_wait = len(sender.calls)

    assert started["status"] == 202
    assert stopped["status"] == 202
    assert running_recorders["body"]["recorders"][0]["messagesSent"] > 1
    rooms = [next(iter(payload["rooms"].values())) for payload in payloads_at_stop]
    assert len({room["dtcase"] for room in rooms}) == 1
    assert len({room["dtstart"] for room in rooms}) > 1
    assert sent_after_stop_wait == sent_at_stop
    assert ("http://edge/", vrcode) in sender.closed_recorders


def test_session_stop_pauses_without_archive_finalization() -> None:
    finalizer = FakeArchiveFinalizer()
    with running_server(
        ["lab_session_1"],
        archive_finalizer=finalizer,
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "recorderCount": 2,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")
        stopped = request(address, "POST", "/lab/sessions/lab_session_1/stop")

    assert stopped["status"] == 202
    assert stopped["body"]["session"]["state"] == "stopped"
    assert "archiveFinalization" not in stopped["body"]
    assert finalizer.calls == []


def test_session_finish_requests_durable_archive_finalization() -> None:
    finalizer = FakeArchiveFinalizer()
    with running_server(
        ["lab_session_1"],
        archive_finalizer=finalizer,
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "recorderCount": 2,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")
        vrcodes = tuple(recorder.vrcode for recorder in address.store.list_recorders())

        finished = request(address, "POST", "/lab/sessions/lab_session_1/finish")

    assert finished["status"] == 202
    assert finished["body"]["session"]["state"] == "finished"
    assert finished["body"]["archiveFinalization"] == {
        "state": "queued",
        "updatedAt": "2026-07-16T00:00:00Z",
        "readError": None,
    }
    assert finalizer.calls == [(vrcodes, "lab_session_finished")]


def test_finished_session_reads_ingress_owned_archive_finalization_progress() -> None:
    finalizer = FakeArchiveFinalizer()
    with running_server(
        ["lab_session_1"],
        archive_finalizer=finalizer,
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "recorderCount": 1,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")
        request(address, "POST", "/lab/sessions/lab_session_1/finish")
        finalizer.progress_state = "exported"

        session = request(address, "GET", "/lab/sessions/lab_session_1")
        sessions = request(address, "GET", "/lab/sessions")

    assert session["status"] == 200
    assert session["body"]["session"]["archiveFinalization"]["state"] == "exported"
    assert sessions["body"]["sessions"][0]["archiveFinalization"]["state"] == "exported"
    persisted = address.store.get("lab_session_1")
    assert persisted is not None
    assert persisted.archive_finalization_request_ids == ("finalization-1",)


def test_finished_session_is_terminal_and_cannot_restart() -> None:
    finalizer = FakeArchiveFinalizer()
    with running_server(
        ["lab_session_1"],
        archive_finalizer=finalizer,
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "recorderCount": 1,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")
        request(address, "POST", "/lab/sessions/lab_session_1/finish")

        restarted = request(address, "POST", "/lab/sessions/lab_session_1/start")

    assert restarted["status"] == 409
    assert restarted["body"]["state"] == "failed"
    assert "cannot start from state finished" in restarted["body"]["readError"]


def test_finished_session_accepts_explicit_archive_finalization_retry() -> None:
    finalizer = FakeArchiveFinalizer()
    with running_server(
        ["lab_session_1"],
        archive_finalizer=finalizer,
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "recorderCount": 1,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")
        request(address, "POST", "/lab/sessions/lab_session_1/finish")

        retried = request(address, "POST", "/lab/sessions/lab_session_1/finish")

    assert retried["status"] == 202
    assert retried["body"]["session"]["state"] == "finished"
    assert len(finalizer.calls) == 2


def test_accepted_session_cannot_finish_or_request_archive_finalization() -> None:
    finalizer = FakeArchiveFinalizer()
    with running_server(
        ["lab_session_1"],
        archive_finalizer=finalizer,
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "recorderCount": 1,
                "targetURL": "http://edge/",
            },
        )

        finished = request(address, "POST", "/lab/sessions/lab_session_1/finish")

    assert finished["status"] == 409
    assert finalizer.calls == []


def test_session_finish_preserves_finished_state_when_finalization_request_fails() -> (
    None
):
    with running_server(
        ["lab_session_1"],
        archive_finalizer=FailingArchiveFinalizer(),
    ) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "recorderCount": 1,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")

        stopped = request(address, "POST", "/lab/sessions/lab_session_1/stop")
        assert stopped["status"] == 202
        finished = request(address, "POST", "/lab/sessions/lab_session_1/finish")
        persisted = address.store.get("lab_session_1")

    assert finished["status"] == 502
    assert finished["body"]["state"] == "failed"
    assert finished["body"]["session"]["state"] == "finished"
    assert finished["body"]["archiveFinalization"] == {"state": "failed"}
    assert persisted is not None
    assert persisted.state == "finished"


def test_session_finish_reports_unavailable_archive_finalizer() -> None:
    with running_server(["lab_session_1"]) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "recorderCount": 1,
                "targetURL": "http://edge/",
            },
        )
        request(address, "POST", "/lab/sessions/lab_session_1/start")

        finished = request(address, "POST", "/lab/sessions/lab_session_1/finish")

    assert finished["status"] == 502
    assert finished["body"]["session"]["state"] == "finished"
    assert "archive finalizer is unavailable" in finished["body"]["readError"]


def test_session_start_records_recorder_send_failure() -> None:
    with running_server(["lab_session_1"], sender=FailingSender()) as address:
        request(
            address,
            "POST",
            "/lab/sessions",
            {
                "scenarioId": "baseline-monitoring",
                "name": "Recovery",
                "recorderCount": 1,
                "targetURL": "http://edge/",
                "bedRoomNames": ["OR-A"],
            },
        )
        started = request(address, "POST", "/lab/sessions/lab_session_1/start")
        recorders = request(address, "GET", "/lab/recorders")

    assert started["status"] == 202
    recorder = recorders["body"]["recorders"][0]
    assert recorder["messagesSent"] == 0
    assert recorder["lastSendState"] == "failed"
    assert recorder["lastSendAt"] is not None
    assert recorder["lastSendError"] == "send dependency unavailable"


def test_missing_session_is_explicit_failure() -> None:
    with running_server() as address:
        response = request(address, "GET", "/lab/sessions/missing-session")

    assert response["status"] == 404
    assert response["body"] == {
        "state": "failed",
        "operationId": None,
        "session": None,
        "readError": "Lab session is not available: missing-session",
    }


def test_replay_vital_file_creates_replay_session_without_exposing_file_path(
    tmp_path: Path,
) -> None:
    vital_file = tmp_path / "private" / "sample.vital"
    vital_file.parent.mkdir()
    vital_file.write_bytes(b"vital")

    with running_server(["lab_replay_1"], vital_files_mount=tmp_path) as address:
        response = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFileRelativePath": "private/sample.vital",
                "targetURL": "http://edge/",
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "once"},
            },
        )

    assert response["status"] == 202
    assert response["body"]["operationId"] == "lab-vital-file-replay-lab_replay_1"
    assert response["body"]["session"]["sessionId"] == "lab_replay_1"
    assert response["body"]["session"]["scenarioId"] == "vital-file-replay"
    assert response["body"]["session"]["name"] == "Vital File Replay"
    assert str(vital_file) not in json.dumps(response["body"])
    stored_session = address.store.get("lab_replay_1")
    assert stored_session is not None
    assert stored_session.vital_file_path == str(vital_file)
    assert stored_session.vital_file_relative_path == "private/sample.vital"
    assert stored_session.replay_policy is not None
    assert stored_session.replay_policy.mode == "once"


def test_replay_vital_file_start_uses_replay_payload_without_exposing_path(
    tmp_path: Path,
) -> None:
    sender = FakeSender()
    vital_file = tmp_path / "private" / "sample.vital"
    vital_file.parent.mkdir()
    vital_file.write_bytes(b"vital")

    with running_server(
        ["lab_replay_1"],
        sender=sender,
        vital_files_mount=tmp_path,
        frame_interval_seconds=0.01,
        replay_source_factory=FakeVitalReplaySourceFactory(),
    ) as address:
        request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFileRelativePath": "private/sample.vital",
                "targetURL": "http://edge/",
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "continuous"},
            },
        )
        started = request(address, "POST", "/lab/sessions/lab_replay_1/start")
        time.sleep(0.03)
        recorders = request(address, "GET", "/lab/recorders")
        payloads = [call["payload"] for call in sender.calls]

    assert started["status"] == 202
    assert sender.calls[0]["payload"]["source"] == {"kind": "vital-file-replay"}
    first_track = next(iter(sender.calls[0]["payload"]["rooms"].values()))["trks"][0]
    assert first_track["sourceTrack"] == "Source/HR"
    assert str(vital_file) not in json.dumps(sender.calls[0]["payload"])
    rooms = [next(iter(payload["rooms"].values())) for payload in payloads]
    assert len(rooms) > 1
    assert len({room["dtcase"] for room in rooms}) == 1
    assert len({room["dtstart"] for room in rooms}) > 1
    recorder = recorders["body"]["recorders"][0]
    assert recorder["lastSendState"] == "sent"
    assert recorder["messagesSent"] > 1


def test_replay_session_shutdown_closes_operation_owned_source(tmp_path: Path) -> None:
    source_factory = FakeVitalReplaySourceFactory()
    vital_file = tmp_path / "sample.vital"
    vital_file.write_bytes(b"vital")

    with running_server(
        ["lab_replay_1"],
        sender=FakeSender(),
        vital_files_mount=tmp_path,
        frame_interval_seconds=0.01,
        replay_source_factory=source_factory,
    ) as address:
        request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFileRelativePath": "sample.vital",
                "targetURL": "http://edge/",
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "continuous"},
            },
        )
        request(address, "POST", "/lab/sessions/lab_replay_1/start")
        assert source_factory.sources[0].closed is False

    assert source_factory.sources[0].closed is True


def test_replay_file_validation_failure_is_persisted_and_cleared_on_retry(
    tmp_path: Path,
) -> None:
    source_factory = FailingThenSuccessfulVitalReplaySourceFactory()
    vital_file = tmp_path / "sample.vital"
    vital_file.write_bytes(b"vital")

    with running_server(
        ["lab_replay_1"],
        vital_files_mount=tmp_path,
        replay_source_factory=source_factory,
    ) as address:
        request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFileRelativePath": "sample.vital",
                "targetURL": "http://edge/",
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "once"},
            },
        )

        failed = request(address, "POST", "/lab/sessions/lab_replay_1/start")
        loaded_after_failure = request(
            address,
            "GET",
            "/lab/sessions/lab_replay_1",
        )
        listed_after_failure = request(address, "GET", "/lab/sessions")
        recorder_after_failure = request(address, "GET", "/lab/recorders")["body"][
            "recorders"
        ][0]
        restarted = request(address, "POST", "/lab/sessions/lab_replay_1/start")
        loaded_after_restart = request(
            address,
            "GET",
            "/lab/sessions/lab_replay_1",
        )

    assert failed["status"] == 422
    assert failed["body"]["state"] == "failed"
    assert failed["body"]["session"]["state"] == "failed"
    failure = failed["body"]["session"]["failure"]
    assert failure["stage"] == "fileValidation"
    assert failure["code"] == "invalidWaveformSampleRate"
    assert failure["message"] == (
        "Vital File waveform track has an invalid sample rate: Source/PLETH"
    )
    assert failure["failedAt"]
    assert loaded_after_failure["body"]["session"]["failure"] == failure
    assert listed_after_failure["body"]["sessions"][0]["failure"] == failure
    assert recorder_after_failure["state"] == "failed"
    assert recorder_after_failure["messagesSent"] == 0
    assert recorder_after_failure["lastSendState"] == "notAttempted"
    assert recorder_after_failure["lastSendError"] is None
    assert restarted["status"] == 202
    assert restarted["body"]["session"]["state"] == "running"
    assert "failure" not in restarted["body"]["session"]
    assert "failure" not in loaded_after_restart["body"]["session"]


def test_replay_vital_file_rejects_unavailable_or_unmounted_source(
    tmp_path: Path,
) -> None:
    valid = tmp_path / "case.vital"
    valid.write_bytes(b"vital")
    wrong_extension = tmp_path / "case.txt"
    wrong_extension.write_text("vital", encoding="utf-8")
    outside = tmp_path.parent / "outside.vital"
    outside.write_bytes(b"vital")

    with running_server(vital_files_mount=tmp_path) as address:
        relative = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFileRelativePath": str(valid),
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "once"},
            },
        )
        invalid_extension = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFileRelativePath": "case.txt",
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "once"},
            },
        )
        outside_mount = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFileRelativePath": "../outside.vital",
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "once"},
            },
        )
        missing = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFileRelativePath": "missing.vital",
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "once"},
            },
        )
        accepted = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFileRelativePath": "case.vital",
                "resourceSelection": {"mode": "quickCreate"},
                "repeatPolicy": {"mode": "once"},
            },
        )

    assert relative["status"] == 400
    assert relative["body"]["error"] == "vitalFileRelativePath_absolute"
    assert invalid_extension["status"] == 400
    assert (
        invalid_extension["body"]["error"] == "vitalFileRelativePath_invalid_extension"
    )
    assert outside_mount["status"] == 400
    assert outside_mount["body"]["error"] == "vitalFileRelativePath_outside_library"
    assert missing["status"] == 404
    assert missing["body"]["error"] == "vitalFileRelativePath_missing"
    assert accepted["status"] == 202


def test_create_session_reports_missing_scenario() -> None:
    with running_server() as address:
        response = request(
            address,
            "POST",
            "/lab/sessions",
            {"scenarioId": "missing-case", "recorderCount": 1},
        )

    assert response["status"] == 404
    assert response["body"] == {
        "error": "scenario_not_found",
        "message": "Lab scenario is not available: missing-case",
    }


class running_server:
    def __init__(
        self,
        ids: list[str] | None = None,
        *,
        sender: FakeSender | None = None,
        vital_files_mount: Path | None = None,
        session_store: LabSessionStore | None = None,
        replay_source_factory: Any | None = None,
        frame_interval_seconds: float = 1.0,
        archive_finalizer: Any | None = None,
    ) -> None:
        self.ids = ids or ["lab_session_1"]
        self.sender = sender or FakeSender()
        self.vital_files_mount = vital_files_mount or Path("/mnt/tirosh-vital-files")
        self.session_store = session_store
        self.replay_source_factory = replay_source_factory
        self.frame_interval_seconds = frame_interval_seconds
        self.archive_finalizer = archive_finalizer

    def __enter__(self) -> running_server:
        counter = iter(self.ids)
        self.settings = LabSettings(
            host="127.0.0.1",
            port=0,
            service_name="vitalserver-lab",
            session_store="memory",
            allow_memory_store=True,
            database_url=None,
            vital_files_mount=self.vital_files_mount,
        )
        self.store = (
            self.session_store
            if self.session_store is not None
            else InMemoryLabSessionStore(id_factory=lambda: next(counter))
        )
        if isinstance(self.store, InMemoryLabSessionStore):
            self.store.id_factory = lambda: next(counter)
        self.engine = LabExecutionEngine(
            sender=self.sender,
            vital_replay_source_factory=self.replay_source_factory,
            frame_interval_seconds=self.frame_interval_seconds,
            archive_finalizer=self.archive_finalizer,
        )
        return self

    def __exit__(self, *_: object) -> None:
        self.engine.shutdown()
        return None


def request(
    server: running_server,
    method: str,
    path: str,
    body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    encoded = None if body is None else json.dumps(body).encode()
    status, response_body = route_lab_request(
        method=method,
        path=path,
        body=encoded or b"",
        settings=server.settings,
        scenarios=DEFAULT_SCENARIOS,
        session_store=server.store,
        execution_engine=server.engine,
    )
    return {"status": status.value, "body": response_body}


class FakeSender:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []
        self.closed_recorders: list[tuple[str, str]] = []
        self.closed_all = False

    def send(
        self,
        *,
        target_url: str,
        payload: dict[str, object],
    ) -> LabRecorderSendReceipt:
        self.calls.append({"target_url": target_url, "payload": payload})
        return LabRecorderSendReceipt(transport="fake", bytes_sent=123)

    def close_recorder(self, *, target_url: str, vrcode: str) -> None:
        self.closed_recorders.append((target_url, vrcode))

    def close_all(self) -> None:
        self.closed_all = True


class FakeArchiveFinalizer:
    def __init__(self) -> None:
        self.calls: list[tuple[tuple[str, ...], str]] = []
        self.progress_state = "queued"

    def request_finalization(
        self,
        *,
        vrcodes: tuple[str, ...],
        reason: str,
    ) -> LabArchiveFinalizationReceipt:
        self.calls.append((vrcodes, reason))
        return LabArchiveFinalizationReceipt(
            state="accepted",
            request_ids=("finalization-1",),
        )

    def read_finalization(
        self,
        *,
        request_ids: tuple[str, ...],
    ) -> LabArchiveFinalizationProgress:
        assert request_ids == ("finalization-1",)
        return LabArchiveFinalizationProgress(
            state=self.progress_state,
            request_ids=request_ids,
            requests=(
                {
                    "requestId": "finalization-1",
                    "state": self.progress_state,
                },
            ),
            updated_at="2026-07-16T00:00:00Z",
        )


class FailingArchiveFinalizer:
    def request_finalization(
        self,
        *,
        vrcodes: tuple[str, ...],
        reason: str,
    ) -> LabArchiveFinalizationReceipt:
        del vrcodes
        del reason
        raise LabArchiveFinalizationError("recorder ingress unavailable")


class FailingSender:
    def send(
        self,
        *,
        target_url: str,
        payload: dict[str, object],
    ) -> LabRecorderSendReceipt:
        del target_url
        del payload
        raise LabRecorderSendError("send dependency unavailable")

    def close_recorder(self, *, target_url: str, vrcode: str) -> None:
        del target_url
        del vrcode

    def close_all(self) -> None:
        return None


class FakeSocketIOModule:
    def __init__(self, client: FakeSocketIOClient) -> None:
        self.client = client

    def Client(self, **kwargs: Any) -> FakeSocketIOClient:
        self.client.client_options = kwargs
        return self.client


class FakeSocketIOClient:
    def __init__(self) -> None:
        self.connected = False
        self.disconnected = False
        self.connected_url: str | None = None
        self.connect_count = 0
        self.client_options: dict[str, Any] = {}
        self.emitted: list[tuple[str, Any]] = []

    def connect(self, url: str, *, transports: list[str]) -> None:
        self.connected = True
        self.connect_count += 1
        self.connected_url = url
        self.transports = transports

    def emit(self, event: str, data: Any) -> None:
        self.emitted.append((event, data))

    def sleep(self, seconds: float) -> None:
        self.sleep_seconds = seconds

    def disconnect(self) -> None:
        self.connected = False
        self.disconnected = True


class FakeVitalReplaySourceFactory:
    def __init__(self) -> None:
        self.sources: list[FakeVitalReplaySource] = []

    def open(self, path: Path) -> FakeVitalReplaySource:
        assert path.name == "sample.vital"
        source = FakeVitalReplaySource()
        self.sources.append(source)
        return source


class FailingThenSuccessfulVitalReplaySourceFactory:
    def __init__(self) -> None:
        self.open_count = 0

    def open(self, path: Path) -> FakeVitalReplaySource:
        assert path.name == "sample.vital"
        self.open_count += 1
        if self.open_count == 1:
            raise VitalReplaySourceError(
                "Vital File waveform track has an invalid sample rate: Source/PLETH",
                stage="fileValidation",
                code="invalidWaveformSampleRate",
            )
        return FakeVitalReplaySource()


class FakeVitalReplaySource:
    duration_seconds = 2

    def __init__(self) -> None:
        self.closed = False

    def frame(self, *, offset_seconds: int, output_time: float) -> LabVitalReplayFrame:
        return LabVitalReplayFrame(
            devices=(
                {"type": "VitalFileReplay", "name": "Source", "status": "connected"},
            ),
            tracks=(
                {
                    "id": 2001,
                    "type": "num",
                    "name": "HR",
                    "dname": "Source",
                    "montype": "ECG_HR",
                    "unit": "/min",
                    "sourceTrack": "Source/HR",
                    "recs": [{"dt": output_time, "val": 70 + offset_seconds}],
                },
            ),
        )

    def close(self) -> None:
        self.closed = True


class UnavailableStore:
    def ensure_ready(self) -> None:
        raise LabSessionStoreUnavailable(
            "lab session store is unavailable",
            kind="testStoreUnavailable",
        )

    def create(self, request: Any) -> Any:
        del request
        raise AssertionError("create should not be called")

    def get(self, session_id: str) -> Any:
        del session_id
        raise AssertionError("get should not be called")

    def delete_session(self, session_id: str) -> Any:
        del session_id
        raise AssertionError("delete_session should not be called")

    def start(self, session_id: str) -> Any:
        del session_id
        raise AssertionError("start should not be called")

    def stop(self, session_id: str) -> Any:
        del session_id
        raise AssertionError("stop should not be called")

    def list_beds(self) -> Any:
        raise AssertionError("list_beds should not be called")

    def list_recorders(self) -> Any:
        raise AssertionError("list_recorders should not be called")

    def create_beds(self, request: Any) -> Any:
        del request
        raise AssertionError("create_beds should not be called")

    def delete_beds(self, request: Any) -> Any:
        del request
        raise AssertionError("delete_beds should not be called")

    def reset_beds(self) -> Any:
        raise AssertionError("reset_beds should not be called")

    def create_recorders(self, request: Any) -> Any:
        del request
        raise AssertionError("create_recorders should not be called")

    def delete_recorders(self, request: Any) -> Any:
        del request
        raise AssertionError("delete_recorders should not be called")

    def reset_recorders(self) -> Any:
        raise AssertionError("reset_recorders should not be called")

    def save_recorder_execution_results(self, results: Any) -> None:
        del results
        raise AssertionError("save_recorder_execution_results should not be called")


class UnavailableReadModelStore:
    def ensure_ready(self) -> None:
        return None

    def create(self, request: Any) -> Any:
        del request
        raise AssertionError("create should not be called")

    def get(self, session_id: str) -> Any:
        del session_id
        raise AssertionError("get should not be called")

    def delete_session(self, session_id: str) -> Any:
        del session_id
        raise AssertionError("delete_session should not be called")

    def start(self, session_id: str) -> Any:
        del session_id
        raise AssertionError("start should not be called")

    def stop(self, session_id: str) -> Any:
        del session_id
        raise AssertionError("stop should not be called")

    def list_beds(self) -> Any:
        raise LabSessionStoreUnavailable(
            "lab session read model is unavailable",
            kind="labReadModelUnavailable",
        )

    def list_recorders(self) -> Any:
        raise LabSessionStoreUnavailable(
            "lab session read model is unavailable",
            kind="labReadModelUnavailable",
        )

    def create_beds(self, request: Any) -> Any:
        del request
        raise LabSessionStoreUnavailable(
            "lab session read model is unavailable",
            kind="labReadModelUnavailable",
        )

    def delete_beds(self, request: Any) -> Any:
        del request
        raise LabSessionStoreUnavailable(
            "lab session read model is unavailable",
            kind="labReadModelUnavailable",
        )

    def reset_beds(self) -> Any:
        raise LabSessionStoreUnavailable(
            "lab session read model is unavailable",
            kind="labReadModelUnavailable",
        )

    def create_recorders(self, request: Any) -> Any:
        del request
        raise LabSessionStoreUnavailable(
            "lab session read model is unavailable",
            kind="labReadModelUnavailable",
        )

    def delete_recorders(self, request: Any) -> Any:
        del request
        raise LabSessionStoreUnavailable(
            "lab session read model is unavailable",
            kind="labReadModelUnavailable",
        )

    def reset_recorders(self) -> Any:
        raise LabSessionStoreUnavailable(
            "lab session read model is unavailable",
            kind="labReadModelUnavailable",
        )

    def save_recorder_execution_results(self, results: Any) -> None:
        del results
        raise LabSessionStoreUnavailable(
            "lab session read model is unavailable",
            kind="labReadModelUnavailable",
        )

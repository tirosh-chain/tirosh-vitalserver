from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import pytest

from vitalserver_lab.execution import (
    LabExecutionEngine,
    LabRecorderSendError,
    LabRecorderSendReceipt,
)
from vitalserver_lab.model import (
    DEFAULT_SCENARIOS,
    InMemoryLabSessionStore,
    LabSessionCreateInput,
    LabSessionStoreUnavailable,
)
from vitalserver_lab.postgres_store import PostgresLabSessionStore
from vitalserver_lab.server import build_session_store, route_lab_request
from vitalserver_lab.settings import (
    LabSettings,
    LabSettingsConfigurationError,
    load_settings,
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
        psql_command="psql",
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
        psql_command="psql",
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
        "respiratory-variation",
        "vital-file-replay",
    ]


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
    assert [
        recorder["bedId"] for recorder in recorders["body"]["recorders"]
    ] == [
        "lab_session_1-bed-1",
        "lab_session_1-bed-2",
    ]
    assert [
        recorder["state"] for recorder in recorders["body"]["recorders"]
    ] == [
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
        deleted = request(
            address,
            "POST",
            "/lab/beds/delete",
            {"bedIds": ["manual_session_1-bed-1"]},
        )

    assert created["status"] == 202
    assert [bed["name"] for bed in created["body"]["beds"]] == ["Lab-A", "Lab-B"]
    assert [
        recorder.vrcode for recorder in address.store.list_recorders()
    ] == ["LAB-manual_session_1-2"]
    assert deleted["status"] == 202
    assert [bed["bedId"] for bed in deleted["body"]["beds"]] == [
        "manual_session_1-bed-2"
    ]


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


def test_lab_recorder_management_creates_and_deletes_product_read_model() -> None:
    with running_server(["manual_session_1"]) as address:
        request(
            address,
            "POST",
            "/lab/beds/create",
            {"roomNames": ["Lab-A"]},
        )
        created = request(
            address,
            "POST",
            "/lab/recorders/create",
            {"bedIds": ["manual_session_1-bed-1"]},
        )
        deleted = request(
            address,
            "POST",
            "/lab/recorders/delete",
            {"recorderIds": ["manual_session_1-recorder-2"]},
        )

    assert created["status"] == 202
    assert [recorder["recorderId"] for recorder in created["body"]["recorders"]] == [
        "manual_session_1-recorder-1",
        "manual_session_1-recorder-2",
    ]
    assert deleted["status"] == 202
    assert [recorder["recorderId"] for recorder in deleted["body"]["recorders"]] == [
        "manual_session_1-recorder-1"
    ]


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
    assert sender.calls[0]["payload"]["vrcode"] == "LAB-lab_session_1-1"
    assert list(sender.calls[0]["payload"]["rooms"].keys()) == ["OR-A"]
    recorder = recorders["body"]["recorders"][0]
    assert recorder["messagesSent"] == 1
    assert recorder["lastSendState"] == "sent"
    assert recorder["lastSendError"] is None
    assert recorder["lastSendAt"] is not None


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
                "vitalFilePath": str(vital_file),
                "targetURL": "http://edge/",
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
    ) as address:
        request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {
                "vitalFilePath": str(vital_file),
                "targetURL": "http://edge/",
            },
        )
        started = request(address, "POST", "/lab/sessions/lab_replay_1/start")
        recorders = request(address, "GET", "/lab/recorders")

    assert started["status"] == 202
    assert sender.calls[0]["payload"]["source"] == {"kind": "vital-file-replay"}
    assert str(vital_file) not in json.dumps(sender.calls[0]["payload"])
    recorder = recorders["body"]["recorders"][0]
    assert recorder["lastSendState"] == "sent"
    assert recorder["messagesSent"] == 1


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
            {"vitalFilePath": "case.vital"},
        )
        invalid_extension = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {"vitalFilePath": str(wrong_extension)},
        )
        outside_mount = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {"vitalFilePath": str(outside)},
        )
        missing = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {"vitalFilePath": str(tmp_path / "missing.vital")},
        )
        accepted = request(
            address,
            "POST",
            "/lab/vital-files/replay",
            {"vitalFilePath": str(valid)},
        )

    assert relative["status"] == 400
    assert relative["body"]["error"] == "vitalFilePath_not_absolute"
    assert invalid_extension["status"] == 400
    assert invalid_extension["body"]["error"] == "vitalFilePath_invalid_extension"
    assert outside_mount["status"] == 400
    assert outside_mount["body"]["error"] == "vitalFilePath_outside_mount"
    assert missing["status"] == 404
    assert missing["body"]["error"] == "vitalFilePath_missing"
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
    ) -> None:
        self.ids = ids or ["lab_session_1"]
        self.sender = sender or FakeSender()
        self.vital_files_mount = vital_files_mount or Path("/mnt/tirosh-vital-files")

    def __enter__(self) -> running_server:
        counter = iter(self.ids)
        self.settings = LabSettings(
            host="127.0.0.1",
            port=0,
            service_name="vitalserver-lab",
            session_store="memory",
            allow_memory_store=True,
            database_url=None,
            psql_command="psql",
            vital_files_mount=self.vital_files_mount,
        )
        self.store = InMemoryLabSessionStore(id_factory=lambda: next(counter))
        self.engine = LabExecutionEngine(sender=self.sender)
        return self

    def __exit__(self, *_: object) -> None:
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

    def send(
        self,
        *,
        target_url: str,
        payload: dict[str, object],
    ) -> LabRecorderSendReceipt:
        self.calls.append({"target_url": target_url, "payload": payload})
        return LabRecorderSendReceipt(status_code=200, bytes_sent=123)


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


def test_postgres_store_runs_schema_migration(monkeypatch: Any) -> None:
    calls: list[list[str]] = []

    def fake_run(
        command: list[str],
        *,
        check: bool,
        capture_output: bool,
        text: bool,
    ) -> subprocess.CompletedProcess[str]:
        assert check is True
        assert capture_output is True
        assert text is True
        calls.append(command)
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    PostgresLabSessionStore("postgresql://lab-db").ensure_ready()

    assert calls[0][:2] == ["psql", "postgresql://lab-db"]
    assert "CREATE TABLE IF NOT EXISTS lab_sessions" in calls[0][-1]
    assert "CREATE TABLE IF NOT EXISTS lab_beds" in calls[0][-1]
    assert "CREATE TABLE IF NOT EXISTS lab_recorders" in calls[0][-1]


def test_postgres_store_persists_and_reads_lab_session(monkeypatch: Any) -> None:
    saved_sql: list[str] = []
    store = PostgresLabSessionStore(
        "postgresql://lab-db",
        id_factory=lambda: "lab_session_pg_1",
    )

    def fake_run(
        command: list[str],
        *,
        check: bool,
        capture_output: bool,
        text: bool,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del capture_output
        del text
        sql = command[-1]
        saved_sql.append(sql)
        if "FROM lab_recorders" in sql:
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")
        if "FROM lab_sessions" in sql:
            return subprocess.CompletedProcess(
                command,
                0,
                stdout=json.dumps(created.as_json(), sort_keys=True),
                stderr="",
            )
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    created = store.create(
        request=LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Postgres backed session",
            recorder_count=2,
            target_url="http://edge/",
            bed_room_names=("OR-A", "OR-B"),
        )
    )
    loaded = store.get("lab_session_pg_1")

    assert loaded == created
    assert any("INSERT INTO lab_sessions" in sql for sql in saved_sql)
    assert any("ON CONFLICT (session_id) DO UPDATE" in sql for sql in saved_sql)
    assert any("INSERT INTO lab_beds" in sql for sql in saved_sql)
    assert any("INSERT INTO lab_recorders" in sql for sql in saved_sql)
    assert any("SELECT document::text FROM lab_sessions" in sql for sql in saved_sql)


def test_postgres_store_persists_private_vital_file_replay_source(
    monkeypatch: Any,
) -> None:
    saved_sql: list[str] = []
    store = PostgresLabSessionStore(
        "postgresql://lab-db",
        id_factory=lambda: "lab_replay_pg_1",
    )

    def fake_run(
        command: list[str],
        *,
        check: bool,
        capture_output: bool,
        text: bool,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del capture_output
        del text
        sql = command[-1]
        saved_sql.append(sql)
        if "FROM lab_recorders" in sql:
            return subprocess.CompletedProcess(command, 0, stdout="", stderr="")
        if "FROM lab_sessions" in sql:
            return subprocess.CompletedProcess(
                command,
                0,
                stdout=json.dumps(private_document, sort_keys=True),
                stderr="",
            )
        return subprocess.CompletedProcess(command, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    created = store.create(
        request=LabSessionCreateInput(
            scenario_id="vital-file-replay",
            name="Replay",
            recorder_count=1,
            target_url="http://edge/",
            vital_file_path="/mnt/tirosh-vital-files/private/sample.vital",
        )
    )
    private_document = created.as_private_json()
    loaded = store.get("lab_replay_pg_1")

    assert loaded is not None
    assert loaded.vital_file_path == "/mnt/tirosh-vital-files/private/sample.vital"
    assert "vitalFilePath" not in created.as_json()
    assert any("vitalFilePath" in sql for sql in saved_sql)


def test_postgres_store_reports_psql_failure(monkeypatch: Any) -> None:
    def fake_run(
        command: list[str],
        *,
        check: bool,
        capture_output: bool,
        text: bool,
    ) -> subprocess.CompletedProcess[str]:
        del check
        del capture_output
        del text
        raise subprocess.CalledProcessError(
            2,
            command,
            output="",
            stderr="relation does not exist",
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    with pytest.raises(LabSessionStoreUnavailable) as error:
        PostgresLabSessionStore("postgresql://lab-db").ensure_ready()

    assert error.value.kind == "postgresCommandFailed"
    assert "relation does not exist" in error.value.message


def test_postgres_store_reports_psql_command_start_failure(monkeypatch: Any) -> None:
    def fake_run(
        command: list[str],
        *,
        check: bool,
        capture_output: bool,
        text: bool,
    ) -> subprocess.CompletedProcess[str]:
        del command
        del check
        del capture_output
        del text
        raise FileNotFoundError("psql")

    monkeypatch.setattr(subprocess, "run", fake_run)

    with pytest.raises(LabSessionStoreUnavailable) as error:
        PostgresLabSessionStore("postgresql://lab-db").ensure_ready()

    assert error.value.kind == "postgresCommandUnavailable"
    assert "postgres command could not start" in error.value.message

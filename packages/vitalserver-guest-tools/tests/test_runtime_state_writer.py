from __future__ import annotations

import json
import subprocess
from pathlib import Path

from pytest import MonkeyPatch

from tirosh_guest_tools.adapters.outbound.runtime import collector, state_writer
from tirosh_guest_tools.contracts import RuntimeFileName
from tirosh_guest_tools.domain.runtime_state import (
    GuestRuntimeState,
    ProbeError,
    RuntimeContainerService,
    RuntimeHTTPProbeStatus,
    RuntimeResourceUsage,
)


def test_runtime_state_document_reports_probe_failures(
    monkeypatch: MonkeyPatch,
) -> None:
    def missing_ip(probe_errors: list[ProbeError]) -> str | None:
        collector.append_probe_error(probe_errors, "vmIP", "missing")
        return None

    monkeypatch.setattr(collector, "first_non_loopback_ip", missing_ip)
    monkeypatch.setattr(collector, "boot_id", lambda errors: "boot-1")
    monkeypatch.setattr(collector, "compose_services", lambda errors: [])
    monkeypatch.setattr(collector, "cpu_usage_percent", lambda errors: 10.0)
    monkeypatch.setattr(
        collector,
        "memory_usage",
        lambda errors: RuntimeResourceUsage(used_bytes=1, total_bytes=2),
    )
    monkeypatch.setattr(
        collector,
        "disk_usage",
        lambda path, errors: RuntimeResourceUsage(used_bytes=1, total_bytes=2),
    )
    monkeypatch.setattr(collector, "vitaldb_observation", lambda errors: None)

    document = state_writer.runtime_state_document(
        guest_http="200",
        redis_ui_http="200",
        swagger_ui_http="200",
    ).as_json()

    assert document["vmIP"] is None
    assert document["probeErrors"] == [{"source": "vmIP", "message": "missing"}]


def test_service_stack_status_document_projects_service_stack_fields_only() -> None:
    app_service = RuntimeContainerService(
        service="app",
        container_id="container-1",
        exit_code=None,
        error=None,
        finished_at=None,
        health="healthy",
        memory_used_bytes=100,
        memory_limit_bytes=200,
        name="vitalserver-app-1",
        oom_killed=False,
        restart_count=0,
        started_at="2026-07-01T00:00:00Z",
        state="running",
        uptime_seconds=30,
    )
    edge_probe = RuntimeHTTPProbeStatus(status="200")
    redis_ui_probe = RuntimeHTTPProbeStatus(status="failed", failed=True)
    state = GuestRuntimeState(
        updated_at="2026-07-01T00:00:00Z",
        vm_ip="192.168.64.10",
        boot_id="boot-1",
        container_services=(app_service,),
        cpu_usage_percent=12.5,
        guest_http=edge_probe,
        memory=RuntimeResourceUsage(used_bytes=1, total_bytes=2),
        probe_errors=(ProbeError(source="vitalDBObservation", message="timeout"),),
        redis_ui_http=redis_ui_probe,
        system_disk=RuntimeResourceUsage(used_bytes=3, total_bytes=4),
        disk_health=None,
        swagger_ui_http=None,
        vital_files_disk=None,
        vitaldb_observation={"state": "loaded"},
    )

    document = state_writer.service_stack_status_document(state).as_json()

    assert document["schemaVersion"] == 1
    assert document["owner"] == "service-stack"
    assert document["updatedAt"] == "2026-07-01T00:00:00Z"
    assert document["bootID"] == "boot-1"
    assert document["composeServices"] == [app_service.as_json()]
    assert document["httpProbes"] == {
        "edge": edge_probe.as_json(),
        "redisUI": redis_ui_probe.as_json(),
        "swaggerUI": None,
    }
    assert document["vitalDBObservation"] == {"state": "loaded"}
    assert document["readIssues"] == [
        {"source": "vitalDBObservation", "message": "timeout"}
    ]
    assert "vmIP" not in document
    assert "cpuUsagePercent" not in document
    assert "memory" not in document
    assert "systemDisk" not in document


def test_write_runtime_state_can_write_parallel_service_stack_status(
    monkeypatch: MonkeyPatch,
    tmp_path: Path,
) -> None:
    state = GuestRuntimeState(
        updated_at="2026-07-01T00:00:00Z",
        vm_ip="192.168.64.10",
        boot_id="boot-1",
        container_services=(),
        cpu_usage_percent=None,
        guest_http=RuntimeHTTPProbeStatus(status="200"),
        memory=None,
        probe_errors=(),
        redis_ui_http=None,
        system_disk=None,
        disk_health=None,
        swagger_ui_http=None,
        vital_files_disk=None,
        vitaldb_observation=None,
    )
    monkeypatch.setattr(state_writer, "runtime_state_document", lambda **_: state)

    runtime_state = tmp_path / RuntimeFileName.RUNTIME_STATE.value
    service_stack_status = tmp_path / RuntimeFileName.SERVICE_STACK_STATUS.value

    state_writer.write_runtime_state(
        runtime_state,
        service_stack_status=service_stack_status,
    )

    runtime_document = json.loads(runtime_state.read_text(encoding="utf-8"))
    service_stack_document = json.loads(
        service_stack_status.read_text(encoding="utf-8")
    )
    assert runtime_document["vmIP"] == "192.168.64.10"
    assert service_stack_document["owner"] == "service-stack"
    assert "vmIP" not in service_stack_document


def test_http_probe_failure_remains_explicit(
    monkeypatch: MonkeyPatch,
) -> None:
    def failed_run(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
        return subprocess.CompletedProcess(
            args=[],
            returncode=7,
            stdout="",
            stderr="connection refused",
        )

    probe_errors: list[ProbeError] = []
    monkeypatch.setattr(collector.subprocess, "run", failed_run)

    status = collector.http_status(
        "guestHTTP",
        "http://127.0.0.1/ready",
        probe_errors,
    )

    assert status.as_status_text() == "failed"
    assert status.as_json() == {
        "status": "failed",
        "failed": True,
        "message": "connection refused",
        "exitCode": 7,
    }
    assert probe_errors == [
        ProbeError(source="guestHTTP", message="connection refused")
    ]


def test_compose_services_reads_stopped_containers_with_all(
    monkeypatch: MonkeyPatch,
    tmp_path: Path,
) -> None:
    (tmp_path / RuntimeFileName.COMPOSE.value).write_text("services: {}\n")
    monkeypatch.setattr(collector, "DEPLOY_DIR", tmp_path)
    commands: list[list[str]] = []

    def check_output(command: list[str], **kwargs: object) -> str:
        commands.append(command)
        if command[:2] == ["docker", "stats"]:
            return (
                '{"ID":"container-1","Name":"vitalserver-app-1",'
                '"MemUsage":"512MiB / 4GiB"}\n'
            )
        if command[:2] == ["docker", "inspect"]:
            return (
                "[{"
                '"Id":"container-1",'
                '"RestartCount":2,'
                '"State":{'
                '"StartedAt":"2026-06-11T00:00:00Z",'
                '"FinishedAt":"2026-06-12T00:00:00Z",'
                '"OOMKilled":true,'
                '"Error":"container oom killed"'
                "},"
                '"HostConfig":{"Memory":4294967296}'
                "}]"
            )
        return (
            '{"Service":"app","Name":"vitalserver-app-1",'
            '"State":"exited","Health":"","ExitCode":0,"ID":"container-1"}'
        )

    monkeypatch.setattr(collector.subprocess, "check_output", check_output)

    services = collector.compose_services([])

    assert commands[0] == [
        "docker",
        "compose",
        "--project-name",
        collector.PROJECT_NAME,
        "-f",
        str(tmp_path / RuntimeFileName.COMPOSE.value),
        "ps",
        "--all",
        "--format",
        "json",
    ]
    assert services is not None
    assert services[0].service == "app"
    assert services[0].state == "exited"
    assert services[0].container_id == "container-1"
    assert services[0].restart_count == 2
    assert services[0].oom_killed is True
    assert services[0].finished_at == "2026-06-12T00:00:00Z"
    assert services[0].error == "container oom killed"
    assert services[0].memory_used_bytes == 536870912
    assert services[0].memory_limit_bytes == 4294967296


def test_compose_services_reports_unknown_limit_when_no_hard_limit_configured(
    monkeypatch: MonkeyPatch,
    tmp_path: Path,
) -> None:
    (tmp_path / RuntimeFileName.COMPOSE.value).write_text("services: {}\n")
    monkeypatch.setattr(collector, "DEPLOY_DIR", tmp_path)

    def check_output(command: list[str], **kwargs: object) -> str:
        if command[:2] == ["docker", "stats"]:
            return (
                '{"ID":"container-1","Name":"vitalserver-app-1",'
                '"MemUsage":"512MiB / 4GiB"}\n'
            )
        if command[:2] == ["docker", "inspect"]:
            return '[{"Id":"container-1","HostConfig":{"Memory":0}}]'
        return (
            '{"Service":"app","Name":"vitalserver-app-1",'
            '"State":"running","Health":"","ExitCode":0,"ID":"container-1"}'
        )

    monkeypatch.setattr(collector.subprocess, "check_output", check_output)

    services = collector.compose_services([])

    assert services is not None
    assert services[0].memory_used_bytes == 536870912
    assert services[0].memory_limit_bytes is None


def test_parse_docker_memory_usage_preserves_missing_values() -> None:
    assert collector.parse_memory_usage(
        "1.5GiB / 4GiB"
    ) == collector.ContainerMemoryStats(
        used_bytes=1_610_612_736,
        limit_bytes=4_294_967_296,
    )
    assert collector.parse_memory_usage(None) == collector.ContainerMemoryStats(
        used_bytes=None,
        limit_bytes=None,
    )


def test_compose_services_reports_inspect_failure(
    monkeypatch: MonkeyPatch,
    tmp_path: Path,
) -> None:
    (tmp_path / RuntimeFileName.COMPOSE.value).write_text("services: {}\n")
    monkeypatch.setattr(collector, "DEPLOY_DIR", tmp_path)

    def check_output(command: list[str], **kwargs: object) -> str:
        if command[:2] == ["docker", "inspect"]:
            raise subprocess.CalledProcessError(1, command)
        return (
            '{"Service":"app","Name":"vitalserver-app-1",'
            '"State":"exited","Health":"","ExitCode":137,"ID":"container-1"}'
        )

    monkeypatch.setattr(collector.subprocess, "check_output", check_output)
    probe_errors: list[ProbeError] = []

    services = collector.compose_services(probe_errors)

    assert services is not None
    assert services[0].service == "app"
    assert services[0].container_id == "container-1"
    assert services[0].oom_killed is None
    assert len(probe_errors) == 1
    assert probe_errors[0].source == "docker inspect container-1"
    assert "returned non-zero exit status 1" in probe_errors[0].message


def test_compose_services_empty_output_is_probe_failure(
    monkeypatch: MonkeyPatch,
    tmp_path: Path,
) -> None:
    (tmp_path / RuntimeFileName.COMPOSE.value).write_text("services: {}\n")
    monkeypatch.setattr(collector, "DEPLOY_DIR", tmp_path)
    monkeypatch.setattr(
        collector.subprocess,
        "check_output",
        lambda *args, **kwargs: "",
    )
    probe_errors: list[ProbeError] = []

    services = collector.compose_services(probe_errors)

    assert services is None
    assert probe_errors == [
        ProbeError(source="docker compose ps", message="no service documents reported")
    ]

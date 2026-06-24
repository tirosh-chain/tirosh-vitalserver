from __future__ import annotations

import subprocess
from typing import Any

import pytest

from tirosh_guest_tools.application import compose
from tirosh_guest_tools.contracts import ComposeService, RuntimeFileName
from tirosh_guest_tools.domain.errors import GuestContractError, GuestDependencyError
from tirosh_guest_tools.infrastructure import common
from tirosh_guest_tools.domain.operations import ComposeAction


def test_load_runtime_env_exports_recorder_ingress_send_data_mode(
    monkeypatch: Any,
    tmp_path: Any,
) -> None:
    runtime_config = type(
        "RuntimeConfig",
        (),
        {
            "redis_host": "redis",
            "redis_port": 6379,
            "trust_proxy": True,
            "public_host": "vital.example.test",
            "public_port": 443,
            "admin_password": "secret",
            "vital_files_directory": "/data/vital-files",
        },
    )()
    settings_path = tmp_path / RuntimeFileName.RUNTIME_SETTINGS.value
    settings_path.write_text(
        """
        {
          "recorderIngressSendDataMode": "spool_only",
          "recorderIngressSendDataReplayBatchSize": 8,
          "recorderIngressSendDataReplayMaxMiBPerSecond": 12
        }
        """,
        encoding="utf-8",
    )

    monkeypatch.setattr(compose, "DEPLOY_DIR", tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_MODE", raising=False)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE", raising=False)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND", raising=False)

    compose.load_runtime_env()

    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_MODE"] == "spool_only"
    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE"] == "8"
    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND"]
        == str(12 * 1024 * 1024)
    )
    assert not (tmp_path / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value).exists()


def test_load_runtime_env_writes_compose_runtime_memory_limits(
    monkeypatch: Any,
    tmp_path: Any,
) -> None:
    runtime_config = type(
        "RuntimeConfig",
        (),
        {
            "redis_host": "redis",
            "redis_port": 6379,
            "trust_proxy": True,
            "public_host": "vital.example.test",
            "public_port": 443,
            "admin_password": "secret",
            "vital_files_directory": "/data/vital-files",
        },
    )()
    (tmp_path / RuntimeFileName.RUNTIME_SETTINGS.value).write_text(
        """
        {
          "containerMemoryLimitsEnabled": true,
          "vitalServerContainerMemoryLimitMiB": 4096,
          "recorderIngressContainerMemoryLimitMiB": 512,
          "redisContainerMemoryLimitMiB": 1024
        }
        """,
        encoding="utf-8",
    )

    monkeypatch.setattr(compose, "DEPLOY_DIR", tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    compose.load_runtime_env()

    assert (tmp_path / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value).read_text(
        encoding="utf-8"
    ) == (
        "services:\n"
        "  app:\n"
        f"    mem_limit: {4096 * 1024 * 1024}\n"
        "  recorder-ingress:\n"
        f"    mem_limit: {512 * 1024 * 1024}\n"
        "  redis:\n"
        f"    mem_limit: {1024 * 1024 * 1024}\n"
    )


def test_load_runtime_env_uses_redis_heavy_default_memory_limits(
    monkeypatch: Any,
    tmp_path: Any,
) -> None:
    runtime_config = type(
        "RuntimeConfig",
        (),
        {
            "redis_host": "redis",
            "redis_port": 6379,
            "trust_proxy": True,
            "public_host": "vital.example.test",
            "public_port": 443,
            "admin_password": "secret",
            "vital_files_directory": "/data/vital-files",
        },
    )()
    (tmp_path / RuntimeFileName.RUNTIME_SETTINGS.value).write_text(
        '{"containerMemoryLimitsEnabled":true}\n',
        encoding="utf-8",
    )

    monkeypatch.setattr(compose, "DEPLOY_DIR", tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    compose.load_runtime_env()

    assert (tmp_path / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value).read_text(
        encoding="utf-8"
    ) == (
        "services:\n"
        "  app:\n"
        f"    mem_limit: {2048 * 1024 * 1024}\n"
        "  recorder-ingress:\n"
        f"    mem_limit: {410 * 1024 * 1024}\n"
        "  redis:\n"
        f"    mem_limit: {3277 * 1024 * 1024}\n"
    )


def test_load_runtime_env_removes_compose_runtime_memory_limits_when_disabled(
    monkeypatch: Any,
    tmp_path: Any,
) -> None:
    runtime_config = type(
        "RuntimeConfig",
        (),
        {
            "redis_host": "redis",
            "redis_port": 6379,
            "trust_proxy": True,
            "public_host": "vital.example.test",
            "public_port": 443,
            "admin_password": "secret",
            "vital_files_directory": "/data/vital-files",
        },
    )()
    (tmp_path / RuntimeFileName.RUNTIME_SETTINGS.value).write_text(
        '{"containerMemoryLimitsEnabled":false}\n',
        encoding="utf-8",
    )
    (tmp_path / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value).write_text(
        "services: {}\n",
        encoding="utf-8",
    )

    monkeypatch.setattr(compose, "DEPLOY_DIR", tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    compose.load_runtime_env()

    assert not (tmp_path / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value).exists()


def test_compose_command_uses_runtime_limits_override_when_present(
    monkeypatch: Any,
    tmp_path: Any,
) -> None:
    (tmp_path / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value).write_text(
        "services: {}\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(common, "DEPLOY_DIR", tmp_path)

    command = common.compose_command(["config"])

    assert command == [
        "docker",
        "compose",
        "--project-name",
        common.PROJECT_NAME,
        "-f",
        str(tmp_path / RuntimeFileName.COMPOSE.value),
        "-f",
        str(tmp_path / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value),
        "config",
    ]


def test_load_runtime_env_defaults_missing_recorder_ingress_mode_to_spool_and_replay(
    monkeypatch: Any,
    tmp_path: Any,
) -> None:
    runtime_config = type(
        "RuntimeConfig",
        (),
        {
            "redis_host": "redis",
            "redis_port": 6379,
            "trust_proxy": True,
            "public_host": "vital.example.test",
            "public_port": 443,
            "admin_password": "secret",
            "vital_files_directory": "/data/vital-files",
        },
    )()
    (tmp_path / RuntimeFileName.RUNTIME_SETTINGS.value).write_text(
        '{"publicHost":"vital.example.test"}\n',
        encoding="utf-8",
    )

    monkeypatch.setattr(compose, "DEPLOY_DIR", tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_MODE", raising=False)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE", raising=False)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND", raising=False)

    compose.load_runtime_env()

    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_MODE"] == "spool_and_replay"
    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE"] == "10"
    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND"]
        == str(20 * 1024 * 1024)
    )


def test_load_runtime_env_rejects_invalid_recorder_ingress_mode(
    monkeypatch: Any,
    tmp_path: Any,
) -> None:
    runtime_config = type(
        "RuntimeConfig",
        (),
        {
            "redis_host": "redis",
            "redis_port": 6379,
            "trust_proxy": True,
            "public_host": "vital.example.test",
            "public_port": 443,
            "admin_password": "secret",
            "vital_files_directory": "/data/vital-files",
        },
    )()
    (tmp_path / RuntimeFileName.RUNTIME_SETTINGS.value).write_text(
        '{"recorderIngressSendDataMode":"mirrorish"}\n',
        encoding="utf-8",
    )

    monkeypatch.setattr(compose, "DEPLOY_DIR", tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    with pytest.raises(GuestContractError) as error:
        compose.load_runtime_env()

    assert error.value.code == "runtime-settings-recorder-ingress-send-data-mode-invalid"


def test_load_runtime_env_rejects_invalid_recorder_ingress_replay_settings(
    monkeypatch: Any,
    tmp_path: Any,
) -> None:
    runtime_config = type(
        "RuntimeConfig",
        (),
        {
            "redis_host": "redis",
            "redis_port": 6379,
            "trust_proxy": True,
            "public_host": "vital.example.test",
            "public_port": 443,
            "admin_password": "secret",
            "vital_files_directory": "/data/vital-files",
        },
    )()
    (tmp_path / RuntimeFileName.RUNTIME_SETTINGS.value).write_text(
        '{"recorderIngressSendDataReplayMaxMiBPerSecond":0}\n',
        encoding="utf-8",
    )

    monkeypatch.setattr(compose, "DEPLOY_DIR", tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    with pytest.raises(GuestContractError) as error:
        compose.load_runtime_env()

    assert (
        error.value.code
        == "runtime-settings-recorder-ingress-send-data-replay-max-mib-invalid"
    )


def test_stop_compose_action_stops_services_in_explicit_order(monkeypatch: Any) -> None:
    events: list[str] = []

    monkeypatch.setattr(compose, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(compose, "mount_vital_files_share", lambda: None)
    monkeypatch.setattr(compose, "load_runtime_env", lambda: object())

    def compose_stub(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        events.append(
            "compose:"
            + " ".join(arguments)
            + f":timeout={kwargs.get('timeout_seconds')}"
        )
        if arguments == ["config", "--services"]:
            services = "\n".join(service.value for service in ComposeService)
            return subprocess.CompletedProcess(arguments, 0, services, "")
        return subprocess.CompletedProcess(arguments, 0, "", "")

    monkeypatch.setattr(compose, "compose", compose_stub)
    monkeypatch.setattr(compose, "run", lambda arguments: events.append("sync"))

    compose.run_compose_action(ComposeAction.STOP)

    assert events == [
        "compose:config --services:timeout=None",
        "compose:stop --timeout 30 testkit:timeout=40",
        "compose:stop --timeout 30 edge:timeout=40",
        "compose:stop --timeout 30 swagger-ui:timeout=40",
        "compose:stop --timeout 30 redis-ui:timeout=40",
        "compose:stop --timeout 30 recorder-ingress:timeout=40",
        "compose:stop --timeout 30 vitaldb-observer:timeout=40",
        "compose:stop --timeout 30 redis-relay:timeout=40",
        "compose:stop --timeout 90 app:timeout=100",
        "compose:stop --timeout 60 redis:timeout=70",
        "sync",
    ]


def test_stop_compose_action_records_absent_services_without_stopping(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(compose, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(compose, "mount_vital_files_share", lambda: None)
    monkeypatch.setattr(compose, "load_runtime_env", lambda: object())

    def compose_stub(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        events.append("compose:" + " ".join(arguments))
        if arguments == ["config", "--services"]:
            return subprocess.CompletedProcess(arguments, 0, "app\nredis\n", "")
        return subprocess.CompletedProcess(arguments, 0, "", "")

    monkeypatch.setattr(compose, "compose", compose_stub)
    monkeypatch.setattr(compose, "run", lambda arguments: events.append("sync"))

    compose.run_compose_action(ComposeAction.STOP)

    assert events == [
        "compose:config --services",
        "compose:stop --timeout 90 app",
        "compose:stop --timeout 60 redis",
        "sync",
    ]


def test_compose_services_captures_command_output(monkeypatch: Any) -> None:
    run_calls: list[dict[str, object]] = []

    def run_stub(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        run_calls.append(kwargs)
        return subprocess.CompletedProcess(arguments, 0, "app\nredis\n", "")

    monkeypatch.setattr(compose, "run", run_stub)

    assert compose.compose_services() == {"app", "redis"}
    assert run_calls == [
        {
            "check": True,
            "stdout": subprocess.PIPE,
            "stderr": subprocess.PIPE,
            "timeout_seconds": None,
        }
    ]


def test_compose_services_reports_missing_stdout(monkeypatch: Any) -> None:
    monkeypatch.setattr(
        compose,
        "compose",
        lambda *args, **kwargs: subprocess.CompletedProcess(args, 0, None, ""),
    )

    with pytest.raises(GuestDependencyError) as error:
        compose.compose_services()

    assert error.value.code == "guest-compose-services-output-missing"
    assert "docker compose config --services did not provide stdout" in str(error.value)


def test_compose_services_reports_empty_stdout(monkeypatch: Any) -> None:
    monkeypatch.setattr(
        compose,
        "compose",
        lambda *args, **kwargs: subprocess.CompletedProcess(args, 0, "\n", ""),
    )

    with pytest.raises(GuestDependencyError) as error:
        compose.compose_services()

    assert error.value.code == "guest-compose-services-output-empty"
    assert "docker compose config --services produced empty stdout" in str(error.value)


def test_stop_compose_action_reports_timeout_as_dependency_failure(
    monkeypatch: Any,
) -> None:
    monkeypatch.setattr(compose, "mount_runtime_share", lambda: None)
    monkeypatch.setattr(compose, "mount_vital_files_share", lambda: None)
    monkeypatch.setattr(compose, "load_runtime_env", lambda: object())

    def timeout_compose(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments == ["config", "--services"]:
            return subprocess.CompletedProcess(arguments, 0, "app\nredis\n", "")
        if arguments == ["ps", "--all", "--format", "json"]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                "\n".join(
                    [
                        '{"Service":"app","Name":"vitalserver-app-1","State":"running","Health":"healthy"}',
                        '{"Service":"redis","Name":"vitalserver-redis-1","State":"running","Health":"healthy"}',
                    ]
                ),
                "",
            )
        raise subprocess.TimeoutExpired(arguments, kwargs["timeout_seconds"])

    monkeypatch.setattr(compose, "compose", timeout_compose)

    with pytest.raises(GuestDependencyError) as error:
        compose.run_compose_action(ComposeAction.STOP)

    assert error.value.code == "compose-stop-timeout"
    assert (
        "docker compose stop timed out while stopping app after 100s"
        in error.value.message
    )
    assert error.value.details["remainingServices"] == ["app", "redis"]

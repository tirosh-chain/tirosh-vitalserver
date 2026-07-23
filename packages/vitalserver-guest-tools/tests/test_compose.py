from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Any

import pytest
import yaml

from tirosh_guest_tools.application import compose
from tirosh_guest_tools.contracts import ComposeService, RuntimeFileName
from tirosh_guest_tools.domain.errors import GuestContractError, GuestDependencyError
from tirosh_guest_tools.domain.operations import ComposeAction
from tirosh_guest_tools.infrastructure import common


def configure_compose_paths(monkeypatch: Any, root: Path) -> None:
    monkeypatch.setattr(compose, "DEPLOY_DIR", root)
    monkeypatch.setattr(
        compose,
        "RUNTIME_CONFIG_FILE",
        root / RuntimeFileName.RUNTIME_CONFIG.value,
    )
    monkeypatch.setattr(
        compose,
        "RUNTIME_SETTINGS_FILE",
        root / RuntimeFileName.RUNTIME_SETTINGS.value,
    )
    monkeypatch.setattr(
        compose,
        "COMPOSE_RUNTIME_LIMITS_FILE",
        root / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value,
    )
    monkeypatch.setattr(compose, "COMPOSE_ENVIRONMENT_FILE", root / "compose.env")


def test_container_bind_source_directories_cover_compose_runtime_binds() -> None:
    compose_path = (
        Path(__file__).resolve().parents[3]
        / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
    )
    document = yaml.safe_load(compose_path.read_text(encoding="utf-8"))
    assert isinstance(document, dict)
    services = document.get("services")
    assert isinstance(services, dict)

    runtime_root = str(common.RUNTIME_DIR)
    runtime_bind_sources: set[str] = set()
    for service in services.values():
        assert isinstance(service, dict)
        volumes = service.get("volumes", [])
        assert isinstance(volumes, list)
        for volume in volumes:
            if not isinstance(volume, dict) or volume.get("type") != "bind":
                continue
            source = volume.get("source")
            if isinstance(source, str):
                match = re.fullmatch(r"\$\{[A-Z0-9_]+:-(.+)\}", source)
                explicit_source = match.group(1) if match else source
                if explicit_source.startswith(runtime_root + "/"):
                    runtime_bind_sources.add(explicit_source)

    prepared_sources = {
        str(path)
        for path in common.container_bind_source_directories(common.RUNTIME_DIR)
    }
    assert runtime_bind_sources == prepared_sources


def test_lab_container_can_read_mounted_vital_files() -> None:
    compose_path = (
        Path(__file__).resolve().parents[3]
        / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
    )
    document = yaml.safe_load(compose_path.read_text(encoding="utf-8"))
    assert isinstance(document, dict)
    services = document.get("services")
    assert isinstance(services, dict)

    expected_source = "${VITALSERVER_VITAL_FILES_DIR:-/mnt/tirosh-vital-files}"
    app_bind = bind_volume(
        services,
        service="app",
        target="/opt/vitalserver/vital_files",
    )
    lab_bind = bind_volume(
        services,
        service="lab",
        target="/mnt/tirosh-vital-files",
    )

    assert app_bind["source"] == expected_source
    assert lab_bind["source"] == expected_source
    assert lab_bind["read_only"] is True


def test_runtime_compose_includes_postgres_service() -> None:
    compose_path = (
        Path(__file__).resolve().parents[3]
        / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
    )
    document = yaml.safe_load(compose_path.read_text(encoding="utf-8"))
    assert isinstance(document, dict)
    services = document.get("services")
    assert isinstance(services, dict)
    volumes = document.get("volumes")
    assert isinstance(volumes, dict)

    postgres = services.get("postgres")
    assert isinstance(postgres, dict)
    assert postgres["image"] == "postgres:16-alpine"
    assert postgres["environment"]["POSTGRES_DB"] == "vitalserver"
    assert postgres["ports"] == ["127.0.0.1:15432:5432"]
    assert "postgres-data" in volumes


def test_runtime_compose_gates_products_on_postgres_migration() -> None:
    compose_path = (
        Path(__file__).resolve().parents[3]
        / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
    )
    document = yaml.safe_load(compose_path.read_text(encoding="utf-8"))
    services = document["services"]

    migration = services["postgres-migrate"]
    assert migration["image"] == "vitalserver-postgres-migrator:0.2.0"
    assert migration["restart"] == "no"
    assert migration["depends_on"]["postgres"]["condition"] == "service_healthy"
    assert migration["environment"]["VITALSERVER_DATABASE_URL"] == (
        "postgresql://vitalserver@postgres:5432/vitalserver"
    )
    assert (
        services["recorder-ingress"]["depends_on"]["postgres-migrate"]["condition"]
        == "service_completed_successfully"
    )
    assert (
        services["lab"]["depends_on"]["postgres-migrate"]["condition"]
        == "service_completed_successfully"
    )


def test_runtime_compose_includes_lab_product_service() -> None:
    compose_path = (
        Path(__file__).resolve().parents[3]
        / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml"
    )
    document = yaml.safe_load(compose_path.read_text(encoding="utf-8"))
    assert isinstance(document, dict)
    services = document.get("services")
    assert isinstance(services, dict)

    lab = services.get("lab")
    assert isinstance(lab, dict)
    assert lab["image"] == "vitalserver-lab:0.2.0"
    assert lab["build"]["dockerfile"] == "apps/vitalserver-lab/Dockerfile"
    assert lab["depends_on"]["postgres"]["condition"] == "service_healthy"
    assert lab["ports"] == ["127.0.0.1:18085:8080"]
    assert lab["environment"]["VITALSERVER_LAB_SESSION_STORE"] == "postgres"
    assert lab["environment"]["VITALSERVER_LAB_DATABASE_URL"] == (
        "postgresql://vitalserver@postgres:5432/vitalserver"
    )
    assert lab["environment"]["PGPASSWORD"] == (
        "${VITALSERVER_POSTGRES_PASSWORD:-vitalserver}"
    )
    assert lab["restart"] == "unless-stopped"


def bind_volume(
    services: dict[str, Any],
    *,
    service: str,
    target: str,
) -> dict[str, Any]:
    service_document = services.get(service)
    assert isinstance(service_document, dict)
    volumes = service_document.get("volumes")
    assert isinstance(volumes, list)
    matches = [
        volume
        for volume in volumes
        if isinstance(volume, dict)
        and volume.get("type") == "bind"
        and volume.get("target") == target
    ]
    assert len(matches) == 1
    return matches[0]


def test_checked_compose_preserves_command_output_and_diagnostics(
    monkeypatch: Any,
) -> None:
    def fake_compose(
        arguments: list[str],
        *,
        check: bool = True,
        timeout_seconds: float | None = None,
        capture_output: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        del timeout_seconds
        del capture_output
        if arguments == ["up", "-d", "app"]:
            raise subprocess.CalledProcessError(
                17,
                ["docker", "compose", "up", "-d", "app"],
                output="created app",
                stderr="dependency failed",
            )
        assert check is False
        if arguments == ["ps", "--all"]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout="app Created",
                stderr="",
            )
        if arguments == ["ps", "--all", "--format", "json"]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout='[{"Service":"app","State":"created"}]',
                stderr="",
            )
        if arguments == ["logs", "--tail=200"]:
            return subprocess.CompletedProcess(
                arguments,
                0,
                stdout="redis ready",
                stderr="",
            )
        raise AssertionError(f"unexpected compose arguments: {arguments}")

    monkeypatch.setattr(compose, "compose", fake_compose)

    with pytest.raises(compose.ComposeCommandError) as error:
        compose.checked_compose(
            ["up", "-d", "app"],
            stage="application service startup",
        )

    assert error.value.code == "guest-compose-command-failed"
    assert "application service startup" in error.value.message
    assert "created app" in error.value.message
    assert "dependency failed" in error.value.message
    assert "app Created" in error.value.message
    assert "redis ready" in error.value.message


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

    configure_compose_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_MODE", raising=False)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE", raising=False)
    monkeypatch.delenv(
        "RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND",
        raising=False,
    )

    compose.load_runtime_env()

    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_MODE"] == "spool_only"
    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE"] == "1000"
    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND"]
        == str(12 * 1024 * 1024)
    )
    assert (tmp_path / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value).exists()


def test_load_runtime_env_materializes_explicit_compose_environment(
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
            "admin_password": 'secret#"value',
            "vital_files_directory": "/data/vital-files",
        },
    )()
    (tmp_path / RuntimeFileName.RUNTIME_SETTINGS.value).write_text(
        "{}\n",
        encoding="utf-8",
    )
    configure_compose_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)
    monkeypatch.setenv("VITALSERVER_HTTP_PORT", "9999")

    compose.load_runtime_env()

    values = {
        name: json.loads(value)
        for name, value in (
            line.split("=", 1)
            for line in (tmp_path / "compose.env").read_text(
                encoding="utf-8"
            ).splitlines()
        )
    }
    assert values["VITALSERVER_ADMIN_PASSWORD"] == 'secret#"value'
    assert values["VITALSERVER_PUBLIC_HOST"] == "vital.example.test"
    assert values["RECORDER_INGRESS_SEND_DATA_MODE"] == "spool_and_replay"
    assert len(values["RECORDER_INGRESS_EXPECTATION_CONTROL_TOKEN"]) >= 32
    assert (
        values["RECORDER_INGRESS_EXPECTATION_CONTROL_TOKEN"]
        == (tmp_path / "recorder-ingress-expectation-control-token")
        .read_text(encoding="utf-8")
        .strip()
    )
    assert "VITALSERVER_HTTP_PORT" not in values


def test_expectation_control_credential_is_stable_and_invalid_state_is_not_replaced(
    tmp_path: Any,
) -> None:
    path = tmp_path / "expectation-token"

    first = compose.ensure_recorder_ingress_expectation_control_token(path)
    second = compose.ensure_recorder_ingress_expectation_control_token(path)

    assert len(first) >= 32
    assert second == first
    assert path.stat().st_mode & 0o777 == 0o600

    path.write_text("short\n", encoding="utf-8")
    with pytest.raises(GuestContractError) as error:
        compose.ensure_recorder_ingress_expectation_control_token(path)
    assert error.value.code == "recorder-expectation-control-credential-invalid"
    assert path.read_text(encoding="utf-8") == "short\n"


def test_load_runtime_env_exports_recorder_ingress_hot_and_cold_path_settings(
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
          "recorderIngress": {
            "sendDataMaxPendingItems": 110000,
            "sendDataMaxPendingMiB": 640,
            "sendDataMaxPayloadMiB": 12,
            "sendDataReplayedMaxItems": 12000,
            "sendDataRealtimeMaxPendingItems": 2400,
            "sendDataReplayIntervalMs": 1500,
            "sendDataReplayMaxAttempts": 4,
            "sendDataReplayTargetTimeoutMs": 7000,
            "sendDataReplayAdaptiveMinConcurrency": 2,
            "sendDataReplayAdaptiveMaxConcurrency": 6,
            "rawArchiveEnabled": false,
            "rawArchiveMaxFileMiB": 768,
            "rawArchiveMaxFiles": 36,
            "rawArchiveAutoExportEnabled": true,
            "rawArchiveAutoExportQuietSeconds": 420,
            "rawArchiveAutoExportScanIntervalSeconds": 90,
            "rawArchiveAutoExportCursorStableSeconds": 120,
            "rawArchiveAutoExportRetryDelaySeconds": 180,
            "rawArchiveAutoExportMaxAttempts": 5,
            "rawArchiveAutoExportRequestTimeoutSeconds": 600
          }
        }
        """,
        encoding="utf-8",
    )

    configure_compose_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    compose.load_runtime_env()

    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS"]
        == "110000"
    )
    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES"] == str(
        640 * 1024 * 1024
    )
    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES"] == str(
        12 * 1024 * 1024
    )
    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAYED_MAX_ITEMS"]
        == "12000"
    )
    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_REALTIME_MAX_PENDING_ITEMS"]
        == "2400"
    )
    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS"] == "1500"
    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_ATTEMPTS"] == "4"
    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_TARGET_TIMEOUT_MS"]
        == "7000"
    )
    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MIN_CONCURRENCY"]
        == "2"
    )
    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_ADAPTIVE_MAX_CONCURRENCY"]
        == "6"
    )
    assert compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_ENABLED"] == "0"
    assert compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILE_BYTES"] == str(
        768 * 1024 * 1024
    )
    assert compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_MAX_FILES"] == "36"
    assert compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_ENABLED"] == "1"
    assert (
        compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_QUIET_MS"]
        == "420000"
    )
    assert (
        compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_SCAN_INTERVAL_MS"]
        == "90000"
    )
    assert (
        compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_CURSOR_STABLE_MS"]
        == "120000"
    )
    assert (
        compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_RETRY_DELAY_MS"]
        == "180000"
    )
    assert (
        compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_MAX_ATTEMPTS"]
        == "5"
    )
    assert (
        compose.os.environ["RECORDER_INGRESS_RAW_ARCHIVE_AUTO_EXPORT_REQUEST_TIMEOUT_MS"]
        == "600000"
    )


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

    configure_compose_paths(monkeypatch, tmp_path)
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

    configure_compose_paths(monkeypatch, tmp_path)
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

    configure_compose_paths(monkeypatch, tmp_path)
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
    monkeypatch.setattr(
        common,
        "COMPOSE_FILE",
        tmp_path / RuntimeFileName.COMPOSE.value,
    )
    monkeypatch.setattr(
        common,
        "COMPOSE_RUNTIME_LIMITS_FILE",
        tmp_path / RuntimeFileName.COMPOSE_RUNTIME_LIMITS.value,
    )

    command = common.compose_command(["config"])

    assert command == [
        "docker",
        "compose",
        "--env-file",
        str(common.COMPOSE_ENVIRONMENT_FILE),
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

    configure_compose_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_MODE", raising=False)
    monkeypatch.delenv("RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE", raising=False)
    monkeypatch.delenv(
        "RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND",
        raising=False,
    )

    compose.load_runtime_env()

    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_MODE"] == "spool_and_replay"
    assert compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE"] == "1000"
    assert (
        compose.os.environ["RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_BYTES_PER_SECOND"]
        == str(20 * 1024 * 1024)
    )
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

    configure_compose_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    with pytest.raises(GuestContractError) as error:
        compose.load_runtime_env()

    assert (
        error.value.code
        == "runtime-settings-recorder-ingress-send-data-mode-invalid"
    )


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

    configure_compose_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    with pytest.raises(GuestContractError) as error:
        compose.load_runtime_env()

    assert (
        error.value.code
        == "runtime-settings-recorder-ingress-send-data-replay-max-mib-invalid"
    )


def test_load_runtime_env_rejects_invalid_recorder_ingress_settings_object(
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
        '{"recorderIngress":{"sendDataMaxPendingItems":0}}\n',
        encoding="utf-8",
    )

    configure_compose_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    with pytest.raises(GuestContractError) as error:
        compose.load_runtime_env()

    assert (
        error.value.code
        == "runtime-settings-recorder-ingress-sendDataMaxPendingItems-invalid"
    )


def test_load_runtime_env_rejects_recorder_ingress_concurrency_inversion(
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
          "recorderIngress": {
            "sendDataReplayAdaptiveMinConcurrency": 4,
            "sendDataReplayAdaptiveMaxConcurrency": 2
          }
        }
        """,
        encoding="utf-8",
    )

    configure_compose_paths(monkeypatch, tmp_path)
    monkeypatch.setattr(compose, "load_config", lambda path: runtime_config)

    with pytest.raises(GuestContractError) as error:
        compose.load_runtime_env()

    assert (
        error.value.code
        == "runtime-settings-recorder-ingress-"
        "sendDataReplayAdaptiveMaxConcurrency-invalid"
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
        "compose:stop --timeout 30 edge:timeout=40",
        "compose:stop --timeout 30 swagger-ui:timeout=40",
        "compose:stop --timeout 30 redis-ui:timeout=40",
        "compose:stop --timeout 30 recorder-ingress:timeout=40",
        "compose:stop --timeout 30 vitaldb-observer:timeout=40",
        "compose:stop --timeout 30 redis-relay:timeout=40",
        "compose:stop --timeout 30 lab:timeout=40",
        "compose:stop --timeout 90 app:timeout=100",
        "compose:stop --timeout 60 postgres:timeout=70",
        "compose:stop --timeout 60 redis:timeout=70",
        "sync",
    ]


def test_start_ordered_starts_postgres_before_product_services(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    def checked_compose_stub(arguments: list[str], *, stage: str) -> None:
        events.append("checked-compose:" + " ".join(arguments) + f":stage={stage}")

    monkeypatch.setattr(compose, "checked_compose", checked_compose_stub)
    monkeypatch.setattr(
        compose,
        "wait_for_postgres",
        lambda: events.append("wait-for-postgres"),
    )
    monkeypatch.setattr(
        compose,
        "wait_for_redis",
        lambda: events.append("wait-for-redis"),
    )
    monkeypatch.setattr(compose, "wait_for_app", lambda: events.append("wait-for-app"))

    compose.start_ordered()

    assert events[:5] == [
        "checked-compose:up --pull never --no-build -d postgres:stage=postgres startup",
        "wait-for-postgres",
        "checked-compose:up --pull never --no-build --no-deps --force-recreate "
        "--abort-on-container-exit --exit-code-from postgres-migrate "
        "postgres-migrate:stage=postgres schema migration",
        "checked-compose:up --pull never --no-build -d redis:stage=redis startup",
        "wait-for-redis",
    ]
    assert (
        "checked-compose:up --pull never --no-build -d app recorder-recovery "
        "recorder-ingress "
        "vitaldb-observer redis-relay lab redis-ui swagger-ui"
        ":stage=application service startup"
    ) in events


def test_up_compose_action_prepares_recorder_ingress_bind_sources(
    monkeypatch: Any,
) -> None:
    events: list[str] = []

    monkeypatch.setattr(
        compose,
        "mount_runtime_share",
        lambda: events.append("mount-runtime-share"),
    )
    monkeypatch.setattr(
        compose,
        "mount_vital_files_share",
        lambda: events.append("mount-vital-files-share"),
    )
    monkeypatch.setattr(compose, "load_runtime_env", lambda: object())
    monkeypatch.setattr(
        compose,
        "prepare_container_bind_source_directories",
        lambda: events.append("prepare-container-bind-source-directories"),
    )
    monkeypatch.setattr(
        compose,
        "start_ordered",
        lambda: events.append("start-ordered"),
    )

    compose.run_compose_action(ComposeAction.UP)

    assert events == [
        "mount-runtime-share",
        "mount-vital-files-share",
        "prepare-container-bind-source-directories",
        "start-ordered",
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


@pytest.mark.parametrize("health", [None, "", "   "])
def test_compose_service_state_maps_unreported_health_explicitly(
    health: str | None,
) -> None:
    row: dict[str, object] = {
        "Service": "app",
        "Name": "vitalserver-app-1",
        "State": "created",
    }
    if health is not None:
        row["Health"] = health

    state = compose.compose_service_state_from_json(row)

    assert state.health == "not_reported"

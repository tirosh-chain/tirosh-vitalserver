from __future__ import annotations

from pathlib import Path

import pytest

from tirosh_guest_tools.domain.errors import GuestContractError
from tirosh_guest_tools.infrastructure.settings import (
    default_settings_text,
    install_default_settings,
    load_settings,
)


def test_load_settings_reads_guest_tools_toml(tmp_path: Path) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
guestHostname = "vital-guest"

[shares]
runtimeTag = "runtime-share"
runtimeMount = "/runtime"
vitalFilesTag = "files-share"
vitalFilesMount = "/files"

[paths]
deployDir = "/runtime/deploy"
runtimeDir = "/runtime/run"
guestToolsHome = "/opt/custom-tools"
pythonWheelDir = "/runtime/wheels"
commandBinDir = "/opt/bin"

[compose]
projectName = "custom-project"
stopTimeoutSeconds = 45

[intervals]
commandPollSeconds = 7
runtimeStateSeconds = 11
observabilitySeconds = 13

[containerLogs]
intervalSeconds = 17
tailLines = "250"
maxBytes = 2048
retainedFiles = 3
rotateCheckLines = 19

[observability]
vitaldbObserverUrl = "http://127.0.0.1:19000/observations"

[logging]
format = "json"
level = "warning"
streamEnabled = false
fileEnabled = true
""".strip()
        + "\n",
        encoding="utf-8",
    )

    settings = load_settings(settings_file)

    assert settings.guest_hostname == "vital-guest"
    assert settings.shares.runtime_tag == "runtime-share"
    assert settings.shares.runtime_mount == Path("/runtime")
    assert settings.paths.python_wheel_dir == Path("/runtime/wheels")
    assert settings.compose.project_name == "custom-project"
    assert settings.compose.stop_timeout_seconds == 45
    assert settings.intervals.command_poll_seconds == 7
    assert settings.container_logs.tail_lines == "250"
    assert settings.observability.vitaldb_observer_url.endswith("/observations")
    assert settings.logging.level == "warning"
    assert settings.logging.stream_enabled is False


def test_load_settings_uses_packaged_defaults_when_file_is_missing(
    tmp_path: Path,
) -> None:
    settings = load_settings(tmp_path / "missing.toml")

    assert settings.shares.runtime_mount == Path("/mnt/tirosh")
    assert settings.paths.deploy_dir == Path("/mnt/tirosh/deploy")
    assert settings.compose.project_name == "vitalserver"
    assert settings.intervals.command_poll_seconds == 3
    assert settings.logging.format == "json"
    assert settings.logging.file_enabled is True


def test_load_settings_merges_explicit_override_with_packaged_defaults(
    tmp_path: Path,
) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
[intervals]
commandPollSeconds = 9

[logging]
level = "debug"
""".strip()
        + "\n",
        encoding="utf-8",
    )

    settings = load_settings(settings_file)

    assert settings.intervals.command_poll_seconds == 9
    assert settings.intervals.runtime_state_seconds == 5
    assert settings.logging.level == "debug"
    assert settings.logging.format == "json"


def test_install_default_settings_writes_packaged_toml(tmp_path: Path) -> None:
    settings_file = tmp_path / "guest-tools.toml"

    install_default_settings(settings_file)

    assert settings_file.read_text(encoding="utf-8") == default_settings_text()


def test_load_settings_rejects_invalid_value_type(tmp_path: Path) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
[intervals]
commandPollSeconds = "fast"
""".strip()
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(GuestContractError, match="commandPollSeconds") as error:
        load_settings(settings_file)
    assert error.value.code == "guest-tools-setting-type-invalid"

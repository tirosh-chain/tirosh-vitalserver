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
runtimeMountMode = "native"
vitalFilesTag = "files-share"
vitalFilesMount = "/files"
vitalFilesMountMode = "virtiofs"

[paths]
deployDir = "/runtime/deploy"
runtimeDir = "/runtime/run"
controlStateDir = "/runtime/control"
composeFile = "/runtime/deploy/compose.yaml"
runtimeConfigFile = "/etc/vitalserver/runtime-config.json"
runtimeSettingsFile = "/etc/vitalserver/runtime-settings.json"
composeRuntimeLimitsFile = "/runtime/run/compose.runtime-limits.yaml"
guestToolsHome = "/opt/custom-tools"
pythonWheelDir = "/runtime/wheels"
commandBinDir = "/opt/bin"

[controlStore]
root = "/runtime"
requiresMount = false

[compose]
projectName = "custom-project"
environmentFile = "/etc/vitalserver/runtime.env"
stopTimeoutSeconds = 45

[intervals]
commandPollSeconds = 7
runtimeObservationSeconds = 11
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
    assert settings.shares.runtime_mount_mode == "native"
    assert settings.shares.vital_files_mount_mode == "virtiofs"
    assert settings.paths.python_wheel_dir == Path("/runtime/wheels")
    assert settings.paths.control_state_dir == Path("/runtime/control")
    assert settings.control_store.root == Path("/runtime")
    assert settings.control_store.requires_mount is False
    assert settings.paths.runtime_config_file == Path(
        "/etc/vitalserver/runtime-config.json"
    )
    assert settings.compose.project_name == "custom-project"
    assert settings.compose.environment_file == Path("/etc/vitalserver/runtime.env")
    assert settings.compose.stop_timeout_seconds == 45
    assert settings.intervals.command_poll_seconds == 7
    assert settings.intervals.runtime_observation_seconds == 11
    assert settings.container_logs.tail_lines == "250"
    assert settings.observability.vitaldb_observer_url.endswith("/observations")
    assert settings.logging.level == "warning"
    assert settings.logging.stream_enabled is False


def test_load_settings_uses_packaged_defaults_when_file_is_missing(
    tmp_path: Path,
) -> None:
    settings = load_settings(tmp_path / "missing.toml")

    assert settings.shares.runtime_mount == Path("/mnt/tirosh")
    assert settings.shares.runtime_mount_mode == "virtiofs"
    assert settings.paths.deploy_dir == Path("/mnt/tirosh/deploy")
    assert settings.paths.control_state_dir == Path("/mnt/runtime/control")
    assert settings.control_store.root == Path("/mnt/runtime")
    assert settings.control_store.requires_mount is True
    assert settings.compose.project_name == "vitalserver"
    assert settings.compose.stop_timeout_seconds == 120
    assert settings.intervals.command_poll_seconds == 3
    assert (
        settings.observability.vitaldb_observer_url
        == "http://127.0.0.1:18084/api/v1/observations"
    )
    assert settings.logging.format == "json"
    assert settings.logging.file_enabled is True


def test_load_settings_rejects_missing_required_config_file(tmp_path: Path) -> None:
    settings_file = tmp_path / "missing.toml"

    with pytest.raises(GuestContractError) as error:
        load_settings(settings_file, require_config_file=True)

    assert error.value.code == "guest-tools-settings-missing"


def test_load_settings_reports_invalid_toml_as_config_failure(tmp_path: Path) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text("[paths\n", encoding="utf-8")

    with pytest.raises(GuestContractError) as error:
        load_settings(settings_file)

    assert error.value.code == "guest-tools-settings-invalid"


def test_load_settings_reports_unreadable_config_file(tmp_path: Path) -> None:
    with pytest.raises(GuestContractError) as error:
        load_settings(tmp_path, require_config_file=True)

    assert error.value.code == "guest-tools-settings-unreadable"


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
    assert settings.intervals.runtime_observation_seconds == 5
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


def test_load_settings_rejects_control_state_under_shared_deploy_directory(
    tmp_path: Path,
) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
[paths]
controlStateDir = "/mnt/tirosh/deploy/control"
""".strip()
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(GuestContractError) as error:
        load_settings(settings_file)

    assert error.value.code == "guest-tools-control-state-path-invalid"


def test_load_settings_rejects_relative_control_state_directory(
    tmp_path: Path,
) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
[paths]
controlStateDir = "control"
""".strip()
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(GuestContractError) as error:
        load_settings(settings_file)

    assert error.value.code == "guest-tools-control-state-path-invalid"


def test_load_settings_rejects_control_state_under_virtiofs_runtime_mount(
    tmp_path: Path,
) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
[paths]
controlStateDir = "/mnt/tirosh/control"
""".strip()
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(GuestContractError) as error:
        load_settings(settings_file)

    assert error.value.code == "guest-tools-control-state-path-invalid"


def test_load_settings_rejects_control_state_outside_declared_root(
    tmp_path: Path,
) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
[paths]
controlStateDir = "/guest-owned/control"

[controlStore]
root = "/platform-owned"
requiresMount = false
""".strip()
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(GuestContractError) as error:
        load_settings(settings_file)

    assert error.value.code == "guest-tools-control-state-path-invalid"


def test_load_settings_rejects_relative_control_store_root(tmp_path: Path) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
[controlStore]
root = "control-root"
requiresMount = false
""".strip()
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(GuestContractError) as error:
        load_settings(settings_file)

    assert error.value.code == "guest-tools-control-state-path-invalid"


def test_load_settings_rejects_filesystem_root_as_control_store_root(
    tmp_path: Path,
) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
[controlStore]
root = "/"
requiresMount = false
""".strip()
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(GuestContractError) as error:
        load_settings(settings_file)

    assert error.value.code == "guest-tools-control-state-path-invalid"


def test_load_settings_rejects_control_store_root_parent_traversal(
    tmp_path: Path,
) -> None:
    settings_file = tmp_path / "guest-tools.toml"
    settings_file.write_text(
        """
[controlStore]
root = "/mnt/runtime/../other"
requiresMount = false
""".strip()
        + "\n",
        encoding="utf-8",
    )

    with pytest.raises(GuestContractError) as error:
        load_settings(settings_file)

    assert error.value.code == "guest-tools-control-state-path-invalid"

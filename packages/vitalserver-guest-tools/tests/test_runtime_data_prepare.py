from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from tirosh_guest_tools.application.runtime_data_prepare import (
    DOCKER_RUNTIME_UNITS,
    SYSTEMD_UNIT_STOP_COMMAND_TIMEOUT_SECONDS,
    SYSTEMD_UNIT_STOP_TIMEOUT_SECONDS,
    VITALSERVER_DOCKER_CONSUMER_UNITS,
    RuntimeDataPrepareContext,
    RuntimeDataPrepareOperations,
    prepare_runtime_data,
    stop_docker_services,
)


def test_prepare_runtime_data_provisions_mount_and_writes_daemon_contract(
    tmp_path: Path,
) -> None:
    context = prepare_context(tmp_path)
    write_metadata(context.deploy_dir, tmp_path)
    commands: list[list[str]] = []
    mounted = False

    def run(arguments: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        nonlocal mounted
        commands.append(arguments)
        if arguments[:2] == ["findmnt", "--json"]:
            if mounted:
                return completed(
                    arguments,
                    json.dumps(
                        {
                            "filesystems": [
                                {
                                    "target": str(tmp_path / "runtime-data"),
                                    "source": "/dev/nvme1n1",
                                    "fstype": "ext4",
                                }
                            ]
                        }
                    ),
                )
            return subprocess.CompletedProcess(arguments, 1, "", "")
        if arguments[:1] == ["findfs"]:
            if mounted:
                return completed(arguments, "/dev/nvme1n1\n")
            return subprocess.CompletedProcess(arguments, 1, "", "")
        if arguments[:1] == ["blkid"]:
            return completed(arguments, "vital-runtime\n")
        if arguments[:1] == ["lsblk"]:
            return completed(
                arguments,
                json.dumps(
                    {
                        "blockdevices": [
                            {
                                "name": "nvme0n1",
                                "path": "/dev/nvme0n1",
                                "type": "disk",
                                "size": 8 * 1024 * 1024 * 1024,
                                "fstype": None,
                                "mountpoints": [None],
                                "children": [{"name": "nvme0n1p1"}],
                            },
                            {
                                "name": "nvme1n1",
                                "path": "/dev/nvme1n1",
                                "type": "disk",
                                "size": 16 * 1024 * 1024 * 1024,
                                "fstype": None,
                                "mountpoints": [None],
                            },
                        ]
                    }
                ),
            )
        if arguments[:1] == ["mkfs.ext4"]:
            return completed(arguments)
        if arguments[:1] == ["mount"]:
            mounted = True
            return completed(arguments)
        if arguments == ["containerd", "config", "default"]:
            return completed(
                arguments,
                "version = 2\n"
                'root = "/var/lib/containerd"\n'
                'state = "/run/containerd"\n',
            )
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            return completed(arguments, "inactive\n")
        return completed(arguments)

    prepare_runtime_data(
        context=context,
        operations=RuntimeDataPrepareOperations(run=run),
    )

    assert [
        "systemctl",
        "stop",
        "--no-block",
        *VITALSERVER_DOCKER_CONSUMER_UNITS,
    ] in commands
    assert [
        "systemctl",
        "stop",
        "--no-block",
        *DOCKER_RUNTIME_UNITS,
    ] in commands
    assert [
        "mkfs.ext4",
        "-F",
        "-L",
        "vital-runtime",
        "/dev/nvme1n1",
    ] in commands
    assert [
        "mount",
        "-t",
        "ext4",
        "/dev/nvme1n1",
        str(tmp_path / "runtime-data"),
    ] in commands
    assert ["systemctl", "daemon-reload"] in commands
    assert json.loads(
        context.docker_daemon_config_path.read_text(encoding="utf-8")
    ) == {"data-root": str(tmp_path / "runtime-data/docker")}
    assert (tmp_path / "runtime-data/docker/tmp").is_dir()
    assert (tmp_path / "runtime-data/containerd").is_dir()
    assert f'root = "{tmp_path / "runtime-data/containerd"}"' in (
        context.containerd_config_path.read_text(encoding="utf-8")
    )
    assert (
        f"LABEL=vital-runtime {tmp_path / 'runtime-data'} ext4 defaults 0 2"
        in context.fstab_path.read_text(encoding="utf-8")
    )


def test_prepare_runtime_data_rejects_conflicting_docker_data_root(
    tmp_path: Path,
) -> None:
    context = prepare_context(tmp_path)
    write_metadata(context.deploy_dir, tmp_path)
    context.docker_daemon_config_path.parent.mkdir(parents=True)
    context.docker_daemon_config_path.write_text(
        json.dumps({"data-root": "/var/lib/docker"}),
        encoding="utf-8",
    )

    def run(arguments: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        if arguments[:2] == ["findmnt", "--json"]:
            return completed(
                arguments,
                json.dumps(
                    {
                        "filesystems": [
                            {
                                "target": str(tmp_path / "runtime-data"),
                                "source": "/dev/nvme1n1",
                                "fstype": "ext4",
                            }
                        ]
                    }
                ),
            )
        if arguments[:1] == ["findfs"]:
            return completed(arguments, "/dev/nvme1n1\n")
        if arguments[:1] == ["blkid"]:
            return completed(arguments, "vital-runtime\n")
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            return completed(arguments, "inactive\n")
        return completed(arguments)

    with pytest.raises(RuntimeError, match="conflicting data-root"):
        prepare_runtime_data(
            context=context,
            operations=RuntimeDataPrepareOperations(run=run),
        )


def test_prepare_runtime_data_rejects_mounted_disk_without_contract_label(
    tmp_path: Path,
) -> None:
    context = prepare_context(tmp_path)
    write_metadata(context.deploy_dir, tmp_path)

    def run(arguments: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        if arguments[:2] == ["findmnt", "--json"]:
            return completed(
                arguments,
                json.dumps(
                    {
                        "filesystems": [
                            {
                                "target": str(tmp_path / "runtime-data"),
                                "source": "/dev/nvme9n1",
                                "fstype": "ext4",
                            }
                        ]
                    }
                ),
            )
        if arguments[:1] == ["blkid"]:
            return completed(arguments, "wrong-runtime-data\n")
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            return completed(arguments, "inactive\n")
        return completed(arguments)

    with pytest.raises(RuntimeError, match="label does not match contract"):
        prepare_runtime_data(
            context=context,
            operations=RuntimeDataPrepareOperations(run=run),
        )


def test_stop_docker_services_uses_warm_stack_deadline_and_inactive_proof() -> None:
    calls: list[tuple[list[str], float | None]] = []

    def run(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        timeout = kwargs.get("timeout_seconds")
        calls.append((arguments, timeout if isinstance(timeout, float) else None))
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            return completed(arguments, "inactive\n")
        return completed(arguments)

    stop_docker_services(RuntimeDataPrepareOperations(run=run))

    assert VITALSERVER_DOCKER_CONSUMER_UNITS[0] == (
        "tirosh-runtime-observation.service"
    )
    assert calls[0] == (
        ["systemctl", "stop", "--no-block", *VITALSERVER_DOCKER_CONSUMER_UNITS],
        SYSTEMD_UNIT_STOP_COMMAND_TIMEOUT_SECONDS,
    )
    docker_stop_index = calls.index(
        (
            ["systemctl", "stop", "--no-block", *DOCKER_RUNTIME_UNITS],
            SYSTEMD_UNIT_STOP_COMMAND_TIMEOUT_SECONDS,
        )
    )
    consumer_state_indexes = [
        calls.index(
            (
                ["systemctl", "show", "--property=ActiveState", "--value", unit],
                30.0,
            )
        )
        for unit in VITALSERVER_DOCKER_CONSUMER_UNITS
    ]
    assert max(consumer_state_indexes) < docker_stop_index


def test_stop_deadline_exceeds_compose_unit_timeout_contract() -> None:
    repository_root = Path(__file__).parents[3]
    compose_unit = (
        repository_root
        / "apps/vitalserver-macos-runtime/Support/Guest/systemd"
        / "tirosh-vitalserver-compose.service"
    )
    timeout_line = next(
        line
        for line in compose_unit.read_text(encoding="utf-8").splitlines()
        if line.startswith("TimeoutStopSec=")
    )
    compose_timeout_seconds = float(timeout_line.partition("=")[2])

    assert compose_timeout_seconds < SYSTEMD_UNIT_STOP_TIMEOUT_SECONDS


def test_stop_docker_services_reports_unit_states_after_timeout() -> None:
    timed_out_command = [
        "systemctl",
        "stop",
        "--no-block",
        *VITALSERVER_DOCKER_CONSUMER_UNITS,
    ]

    def run(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments == timed_out_command:
            raise subprocess.TimeoutExpired(
                arguments,
                SYSTEMD_UNIT_STOP_COMMAND_TIMEOUT_SECONDS,
            )
        if arguments[-1] in {
            "tirosh-runtime-observation.service",
            "tirosh-vitalserver-container-logs.service",
        }:
            return completed(arguments, "inactive\n")
        if arguments[-1] == "tirosh-vitalserver-compose.service":
            return completed(arguments, "deactivating\n")
        raise AssertionError(f"unexpected command: {arguments}")

    with pytest.raises(
        RuntimeError,
        match=(
            r"systemd unit stop timed out.*"
            r"tirosh-vitalserver-compose\.service=deactivating"
        ),
    ):
        stop_docker_services(RuntimeDataPrepareOperations(run=run))


def test_stop_docker_services_rejects_non_inactive_unit_after_stop() -> None:
    current_times = iter([0.0, 1.0, SYSTEMD_UNIT_STOP_TIMEOUT_SECONDS + 2.0])

    def run(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            state = "active" if arguments[-1] == "docker.service" else "inactive"
            return completed(arguments, f"{state}\n")
        return completed(arguments)

    with pytest.raises(
        RuntimeError,
        match=r"systemd units did not stop before deadline:.*docker\.service=active",
    ):
        stop_docker_services(
            RuntimeDataPrepareOperations(
                run=run,
                current_time_seconds=current_times.__next__,
                sleep=lambda _: None,
            )
        )


def test_stop_docker_services_preserves_nonzero_stop_failure() -> None:
    failed_command = [
        "systemctl",
        "stop",
        "--no-block",
        *VITALSERVER_DOCKER_CONSUMER_UNITS,
    ]

    def run(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments == failed_command:
            return subprocess.CompletedProcess(
                arguments,
                5,
                "",
                "dependency stop failed",
            )
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            return completed(arguments, "inactive\n")
        raise AssertionError(f"unexpected command: {arguments}")

    with pytest.raises(
        RuntimeError,
        match=r"systemd unit stop failed:.*exit=5.*dependency stop failed",
    ):
        stop_docker_services(RuntimeDataPrepareOperations(run=run))


def test_stop_docker_services_waits_for_deactivating_unit() -> None:
    compose_states = iter(["deactivating", "inactive"])
    sleeps: list[float] = []

    def run(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            if arguments[-1] == "tirosh-vitalserver-compose.service":
                return completed(arguments, f"{next(compose_states)}\n")
            return completed(arguments, "inactive\n")
        return completed(arguments)

    stop_docker_services(
        RuntimeDataPrepareOperations(
            run=run,
            current_time_seconds=iter([0.0, 1.0, 2.0]).__next__,
            sleep=sleeps.append,
        )
    )

    assert sleeps == [1.0]


def test_stop_docker_services_resets_failed_unit_only_after_processes_exit() -> None:
    compose_states = iter(["failed", "inactive"])
    commands: list[list[str]] = []

    def run(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        commands.append(arguments)
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            if arguments[-1] == "tirosh-vitalserver-compose.service":
                return completed(arguments, f"{next(compose_states)}\n")
            return completed(arguments, "inactive\n")
        if arguments[:3] == ["systemctl", "show", "--property=MainPID"]:
            return completed(arguments, "0\n")
        if arguments[:3] == ["systemctl", "show", "--property=ControlPID"]:
            return completed(arguments, "0\n")
        return completed(arguments)

    stop_docker_services(RuntimeDataPrepareOperations(run=run))

    assert [
        "systemctl",
        "reset-failed",
        "tirosh-vitalserver-compose.service",
    ] in commands


def test_stop_docker_services_does_not_reset_failed_unit_with_live_control_process() -> (
    None
):
    current_times = iter([0.0, SYSTEMD_UNIT_STOP_TIMEOUT_SECONDS + 1.0])

    def run(
        arguments: list[str],
        **kwargs: object,
    ) -> subprocess.CompletedProcess[str]:
        if arguments[:3] == ["systemctl", "show", "--property=ActiveState"]:
            state = (
                "failed"
                if arguments[-1] == "tirosh-vitalserver-compose.service"
                else "inactive"
            )
            return completed(arguments, f"{state}\n")
        if arguments[:3] == ["systemctl", "show", "--property=MainPID"]:
            return completed(arguments, "0\n")
        if arguments[:3] == ["systemctl", "show", "--property=ControlPID"]:
            return completed(arguments, "42\n")
        if arguments[:2] == ["systemctl", "reset-failed"]:
            raise AssertionError("live failed unit must not be reset")
        return completed(arguments)

    with pytest.raises(
        RuntimeError,
        match=r"systemd units did not stop before deadline:.*compose\.service=failed",
    ):
        stop_docker_services(
            RuntimeDataPrepareOperations(
                run=run,
                current_time_seconds=current_times.__next__,
                sleep=lambda _: None,
            )
        )


def test_runtime_data_prepare_cli_is_registered() -> None:
    pyproject = Path(__file__).parents[1] / "pyproject.toml"
    assert "tirosh-vitalserver-runtime-data-prepare" in pyproject.read_text(
        encoding="utf-8"
    )


def prepare_context(tmp_path: Path) -> RuntimeDataPrepareContext:
    return RuntimeDataPrepareContext(
        deploy_dir=tmp_path / "deploy",
        docker_daemon_config_path=tmp_path / "etc/docker/daemon.json",
        containerd_config_path=tmp_path / "etc/containerd/config.toml",
        fstab_path=tmp_path / "etc/fstab",
    )


def write_metadata(deploy_dir: Path, tmp_path: Path) -> None:
    metadata = deploy_dir / "build-metadata/rootfs-input.json"
    metadata.parent.mkdir(parents=True)
    metadata.write_text(
        json.dumps(
            {
                "runtimeData": {
                    "diskImageName": "runtime-data.img",
                    "diskSize": "16G",
                    "filesystemLabel": "vital-runtime",
                    "mountPath": str(tmp_path / "runtime-data"),
                    "dockerDataRoot": str(tmp_path / "runtime-data/docker"),
                    "containerdRoot": str(tmp_path / "runtime-data/containerd"),
                },
            }
        ),
        encoding="utf-8",
    )


def completed(
    arguments: list[str],
    stdout: str = "",
) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(arguments, 0, stdout, "")

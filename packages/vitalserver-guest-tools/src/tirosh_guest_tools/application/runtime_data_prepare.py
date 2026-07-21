from __future__ import annotations

import json
import subprocess
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tirosh_guest_tools.application.runtime_data_contract import (
    RuntimeDataContract,
    prepare_runtime_data_directories,
)
from tirosh_guest_tools.contracts import RuntimeService
from tirosh_guest_tools.infrastructure.common import DEPLOY_DIR

VITALSERVER_DOCKER_CONSUMER_UNITS = (
    RuntimeService.RUNTIME_OBSERVATION.value,
    RuntimeService.CONTAINER_LOGS.value,
    RuntimeService.COMPOSE.value,
)
DOCKER_RUNTIME_UNITS = (
    "docker.service",
    "docker.socket",
    "containerd.service",
)
SYSTEMD_UNIT_STOP_TIMEOUT_SECONDS = 180.0
SYSTEMD_UNIT_STOP_COMMAND_TIMEOUT_SECONDS = 30.0
SYSTEMD_UNIT_STATE_READ_TIMEOUT_SECONDS = 30.0
SYSTEMD_UNIT_STATE_POLL_SECONDS = 1.0


@dataclass(frozen=True)
class RuntimeDataPrepareContext:
    deploy_dir: Path
    docker_daemon_config_path: Path
    containerd_config_path: Path
    fstab_path: Path


@dataclass(frozen=True)
class RuntimeDataPrepareOperations:
    run: Callable[..., subprocess.CompletedProcess[str]]
    current_time_seconds: Callable[[], float] = time.monotonic
    sleep: Callable[[float], None] = time.sleep


def default_context() -> RuntimeDataPrepareContext:
    return RuntimeDataPrepareContext(
        deploy_dir=DEPLOY_DIR,
        docker_daemon_config_path=Path("/etc/docker/daemon.json"),
        containerd_config_path=Path("/etc/containerd/config.toml"),
        fstab_path=Path("/etc/fstab"),
    )


def default_operations() -> RuntimeDataPrepareOperations:
    return RuntimeDataPrepareOperations(run=run_command)


def prepare_runtime_data(
    *,
    context: RuntimeDataPrepareContext | None = None,
    operations: RuntimeDataPrepareOperations | None = None,
) -> None:
    context = context or default_context()
    operations = operations or default_operations()
    contract = read_runtime_data_contract(context.deploy_dir)
    stop_docker_services(operations)
    mount_runtime_data_disk(contract, operations)
    prepare_runtime_data_directories(contract)
    write_docker_daemon_config(context.docker_daemon_config_path, contract)
    write_containerd_config(context.containerd_config_path, contract, operations)
    write_fstab(context.fstab_path, contract)
    run_checked(
        operations,
        ["systemctl", "daemon-reload"],
        timeout_seconds=30.0,
    )


def stop_docker_services(operations: RuntimeDataPrepareOperations) -> None:
    stop_systemd_units(operations, VITALSERVER_DOCKER_CONSUMER_UNITS)
    stop_systemd_units(operations, DOCKER_RUNTIME_UNITS)


def stop_systemd_units(
    operations: RuntimeDataPrepareOperations,
    units: tuple[str, ...],
) -> None:
    arguments = ["systemctl", "stop", "--no-block", *units]
    try:
        completed = operations.run(
            arguments,
            check=False,
            timeout_seconds=SYSTEMD_UNIT_STOP_COMMAND_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired as error:
        unit_state_diagnostics = systemd_unit_state_diagnostics(operations, units)
        raise RuntimeError(
            "systemd unit stop timed out: "
            f"units={','.join(units)} "
            f"timeoutSeconds={SYSTEMD_UNIT_STOP_COMMAND_TIMEOUT_SECONDS:g} "
            f"unitStates={unit_state_diagnostics}"
        ) from error

    unit_states = read_systemd_unit_states(operations, units)
    if completed.returncode != 0:
        raise RuntimeError(
            "systemd unit stop failed: "
            f"units={','.join(units)} exit={completed.returncode} "
            f"stdout={completed.stdout} stderr={completed.stderr} "
            f"unitStates={format_systemd_unit_states(unit_states)}"
        )

    deadline = operations.current_time_seconds() + SYSTEMD_UNIT_STOP_TIMEOUT_SECONDS
    while True:
        for unit, state in unit_states.items():
            if state != "failed":
                continue
            main_pid = read_systemd_unit_process_id(
                operations,
                unit=unit,
                property_name="MainPID",
            )
            control_pid = read_systemd_unit_process_id(
                operations,
                unit=unit,
                property_name="ControlPID",
            )
            if main_pid != 0 or control_pid != 0:
                continue
            reset_failed_systemd_unit(operations, unit)
            recovered_state = read_systemd_unit_states(operations, (unit,))[unit]
            if recovered_state != "inactive":
                raise RuntimeError(
                    "systemd unit failed-state recovery did not reach inactive: "
                    f"unit={unit} state={recovered_state}"
                )
            unit_states[unit] = recovered_state

        non_inactive_states = {
            unit: state for unit, state in unit_states.items() if state != "inactive"
        }
        if not non_inactive_states:
            return
        if operations.current_time_seconds() >= deadline:
            raise RuntimeError(
                "systemd units did not stop before deadline: "
                f"timeoutSeconds={SYSTEMD_UNIT_STOP_TIMEOUT_SECONDS:g} "
                f"{format_systemd_unit_states(non_inactive_states)}"
            )
        operations.sleep(SYSTEMD_UNIT_STATE_POLL_SECONDS)
        unit_states = read_systemd_unit_states(operations, units)


def read_systemd_unit_process_id(
    operations: RuntimeDataPrepareOperations,
    *,
    unit: str,
    property_name: str,
) -> int:
    completed = operations.run(
        ["systemctl", "show", f"--property={property_name}", "--value", unit],
        check=False,
        timeout_seconds=SYSTEMD_UNIT_STATE_READ_TIMEOUT_SECONDS,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            "systemd unit process state read failed: "
            f"unit={unit} property={property_name} exit={completed.returncode} "
            f"stdout={completed.stdout} stderr={completed.stderr}"
        )
    raw_value = completed.stdout.strip() if isinstance(completed.stdout, str) else ""
    try:
        value = int(raw_value)
    except ValueError as error:
        raise RuntimeError(
            "systemd unit process state is invalid: "
            f"unit={unit} property={property_name} value={raw_value!r}"
        ) from error
    if value < 0:
        raise RuntimeError(
            "systemd unit process state is invalid: "
            f"unit={unit} property={property_name} value={raw_value!r}"
        )
    return value


def reset_failed_systemd_unit(
    operations: RuntimeDataPrepareOperations,
    unit: str,
) -> None:
    print(
        "Recovering stopped systemd unit from explicit failed state: "
        f"unit={unit} MainPID=0 ControlPID=0"
    )
    completed = operations.run(
        ["systemctl", "reset-failed", unit],
        check=False,
        timeout_seconds=SYSTEMD_UNIT_STATE_READ_TIMEOUT_SECONDS,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            "systemd unit failed-state reset failed: "
            f"unit={unit} exit={completed.returncode} "
            f"stdout={completed.stdout} stderr={completed.stderr}"
        )


def read_systemd_unit_states(
    operations: RuntimeDataPrepareOperations,
    units: tuple[str, ...],
) -> dict[str, str]:
    states: dict[str, str] = {}
    for unit in units:
        completed = operations.run(
            ["systemctl", "show", "--property=ActiveState", "--value", unit],
            check=False,
            timeout_seconds=SYSTEMD_UNIT_STATE_READ_TIMEOUT_SECONDS,
        )
        if completed.returncode != 0:
            raise RuntimeError(
                "systemd unit state read failed: "
                f"unit={unit} exit={completed.returncode} "
                f"stdout={completed.stdout} stderr={completed.stderr}"
            )
        state = completed.stdout.strip() if isinstance(completed.stdout, str) else ""
        if not state or "\n" in state:
            raise RuntimeError(
                f"systemd unit ActiveState is invalid: unit={unit} value={state!r}"
            )
        states[unit] = state
    return states


def systemd_unit_state_diagnostics(
    operations: RuntimeDataPrepareOperations,
    units: tuple[str, ...],
) -> str:
    try:
        return format_systemd_unit_states(read_systemd_unit_states(operations, units))
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        return f"unavailable({error})"


def format_systemd_unit_states(states: dict[str, str]) -> str:
    return ",".join(f"{unit}={state}" for unit, state in states.items())


def read_runtime_data_contract(deploy_dir: Path) -> RuntimeDataContract:
    metadata = deploy_dir / "build-metadata/rootfs-input.json"
    try:
        document = json.loads(metadata.read_text(encoding="utf-8"))
    except OSError as error:
        raise RuntimeError(
            f"runtime data metadata is unreadable: {metadata}: {error}"
        ) from error
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"runtime data metadata is invalid JSON: {metadata}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise RuntimeError(f"runtime data metadata must be an object: {metadata}")
    runtime_data = document.get("runtimeData")
    if not isinstance(runtime_data, dict):
        raise RuntimeError("runtime data metadata is missing runtimeData")
    values: dict[str, str] = {}
    for key in (
        "diskImageName",
        "diskSize",
        "filesystemLabel",
        "mountPath",
        "dockerDataRoot",
        "containerdRoot",
    ):
        value = runtime_data.get(key)
        if not isinstance(value, str) or not value.strip():
            raise RuntimeError(f"runtime data metadata has invalid {key}")
        values[key] = value
    return RuntimeDataContract(
        disk_image_name=values["diskImageName"],
        disk_size=values["diskSize"],
        filesystem_label=values["filesystemLabel"],
        mount_path=values["mountPath"],
        docker_data_root=values["dockerDataRoot"],
        containerd_root=values["containerdRoot"],
    )


def mount_runtime_data_disk(
    contract: RuntimeDataContract,
    operations: RuntimeDataPrepareOperations,
) -> None:
    Path(contract.mount_path).mkdir(parents=True, exist_ok=True)
    if mounted_runtime_data_proof(contract, operations) is not None:
        return
    source = runtime_data_device_source(contract, operations)
    if source is None:
        source = provision_runtime_data_filesystem(contract, operations)
    run_checked(
        operations,
        ["mount", "-t", "ext4", source, contract.mount_path],
        timeout_seconds=30.0,
    )
    if mounted_runtime_data_proof(contract, operations) is None:
        raise RuntimeError("runtime data disk did not mount after preparation")


def mounted_runtime_data_proof(
    contract: RuntimeDataContract,
    operations: RuntimeDataPrepareOperations,
) -> dict[str, Any] | None:
    completed = operations.run(
        ["findmnt", "--json", "--mountpoint", contract.mount_path],
        check=False,
        timeout_seconds=30.0,
    )
    if completed.returncode != 0 or not completed.stdout.strip():
        return None
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"findmnt returned invalid JSON: {error}") from error
    filesystems = document.get("filesystems")
    if not isinstance(filesystems, list) or not filesystems:
        return None
    mount = filesystems[0]
    if not isinstance(mount, dict):
        raise RuntimeError("findmnt filesystem entry is invalid")
    if mount.get("target") != contract.mount_path:
        raise RuntimeError(
            "runtime data mount target mismatch: "
            f"expected={contract.mount_path} actual={mount.get('target')}"
        )
    if mount.get("fstype") not in ("ext4", "ext3", "ext2"):
        raise RuntimeError(
            "runtime data filesystem type is unsupported: "
            f"mountPath={contract.mount_path} fstype={mount.get('fstype')}"
        )
    actual_source = mount.get("source")
    if not isinstance(actual_source, str) or not actual_source.strip():
        raise RuntimeError(
            f"runtime data mount source is missing: mountPath={contract.mount_path}"
        )
    actual_label = filesystem_label(actual_source, operations)
    if actual_label is None:
        raise RuntimeError(
            "runtime data filesystem label is missing: "
            f"expected={contract.filesystem_label} source={actual_source} "
            f"mountPath={contract.mount_path}"
        )
    if actual_label != contract.filesystem_label:
        raise RuntimeError(
            "runtime data mount source label does not match contract: "
            f"expected={contract.filesystem_label} actual={actual_label} "
            f"source={actual_source}"
        )
    return mount


def runtime_data_device_source(
    contract: RuntimeDataContract,
    operations: RuntimeDataPrepareOperations,
) -> str | None:
    completed = operations.run(
        ["findfs", f"LABEL={contract.filesystem_label}"],
        check=False,
        timeout_seconds=30.0,
    )
    source = completed.stdout.strip()
    if completed.returncode == 0 and source:
        return source
    return None


def filesystem_label(
    source: str,
    operations: RuntimeDataPrepareOperations,
) -> str | None:
    completed = operations.run(
        ["blkid", "-s", "LABEL", "-o", "value", source],
        check=False,
        timeout_seconds=30.0,
    )
    label = completed.stdout.strip()
    if completed.returncode == 0 and label:
        return label
    return None


def provision_runtime_data_filesystem(
    contract: RuntimeDataContract,
    operations: RuntimeDataPrepareOperations,
) -> str:
    candidate = runtime_data_blank_disk_candidate(contract, operations)
    run_checked(
        operations,
        ["mkfs.ext4", "-F", "-L", contract.filesystem_label, candidate],
        timeout_seconds=30.0,
    )
    return candidate


def runtime_data_blank_disk_candidate(
    contract: RuntimeDataContract,
    operations: RuntimeDataPrepareOperations,
) -> str:
    completed = run_checked(
        operations,
        [
            "lsblk",
            "--json",
            "--bytes",
            "--output",
            "NAME,PATH,TYPE,SIZE,FSTYPE,MOUNTPOINTS",
        ],
        timeout_seconds=30.0,
    )
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f"lsblk returned invalid JSON: {error}") from error
    blockdevices = document.get("blockdevices")
    if not isinstance(blockdevices, list):
        raise RuntimeError("lsblk output is missing blockdevices")
    expected_size = size_to_bytes(contract.disk_size)
    candidates = [
        str(device["path"])
        for device in blockdevices
        if runtime_data_blank_disk_matches(device, expected_size)
    ]
    if len(candidates) != 1:
        raise RuntimeError(
            "runtime data blank disk candidate count is invalid: "
            f"expected=1 actual={len(candidates)} candidates={candidates}"
        )
    return candidates[0]


def runtime_data_blank_disk_matches(device: object, expected_size: int) -> bool:
    if not isinstance(device, dict):
        return False
    mountpoints = device.get("mountpoints")
    children = device.get("children")
    return (
        device.get("type") == "disk"
        and isinstance(device.get("path"), str)
        and device.get("size") == expected_size
        and not device.get("fstype")
        and (not isinstance(mountpoints, list) or not any(mountpoints))
        and not children
    )


def write_docker_daemon_config(path: Path, contract: RuntimeDataContract) -> None:
    if path.exists():
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise RuntimeError(
                f"Docker daemon config is unreadable: {path}: {error}"
            ) from error
        if not isinstance(document, dict):
            raise RuntimeError(f"Docker daemon config must be an object: {path}")
        existing = document.get("data-root")
        if existing is not None and existing != contract.docker_data_root:
            raise RuntimeError(
                "Docker daemon config has conflicting data-root: "
                f"path={path} expected={contract.docker_data_root} actual={existing}"
            )
    else:
        document = {}
    document["data-root"] = contract.docker_data_root
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


def write_containerd_config(
    path: Path,
    contract: RuntimeDataContract,
    operations: RuntimeDataPrepareOperations,
) -> None:
    completed = run_checked(
        operations,
        ["containerd", "config", "default"],
        timeout_seconds=30.0,
    )
    config = containerd_config_with_root(completed.stdout, contract.containerd_root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(config, encoding="utf-8")


def containerd_config_with_root(config: str, root: str) -> str:
    if not config.strip():
        raise RuntimeError("containerd config default returned empty output")
    lines = config.splitlines()
    replaced = False
    for index, line in enumerate(lines):
        if line.startswith("root = "):
            lines[index] = f'root = "{root}"'
            replaced = True
            break
    if not replaced:
        raise RuntimeError("containerd default config is missing top-level root")
    return "\n".join(lines) + "\n"


def write_fstab(path: Path, contract: RuntimeDataContract) -> None:
    line = f"LABEL={contract.filesystem_label} {contract.mount_path} ext4 defaults 0 2"
    existing = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
    filtered = [
        item
        for item in existing
        if f"LABEL={contract.filesystem_label} " not in item
        and f" {contract.mount_path} " not in item
    ]
    filtered.append(line)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(filtered) + "\n", encoding="utf-8")


def size_to_bytes(value: str) -> int:
    suffix = value[-1:].lower()
    unit = suffix if suffix in ("k", "m", "g") else ""
    number_text = value[:-1] if unit else value
    try:
        number = int(number_text)
    except ValueError as error:
        raise RuntimeError(f"invalid size value: {value}") from error
    multipliers = {
        "": 1,
        "k": 1024,
        "m": 1024 * 1024,
        "g": 1024 * 1024 * 1024,
    }
    if unit not in multipliers:
        raise RuntimeError(f"invalid size unit: {value}")
    return number * multipliers[unit]


def run_checked(
    operations: RuntimeDataPrepareOperations,
    arguments: list[str],
    *,
    timeout_seconds: float,
) -> subprocess.CompletedProcess[str]:
    completed = operations.run(
        arguments,
        check=False,
        timeout_seconds=timeout_seconds,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            "command failed: "
            f"{' '.join(arguments)} exit={completed.returncode} "
            f"stdout={completed.stdout} stderr={completed.stderr}"
        )
    return completed


def run_command(
    arguments: list[str],
    *,
    check: bool = False,
    timeout_seconds: float | None = None,
    **_: object,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        arguments,
        check=check,
        text=True,
        capture_output=True,
        timeout=timeout_seconds,
    )

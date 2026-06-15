from __future__ import annotations

import json
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from tirosh_guest_tools.application.runtime_data_contract import (
    RuntimeDataContract,
    prepare_runtime_data_directories,
)
from tirosh_guest_tools.infrastructure.common import DEPLOY_DIR


@dataclass(frozen=True)
class RuntimeDataPrepareContext:
    deploy_dir: Path
    docker_daemon_config_path: Path
    containerd_config_path: Path
    fstab_path: Path


@dataclass(frozen=True)
class RuntimeDataPrepareOperations:
    run: Callable[..., subprocess.CompletedProcess[str]]


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
    run_checked(
        operations,
        ["systemctl", "stop", "docker.service", "docker.socket", "containerd.service"],
        timeout_seconds=30.0,
    )


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

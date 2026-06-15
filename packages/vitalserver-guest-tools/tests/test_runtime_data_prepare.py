from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

from tirosh_guest_tools.application.runtime_data_prepare import (
    RuntimeDataPrepareContext,
    RuntimeDataPrepareOperations,
    prepare_runtime_data,
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
        return completed(arguments)

    prepare_runtime_data(
        context=context,
        operations=RuntimeDataPrepareOperations(run=run),
    )

    assert [
        "systemctl",
        "stop",
        "docker.service",
        "docker.socket",
        "containerd.service",
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
        return completed(arguments)

    with pytest.raises(RuntimeError, match="label does not match contract"):
        prepare_runtime_data(
            context=context,
            operations=RuntimeDataPrepareOperations(run=run),
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

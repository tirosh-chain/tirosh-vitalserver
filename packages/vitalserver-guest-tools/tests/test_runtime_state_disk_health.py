from __future__ import annotations

import subprocess
from pathlib import Path

from tirosh_guest_tools.adapters.outbound.runtime import collector
from tirosh_guest_tools.domain.runtime_state import (
    GuestRuntimeState,
    RuntimeDiskHealth,
)


def test_runtime_state_document_reports_disk_health() -> None:
    document = GuestRuntimeState(
        updated_at="2026-06-04T00:00:00Z",
        vm_ip=None,
        boot_id=None,
        container_services=None,
        cpu_usage_percent=None,
        guest_http=None,
        memory=None,
        probe_errors=(),
        redis_ui_http=None,
        system_disk=None,
        disk_health=RuntimeDiskHealth(
            root_filesystem_read_only=True,
            kernel_errors=("EXT4-fs error (device vda1): checksum invalid",),
        ),
        swagger_ui_http=None,
        vital_files_disk=None,
        vitaldb_observation=None,
    ).as_json()

    assert document["diskHealth"] == {
        "rootFilesystemReadOnly": True,
        "kernelErrors": ["EXT4-fs error (device vda1): checksum invalid"],
    }


def test_root_filesystem_read_only_reads_proc_mounts(
    monkeypatch,
    tmp_path: Path,
) -> None:
    mounts = tmp_path / "mounts"
    mounts.write_text(
        "proc /proc proc rw,nosuid,nodev,noexec,relatime 0 0\n"
        "/dev/vda1 / ext4 ro,relatime,errors=remount-ro 0 0\n",
        encoding="utf-8",
    )
    monkeypatch.setattr(collector, "Path", lambda value: mounts if value == "/proc/mounts" else Path(value))

    assert collector.root_filesystem_read_only([]) is True


def test_kernel_disk_errors_reports_ext4_metadata_lines(monkeypatch) -> None:
    def fake_run(*_args, **_kwargs):
        return subprocess.CompletedProcess(
            args=["dmesg", "--ctime"],
            returncode=0,
            stdout=(
                "[Thu Jun  4] random line\n"
                "[Thu Jun  4] EXT4-fs error (device vda1): checksum invalid\n"
                "[Thu Jun  4] EXT4-fs (vda1): Remounting filesystem read-only\n"
            ),
            stderr="",
        )

    monkeypatch.setattr(collector.subprocess, "run", fake_run)

    assert collector.kernel_disk_errors([]) == (
        "[Thu Jun  4] EXT4-fs error (device vda1): checksum invalid",
        "[Thu Jun  4] EXT4-fs (vda1): Remounting filesystem read-only",
    )

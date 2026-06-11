import json
import subprocess
from types import SimpleNamespace

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle import (
    require_no_running_runtime,
    running_vm_processes_for_home,
    wait_for_rootfs_ready,
    wait_for_runtime_stopped,
)
from tirosh_vitalserver.devtools.application.inputs import RuntimeVmHomeInput, RuntimeWaitInput


def test_wait_for_runtime_stopped_accepts_stopped_lifecycle(tmp_path):
    lifecycle = tmp_path / "run" / "vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True)
    lifecycle.write_text(json.dumps({"state": "stopped"}), encoding="utf-8")

    result = wait_for_runtime_stopped(
        RuntimeWaitInput(config=tmp_path / "config.toml", vm_home=tmp_path, timeout=1)
    )

    assert result == 0


def test_wait_for_runtime_stopped_rejects_stopping_lifecycle(tmp_path):
    lifecycle = tmp_path / "run" / "vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True)
    lifecycle.write_text(json.dumps({"state": "stopping"}), encoding="utf-8")

    with pytest.raises(SystemExit, match="timed out waiting for VM lifecycle stopped"):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
            )
        )


def test_wait_for_rootfs_ready_rejects_failed_lifecycle(tmp_path):
    lifecycle = tmp_path / "run" / "vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True)
    lifecycle.write_text(
        json.dumps(
            {
                "state": "failed",
                "terminalReason": "guest-kernel-panic",
                "message": "guest kernel panic detected",
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(
        SystemExit,
        match="VM lifecycle failed while waiting for rootfs marker",
    ):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_wait_for_rootfs_ready_rejects_terminal_launcher_log(tmp_path):
    log_file = tmp_path / "logs" / "launcher.log"
    log_file.parent.mkdir(parents=True)
    log_file.write_text(
        "Unable to handle kernel NULL pointer dereference at virtual address 10\n",
        encoding="utf-8",
    )

    with pytest.raises(
        SystemExit,
        match="VM launcher log shows terminal guest failure",
    ):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_wait_for_rootfs_ready_rejects_kernel_panic_log(tmp_path):
    log_file = tmp_path / "logs" / "launcher.log"
    log_file.parent.mkdir(parents=True)
    log_file.write_text(
        "[ 155.971753] Kernel panic - not syncing: Attempted to kill init!\n",
        encoding="utf-8",
    )

    with pytest.raises(
        SystemExit,
        match="VM launcher log shows terminal guest failure",
    ):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_running_vm_processes_for_home_reads_explicit_vm_home(monkeypatch, tmp_path):
    def fake_run(command, text, capture_output, check):
        assert command == ["ps", "eww", "-axo", "pid=,command="]
        return SimpleNamespace(
            returncode=0,
            stdout=(
                "101 /path/vitalserver-vm start VITALSERVER_VM_HOME=/other\n"
                f"202 /path/vitalserver-vm start VITALSERVER_VM_HOME={tmp_path}\n"
                f"303 /path/vitalserver-vm start VITALSERVER_VM_HOME={tmp_path}\n"
            ),
            stderr="",
        )

    monkeypatch.setattr(subprocess, "run", fake_run)

    assert running_vm_processes_for_home(tmp_path) == [202, 303]


def test_running_vm_processes_for_home_does_not_hide_process_read_failure(
    monkeypatch,
    tmp_path,
):
    def fake_run(command, text, capture_output, check):
        return SimpleNamespace(returncode=1, stdout="", stderr="ps denied")

    monkeypatch.setattr(subprocess, "run", fake_run)

    with pytest.raises(SystemExit, match="failed to inspect running VM processes"):
        running_vm_processes_for_home(tmp_path)


def test_require_no_running_runtime_rejects_stale_vm_process(monkeypatch, tmp_path):
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".repo_root",
        lambda: tmp_path,
    )
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".running_vm_processes_for_home",
        lambda vm_home: [1234],
    )

    with pytest.raises(SystemExit, match="VM launcher process is still running"):
        require_no_running_runtime(
            RuntimeVmHomeInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path / "vm",
            )
        )


def test_require_no_running_runtime_accepts_no_process(monkeypatch, tmp_path):
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".repo_root",
        lambda: tmp_path,
    )
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )

    result = require_no_running_runtime(
        RuntimeVmHomeInput(
            config=tmp_path / "config.toml",
            vm_home=tmp_path / "vm",
        )
    )

    assert result == 0

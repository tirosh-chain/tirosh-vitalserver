import json
import subprocess
from types import SimpleNamespace

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle import (
    begin_runtime_boot_smoke_run,
    require_no_running_runtime,
    running_vm_processes_for_home,
    wait_for_rootfs_ready,
    wait_for_runtime_boot_smoke,
    wait_for_runtime_stopped,
)
from tirosh_vitalserver.devtools.application.inputs import (
    RuntimeBootSmokeRunInput,
    RuntimeVmHomeInput,
    RuntimeWaitInput,
)


def test_wait_for_runtime_stopped_accepts_stopped_lifecycle(tmp_path):
    lifecycle = tmp_path / "run" / "vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True)
    lifecycle.write_text(json.dumps({"state": "stopped"}), encoding="utf-8")

    result = wait_for_runtime_stopped(
        RuntimeWaitInput(config=tmp_path / "config.toml", vm_home=tmp_path, timeout=1)
    )

    assert result == 0


def test_wait_for_runtime_stopped_rejects_stopping_lifecycle_with_running_process(
    monkeypatch,
    tmp_path,
):
    lifecycle = tmp_path / "run" / "vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True)
    lifecycle.write_text(json.dumps({"state": "stopping"}), encoding="utf-8")
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".running_vm_processes_for_home",
        lambda vm_home: [1234],
    )

    with pytest.raises(SystemExit, match="timed out waiting for VM lifecycle stopped"):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
            )
        )


def test_wait_for_runtime_stopped_accepts_stopping_lifecycle_without_process(
    monkeypatch,
    tmp_path,
):
    lifecycle = tmp_path / "run" / "vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True)
    lifecycle.write_text(json.dumps({"state": "stopping"}), encoding="utf-8")
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )

    result = wait_for_runtime_stopped(
        RuntimeWaitInput(config=tmp_path / "config.toml", vm_home=tmp_path, timeout=1)
    )

    assert result == 0


def test_wait_for_runtime_stopped_rejects_failed_lifecycle(tmp_path):
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

    with pytest.raises(SystemExit, match="VM lifecycle failed while waiting"):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_wait_for_rootfs_ready_accepts_matching_marker_and_manifest(tmp_path):
    write_rootfs_manifest(tmp_path, run_id="run-test")
    write_rootfs_marker(tmp_path, run_id="run-test")

    result = wait_for_rootfs_ready(
        RuntimeWaitInput(
            config=tmp_path / "config.toml",
            vm_home=tmp_path,
            timeout=1,
            expected_run_id="run-test",
        )
    )

    assert result == 0


def test_wait_for_rootfs_ready_rejects_failed_manifest_even_with_marker(tmp_path):
    write_rootfs_manifest(
        tmp_path,
        run_id="run-test",
        stage_statuses={"edge-ready": ("timeout", "edge did not respond")},
    )
    write_rootfs_marker(tmp_path, run_id="run-test")

    with pytest.raises(SystemExit, match="rootfs stage failed"):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
                expected_run_id="run-test",
            )
        )


def test_wait_for_rootfs_ready_rejects_manifest_without_run_id(tmp_path):
    write_rootfs_manifest(tmp_path, run_id="run-test")
    manifest = tmp_path / "data/run/rootfs-runtime-manifest.json"
    document = json.loads(manifest.read_text(encoding="utf-8"))
    document.pop("runId")
    manifest.write_text(json.dumps(document), encoding="utf-8")
    write_rootfs_marker(tmp_path, run_id="run-test")

    with pytest.raises(SystemExit, match="rootfs manifest is missing runId"):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_wait_for_rootfs_ready_rejects_invalid_run_context(tmp_path):
    write_rootfs_manifest(tmp_path, run_id="stale-run")
    write_rootfs_marker(tmp_path, run_id="stale-run")
    run_context = tmp_path / "run/golden-rootfs-run.json"
    run_context.parent.mkdir(parents=True)
    run_context.write_text(json.dumps({"schemaVersion": 1}), encoding="utf-8")

    with pytest.raises(SystemExit, match="golden rootfs run context is missing runId"):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_wait_for_rootfs_ready_rejects_marker_without_manifest(tmp_path):
    write_rootfs_marker(tmp_path, run_id="run-test")

    with pytest.raises(SystemExit, match="timed out waiting"):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
                expected_run_id="run-test",
            )
        )


def test_wait_for_runtime_boot_smoke_accepts_passed_manifest(tmp_path):
    write_runtime_boot_smoke_manifest(tmp_path, run_id="runtime-run-test")

    result = wait_for_runtime_boot_smoke(
        RuntimeWaitInput(
            config=tmp_path / "config.toml",
            vm_home=tmp_path,
            timeout=1,
            expected_run_id="runtime-run-test",
        )
    )

    assert result == 0


def test_wait_for_runtime_boot_smoke_rejects_failed_stage(tmp_path):
    write_runtime_boot_smoke_manifest(
        tmp_path,
        run_id="runtime-run-test",
        stage_statuses={"runtime-state": ("failed", "runtime state is invalid")},
    )

    with pytest.raises(SystemExit, match="runtime boot smoke stage failed"):
        wait_for_runtime_boot_smoke(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
                expected_run_id="runtime-run-test",
            )
        )


def test_wait_for_runtime_boot_smoke_rejects_stale_run_id(tmp_path):
    write_runtime_boot_smoke_manifest(tmp_path, run_id="stale-run")

    with pytest.raises(SystemExit, match="timed out waiting"):
        wait_for_runtime_boot_smoke(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
                expected_run_id="runtime-run-test",
            )
        )


def test_wait_for_runtime_boot_smoke_rejects_stopped_lifecycle(tmp_path):
    lifecycle = tmp_path / "run" / "vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True)
    lifecycle.write_text(json.dumps({"state": "stopped"}), encoding="utf-8")

    with pytest.raises(SystemExit, match="VM lifecycle stopped"):
        wait_for_runtime_boot_smoke(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
                expected_run_id="runtime-run-test",
            )
        )


def test_begin_runtime_boot_smoke_run_invalidates_stale_proof(monkeypatch, tmp_path):
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".repo_root",
        lambda: tmp_path,
    )
    write_runtime_boot_smoke_manifest(tmp_path / "vm", run_id="stale-run")
    lifecycle = tmp_path / "vm/run/vm-lifecycle.json"
    lifecycle.parent.mkdir(parents=True, exist_ok=True)
    lifecycle.write_text(json.dumps({"state": "stopped"}), encoding="utf-8")

    result = begin_runtime_boot_smoke_run(
        RuntimeBootSmokeRunInput(
            config=tmp_path / "config.toml",
            vm_home=tmp_path / "vm",
            run_id="runtime-run-test",
        )
    )

    assert result == 0
    assert not (tmp_path / "vm/data/run/runtime-boot-smoke-manifest.json").exists()
    assert not lifecycle.exists()
    context = json.loads(
        (tmp_path / "vm/run/runtime-boot-smoke-run.json").read_text(
            encoding="utf-8"
        )
    )
    assert context["runId"] == "runtime-run-test"
    assert context["removedStaleProof"] == [
        str(tmp_path / "vm/data/run/runtime-boot-smoke-manifest.json"),
        str(tmp_path / "vm/run/vm-lifecycle.json"),
    ]


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


def test_wait_for_rootfs_ready_rejects_guest_filesystem_corruption_log(tmp_path):
    log_file = tmp_path / "logs" / "launcher.log"
    log_file.parent.mkdir(parents=True)
    log_file.write_text(
        "\n".join(
            [
                "appstreamcli: error while loading shared libraries: invalid ELF header",
                "E: Unable to mkstemp /tmp/clearsigned.message - GetTempFile (30: Read-only file system)",
            ]
        ),
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


def write_rootfs_manifest(
    vm_home,
    *,
    run_id: str,
    stage_statuses: dict[str, tuple[str, str]] | None = None,
) -> None:
    manifest = vm_home / "data/run/rootfs-runtime-manifest.json"
    manifest.parent.mkdir(parents=True)
    stage_statuses = stage_statuses or {}
    stages = []
    for name in (
        "docker-smoke",
        "disk-space",
        "compose-build",
        "compose-up",
        "edge-ready",
    ):
        status, message = stage_statuses.get(name, ("passed", f"{name} passed"))
        stages.append(
            {
                "name": name,
                "status": status,
                "message": message,
                "startedAt": "2026-06-11T00:00:00Z",
                "completedAt": "2026-06-11T00:00:01Z",
                "details": {},
            }
        )
    manifest.write_text(
        json.dumps(
            {
                "schemaVersion": 2,
                "runId": run_id,
                "stages": stages,
                "cleanup": {"status": "passed", "message": "cleanup passed"},
            }
        ),
        encoding="utf-8",
    )


def write_rootfs_marker(vm_home, *, run_id: str) -> None:
    marker = vm_home / "data/run/rootfs-ready"
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": run_id,
                "readyAt": "2026-06-11T00:00:02Z",
            }
        ),
        encoding="utf-8",
    )


def write_runtime_boot_smoke_manifest(
    vm_home,
    *,
    run_id: str,
    stage_statuses: dict[str, tuple[str, str]] | None = None,
) -> None:
    manifest = vm_home / "data/run/runtime-boot-smoke-manifest.json"
    manifest.parent.mkdir(parents=True)
    stage_statuses = stage_statuses or {}
    stages = []
    for name in (
        "bootstrap-result",
        "runtime-state",
        "systemd-units",
        "http",
        "compose-services",
        "disk-health",
        "capabilities",
        "command-dispatch",
        "feature-readiness",
    ):
        status, message = stage_statuses.get(name, ("passed", f"{name} passed"))
        stages.append(
            {
                "name": name,
                "status": status,
                "message": message,
                "startedAt": "2026-06-11T00:00:00Z",
                "completedAt": "2026-06-11T00:00:01Z",
                "details": {},
            }
        )
    manifest.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": run_id,
                "status": "failed" if stage_statuses else "passed",
                "stages": stages,
            }
        ),
        encoding="utf-8",
    )

import json
import sqlite3
import subprocess
from types import SimpleNamespace

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle import (
    begin_runtime_boot_smoke_run,
    force_stop_runtime,
    print_runtime_guest_address_proxy_upstream,
    require_no_running_runtime,
    running_vm_processes_for_home,
    wait_for_rootfs_ready,
    wait_for_runtime_boot_smoke,
    wait_for_runtime_http,
    wait_for_runtime_ip,
    wait_for_runtime_stopped,
)
from tirosh_vitalserver.devtools.application.inputs import (
    RuntimeBootSmokeRunInput,
    RuntimeGuestAddressOwnerInput,
    RuntimeVmHomeInput,
    RuntimeWaitInput,
)


def write_vm_lifecycle_owner(
    vm_home,
    *,
    state,
    terminal_reason=None,
    message=None,
):
    database = vm_home / "runtime/runtime-state.sqlite"
    database.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(database) as connection:
        connection.execute(
            """
            CREATE TABLE vm_lifecycle (
              singleton_id INTEGER PRIMARY KEY,
              state TEXT NOT NULL,
              terminal_reason TEXT,
              message TEXT
            )
            """
        )
        connection.execute(
            """
            INSERT INTO vm_lifecycle(singleton_id, state, terminal_reason, message)
            VALUES (1, ?, ?, ?)
            """,
            (state, terminal_reason, message),
        )


def test_wait_for_runtime_stopped_accepts_stopped_lifecycle(tmp_path):
    write_vm_lifecycle_owner(tmp_path, state="stopped")

    result = wait_for_runtime_stopped(
        RuntimeWaitInput(config=tmp_path / "config.toml", vm_home=tmp_path, timeout=1)
    )

    assert result == 0


def test_wait_for_runtime_ip_reads_vm_ip_bootstrap_file_not_runtime_observation(
    capsys,
    tmp_path,
):
    run_dir = tmp_path / "data/run"
    run_dir.mkdir(parents=True)
    (run_dir / "vm-ip").write_text("192.168.64.8\n", encoding="utf-8")
    (run_dir / "runtime-observation.json").write_text(
        json.dumps({"vmIP": "192.168.64.99"}),
        encoding="utf-8",
    )

    result = wait_for_runtime_ip(
        RuntimeWaitInput(config=tmp_path / "config.toml", vm_home=tmp_path, timeout=1)
    )

    output = capsys.readouterr().out
    assert result == 0
    assert "Waiting for VM IP bootstrap file:" in output
    assert "VM IP: 192.168.64.8" in output
    assert "runtime-observation" not in output


def test_wait_for_runtime_http_uses_direct_probe_not_runtime_observation_guest_http(
    capsys,
    monkeypatch,
    tmp_path,
):
    run_dir = tmp_path / "data/run"
    run_dir.mkdir(parents=True)
    (run_dir / "vm-ip").write_text("192.168.64.8\n", encoding="utf-8")
    (run_dir / "runtime-observation.json").write_text(
        json.dumps({"guestHTTP": "503"}),
        encoding="utf-8",
    )
    observed_addresses: list[str] = []

    def probe(address: str) -> tuple[bool, str]:
        observed_addresses.append(address)
        return True, "root=200 recorder-ingress=200"

    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".probe_guest_runtime_http",
        probe,
    )

    result = wait_for_runtime_http(
        RuntimeWaitInput(config=tmp_path / "config.toml", vm_home=tmp_path, timeout=1)
    )

    output = capsys.readouterr().out
    assert result == 0
    assert observed_addresses == ["192.168.64.8"]
    assert "VM HTTP ready: upstream=http://192.168.64.8:80" in output
    assert "guestHTTP" not in output
    assert "runtime-observation" not in output


def test_runtime_proxy_upstream_publishes_bootstrap_and_prints_owner_address(
    capsys,
    monkeypatch,
    tmp_path,
):
    run_dir = tmp_path / "data/run"
    run_dir.mkdir(parents=True)
    (run_dir / "vm-ip").write_text("192.168.64.8\n", encoding="utf-8")
    calls: list[tuple[str, str, dict[str, str] | None]] = []

    def request(
        input: RuntimeGuestAddressOwnerInput,
        *,
        method: str,
        path: str,
        body: dict[str, str] | None,
    ) -> dict[str, object]:
        calls.append((method, path, body))
        if method == "PUT":
            return loaded_guest_address_state("192.168.64.8")
        return loaded_guest_address_state("192.168.64.10")

    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".runtime_control_guest_address_request",
        request,
    )

    result = print_runtime_guest_address_proxy_upstream(
        guest_address_owner_input(tmp_path)
    )

    assert result == 0
    assert capsys.readouterr().out == "192.168.64.10:80\n"
    assert calls == [
        ("PUT", "/platform/runtime-endpoint", {"address": "192.168.64.8"}),
        ("GET", "/platform/runtime-endpoint", None),
    ]


def test_runtime_proxy_upstream_does_not_fallback_to_vm_ip_when_owner_missing(
    monkeypatch,
    tmp_path,
):
    run_dir = tmp_path / "data/run"
    run_dir.mkdir(parents=True)
    (run_dir / "vm-ip").write_text("192.168.64.8\n", encoding="utf-8")

    def request(
        input: RuntimeGuestAddressOwnerInput,
        *,
        method: str,
        path: str,
        body: dict[str, str] | None,
    ) -> dict[str, object]:
        if method == "PUT":
            return loaded_guest_address_state("192.168.64.8")
        return {"state": "missing", "readError": "Guest address resource missing"}

    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".runtime_control_guest_address_request",
        request,
    )

    with pytest.raises(SystemExit, match="Guest address owner is not loaded"):
        print_runtime_guest_address_proxy_upstream(guest_address_owner_input(tmp_path))


def test_wait_for_runtime_stopped_rejects_stopping_lifecycle_with_running_process(
    monkeypatch,
    tmp_path,
):
    write_vm_lifecycle_owner(tmp_path, state="stopping")
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".running_vm_processes_for_home",
        lambda vm_home: [1234],
    )

    with pytest.raises(
        SystemExit,
        match="timed out waiting for VM lifecycle and launcher process stopped",
    ):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
            )
        )


def test_wait_for_runtime_stopped_rejects_stopping_lifecycle_without_process(
    monkeypatch,
    tmp_path,
):
    write_vm_lifecycle_owner(tmp_path, state="stopping")
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".running_vm_processes_for_home",
        lambda vm_home: [],
    )

    with pytest.raises(
        SystemExit,
        match=(
            r"launcher process exited before VM lifecycle reached "
            r"stopped.*state=stopping"
        ),
    ):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_wait_for_runtime_stopped_waits_for_process_after_stopped_lifecycle(
    monkeypatch,
    tmp_path,
):
    write_vm_lifecycle_owner(tmp_path, state="stopped")
    process_reads = iter(([1234], []))
    observed_process_states: list[list[int]] = []

    def running_processes(_vm_home):
        state = next(process_reads)
        observed_process_states.append(state)
        return state

    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".running_vm_processes_for_home",
        running_processes,
    )
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".time.sleep",
        lambda _seconds: None,
    )

    result = wait_for_runtime_stopped(
        RuntimeWaitInput(config=tmp_path / "config.toml", vm_home=tmp_path, timeout=1)
    )

    assert result == 0
    assert observed_process_states == [[1234], []]


def test_wait_for_runtime_stopped_rejects_failed_lifecycle(tmp_path):
    write_vm_lifecycle_owner(
        tmp_path,
        state="failed",
        terminal_reason="guest-kernel-panic",
        message="guest kernel panic detected",
    )

    with pytest.raises(SystemExit, match="VM lifecycle failed while waiting"):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_wait_for_runtime_stopped_ignores_stale_json_diagnostic(
    monkeypatch,
    tmp_path,
):
    diagnostic = tmp_path / "run/vm-lifecycle.json"
    diagnostic.parent.mkdir(parents=True)
    diagnostic.write_text(json.dumps({"state": "stopped"}), encoding="utf-8")
    write_vm_lifecycle_owner(tmp_path, state="stopping")
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".running_vm_processes_for_home",
        lambda _: [28454],
    )

    with pytest.raises(SystemExit, match=r"state=stopping.*pids=28454"):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
            )
        )


def test_wait_for_runtime_stopped_rejects_missing_sqlite_owner(tmp_path):
    with pytest.raises(SystemExit, match="VM lifecycle SQLite owner is missing"):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
            )
        )


def test_wait_for_runtime_stopped_rejects_invalid_sqlite_owner(tmp_path):
    database = tmp_path / "runtime/runtime-state.sqlite"
    database.parent.mkdir(parents=True)
    with sqlite3.connect(database) as connection:
        connection.execute("CREATE TABLE unrelated(value TEXT)")

    with pytest.raises(SystemExit, match="VM lifecycle SQLite owner read failed"):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
            )
        )


def test_wait_for_runtime_stopped_rejects_invalid_sqlite_state(tmp_path):
    write_vm_lifecycle_owner(tmp_path, state="unknown")

    with pytest.raises(SystemExit, match="VM lifecycle SQLite state is invalid"):
        wait_for_runtime_stopped(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
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


def test_wait_for_rootfs_ready_rejects_missing_guest_tools_dependency_proof(tmp_path):
    write_rootfs_manifest(tmp_path, run_id="run-test")
    write_rootfs_marker(tmp_path, run_id="run-test", python_dependencies=None)

    with pytest.raises(SystemExit, match="Guest Tools dependency proof"):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
                expected_run_id="run-test",
            )
        )


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


def test_wait_for_rootfs_ready_rejects_guest_failure_marker(tmp_path):
    write_rootfs_failure(tmp_path, run_id="run-test", stage="apt-plan", exit_code=1)

    with pytest.raises(
        SystemExit,
        match=r"guest rootfs preparation failed.*stage=apt-plan",
    ):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
                expected_run_id="run-test",
            )
        )


def test_wait_for_rootfs_ready_ignores_stale_guest_failure_marker(tmp_path):
    write_rootfs_failure(tmp_path, run_id="old-run", stage="apt-plan", exit_code=1)

    with pytest.raises(SystemExit, match="timed out waiting"):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
                expected_run_id="run-test",
            )
        )


def test_wait_for_rootfs_ready_rejects_blocked_apt_plan(tmp_path):
    write_rootfs_apt_plan(
        tmp_path,
        run_id="run-test",
        status="blocked",
        blocked=["python3", "util-linux"],
    )

    with pytest.raises(
        SystemExit,
        match="rootfs apt plan mutates base runtime packages",
    ):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
                expected_run_id="run-test",
            )
        )


def test_wait_for_rootfs_ready_ignores_stale_blocked_apt_plan(tmp_path):
    write_rootfs_apt_plan(
        tmp_path,
        run_id="old-run",
        status="blocked",
        blocked=["python3", "util-linux"],
    )

    with pytest.raises(SystemExit, match="timed out waiting"):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=0,
                expected_run_id="run-test",
            )
        )


def test_wait_for_runtime_boot_smoke_accepts_passed_manifest(tmp_path, capsys):
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
    captured = capsys.readouterr()
    assert "SUCCESS: runtime boot smoke passed" in captured.out
    assert "runId=runtime-run-test" in captured.out


def test_wait_for_runtime_boot_smoke_accepts_passed_manifest_without_retired_stage(
    tmp_path,
    capsys,
):
    write_runtime_boot_smoke_manifest(
        tmp_path,
        run_id="runtime-run-test",
        stage_statuses={"command-dispatch": ("missing", "")},
    )

    result = wait_for_runtime_boot_smoke(
        RuntimeWaitInput(
            config=tmp_path / "config.toml",
            vm_home=tmp_path,
            timeout=1,
            expected_run_id="runtime-run-test",
        )
    )

    assert result == 0
    captured = capsys.readouterr()
    assert "SUCCESS: runtime boot smoke passed" in captured.out


def test_wait_for_runtime_boot_smoke_rejects_failed_stage(tmp_path):
    write_runtime_boot_smoke_manifest(
        tmp_path,
        run_id="runtime-run-test",
        stage_statuses={
            "runtime-observation": ("failed", "runtime observation is invalid")
        },
    )

    with pytest.raises(SystemExit) as error:
        wait_for_runtime_boot_smoke(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
                expected_run_id="runtime-run-test",
            )
        )
    message = str(error.value)
    assert "runtime boot smoke stage failed" in message
    assert "runId=runtime-run-test" in message
    assert "runtime-boot-smoke-manifest.json" in message
    assert "Check VM launcher log" in message


def test_wait_for_runtime_boot_smoke_rejects_failed_bootstrap_result(tmp_path):
    bootstrap_result = tmp_path / "data/run/bootstrap-result.json"
    bootstrap_result.parent.mkdir(parents=True)
    bootstrap_result.write_text(
        json.dumps(
            {
                "status": "failed",
                "message": "Guest bootstrap failed before completion.",
                "reasonCodes": ["guest-bootstrap-failed"],
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(SystemExit) as error:
        wait_for_runtime_boot_smoke(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
                expected_run_id="runtime-run-test",
            )
        )

    message = str(error.value)
    assert "runtime boot smoke bootstrap failed" in message
    assert "runId=runtime-run-test" in message
    assert "stage=bootstrap-result" in message
    assert "guest-bootstrap-failed" in message
    assert str(bootstrap_result) in message
    assert "Check VM launcher log" in message


def test_wait_for_runtime_boot_smoke_rejects_failed_guest_control_stage(tmp_path):
    write_runtime_boot_smoke_manifest(
        tmp_path,
        run_id="runtime-run-test",
        stage_statuses={
            "guest-control-api": (
                "failed",
                "runtime HTTP JSON request failed: timed out",
            ),
            "disk-health": ("missing", ""),
        },
    )

    with pytest.raises(SystemExit) as error:
        wait_for_runtime_boot_smoke(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
                expected_run_id="runtime-run-test",
            )
        )
    message = str(error.value)
    assert "runtime boot smoke stage failed" in message
    assert "name=guest-control-api" in message
    assert "timed out" in message


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
    bootstrap_result = tmp_path / "vm/data/run/bootstrap-result.json"
    bootstrap_result.write_text(
        json.dumps({"status": "failed"}),
        encoding="utf-8",
    )
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
    assert not bootstrap_result.exists()
    assert not lifecycle.exists()
    context = json.loads(
        (tmp_path / "vm/run/runtime-boot-smoke-run.json").read_text(
            encoding="utf-8"
        )
    )
    assert context["runId"] == "runtime-run-test"
    assert context["removedStaleProof"] == [
        str(tmp_path / "vm/data/run/runtime-boot-smoke-manifest.json"),
        str(bootstrap_result),
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
                "appstreamcli: error while loading shared libraries: "
                "invalid ELF header",
                "E: Unable to mkstemp /tmp/clearsigned.message - "
                "GetTempFile (30: Read-only file system)",
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


def test_wait_for_rootfs_ready_reports_ext4_error_before_read_only_result(tmp_path):
    log_file = tmp_path / "logs" / "launcher.log"
    log_file.parent.mkdir(parents=True)
    log_file.write_text(
        "\n".join(
            [
                "EXT4-fs error (device vda1): ext4_lookup: "
                "inode #23401: iget: checksum invalid",
                "Aborting journal on device vda1-8.",
                "EXT4-fs (vda1): Remounting filesystem read-only",
            ]
        ),
        encoding="utf-8",
    )

    with pytest.raises(
        SystemExit,
        match=r"pattern='EXT4-fs error'.*checksum invalid",
    ):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_wait_for_rootfs_ready_rejects_guest_execution_freeze_log(tmp_path):
    log_file = tmp_path / "logs" / "launcher.log"
    log_file.parent.mkdir(parents=True)
    log_file.write_text(
        "\n".join(
            [
                "(udev-worker)[9058]: veth528db2e: Process "
                "'bridge-network-interface' terminated by signal ILL.",
                "systemd[1]: Caught <ILL>, dumped core as pid 9094.",
                "systemd[1]: Freezing execution.",
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


def test_wait_for_rootfs_ready_rejects_guest_userspace_crash_log(tmp_path):
    log_file = tmp_path / "logs" / "launcher.log"
    log_file.parent.mkdir(parents=True)
    log_file.write_text(
        "/mnt/tirosh/deploy/prepare-airgap-rootfs.sh: line 127: "
        "7191 Illegal instruction     (core dumped) "
        "tirosh-vitalserver-rootfs-smoke\n",
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


def test_wait_for_rootfs_ready_reports_kernel_undefined_instruction_first(tmp_path):
    log_file = tmp_path / "logs" / "launcher.log"
    log_file.parent.mkdir(parents=True)
    log_file.write_text(
        "\n".join(
            [
                "/mnt/tirosh/deploy/prepare-airgap-rootfs.sh: line 458: "
                "5829 Illegal instruction     (core dumped) "
                "tirosh-vitalserver-rootfs-smoke",
                "Internal error: Oops - Undefined instruction: "
                "0000000002000000 [#1] SMP",
                "lr : seccomp_run_filters+0xb4/0x230",
                "Kernel panic - not syncing: Attempted to kill init! "
                "exitcode=0x0000008b",
            ]
        ),
        encoding="utf-8",
    )

    with pytest.raises(
        SystemExit,
        match="pattern='Internal error: Oops - Undefined instruction'",
    ):
        wait_for_rootfs_ready(
            RuntimeWaitInput(
                config=tmp_path / "config.toml",
                vm_home=tmp_path,
                timeout=1,
            )
        )


def test_wait_for_rootfs_ready_reports_dpkg_tar_segfault_before_illegal_instruction(
    tmp_path,
):
    log_file = tmp_path / "logs" / "launcher.log"
    log_file.parent.mkdir(parents=True)
    log_file.write_text(
        "\n".join(
            [
                "cloud-init[1064]: dpkg-deb: error: tar subprocess was "
                "killed by signal (Segmentation fault), core dumped",
                "cloud-init[1064]: E: Sub-process /usr/bin/dpkg returned "
                "an error code (1)",
                "cloud-init[1064]: Illegal instruction (core dumped)",
            ]
        ),
        encoding="utf-8",
    )

    with pytest.raises(
        SystemExit,
        match=r"pattern='Segmentation fault'.*tar subprocess",
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


def test_force_stop_runtime_sends_sigkill_when_sigterm_leaves_process(
    monkeypatch,
    tmp_path,
):
    calls = iter([[1234], [1234], [1234], []])
    signals = []
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".repo_root",
        lambda: tmp_path,
    )
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".running_vm_processes_for_home",
        lambda vm_home: next(calls),
    )
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".os.kill",
        lambda pid, signal: signals.append((pid, signal)),
    )

    result = force_stop_runtime(
        RuntimeWaitInput(
            config=tmp_path / "config.toml",
            vm_home=tmp_path / "vm",
            timeout=0,
        )
    )

    assert result == 0
    assert signals == [(1234, 15), (1234, 9)]


def test_force_stop_runtime_accepts_no_process(monkeypatch, tmp_path):
    signals = []
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
    monkeypatch.setattr(
        "tirosh_vitalserver.devtools.adapters.macos_release.runtime_lifecycle"
        ".os.kill",
        lambda pid, signal: signals.append((pid, signal)),
    )

    result = force_stop_runtime(
        RuntimeWaitInput(
            config=tmp_path / "config.toml",
            vm_home=tmp_path / "vm",
            timeout=1,
        )
    )

    assert result == 0
    assert signals == []


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
        "runtime-data-mount",
        "runtime-data-configure",
        "docker-service",
        "runtime-version",
        "docker-image-load",
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


def write_rootfs_marker(
    vm_home,
    *,
    run_id: str,
    python_dependencies: dict[str, object] | None | bool = True,
) -> None:
    marker = vm_home / "data/run/rootfs-ready"
    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": run_id,
                "readyAt": "2026-06-11T00:00:02Z",
                **(
                    {
                        "pythonDependencies": {
                            "status": "passed",
                            "proof": "/opt/tirosh/guest-tools/install-proof.json",
                            "target": "linux-aarch64",
                            "dependencies": {
                                "alembic": "1.16.5",
                                "sqlalchemy": "2.0.51",
                            },
                        }
                    }
                    if python_dependencies is True
                    else {"pythonDependencies": python_dependencies}
                    if isinstance(python_dependencies, dict)
                    else {}
                ),
            }
        ),
        encoding="utf-8",
    )


def write_rootfs_failure(
    vm_home,
    *,
    run_id: str,
    stage: str,
    exit_code: int,
) -> None:
    failure = vm_home / "data/run/rootfs-failure.json"
    failure.parent.mkdir(parents=True, exist_ok=True)
    failure.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": run_id,
                "stage": stage,
                "exitCode": exit_code,
                "reason": "guest-rootfs-prepare-failed",
                "aptPlanPath": "/mnt/tirosh/run/rootfs-apt-plan.json",
            }
        ),
        encoding="utf-8",
    )


def write_rootfs_apt_plan(
    vm_home,
    *,
    run_id: str,
    status: str,
    blocked: list[str],
) -> None:
    apt_plan = vm_home / "data/run/rootfs-apt-plan.json"
    apt_plan.parent.mkdir(parents=True, exist_ok=True)
    apt_plan.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": run_id,
                "status": status,
                "snapshot": "20250313T000000Z",
                "blockedUpgrades": blocked,
            }
        ),
        encoding="utf-8",
    )


def guest_address_owner_input(vm_home) -> RuntimeGuestAddressOwnerInput:
    return RuntimeGuestAddressOwnerInput(
        config=vm_home / "config.toml",
        vm_home=vm_home,
        runtime_control_api_base_url="http://127.0.0.1:18321",
        runtime_control_api_token="token",
        runtime_control_api_token_header="X-Runtime-Control-Token",
        runtime_control_api_timeout=2.0,
    )


def loaded_guest_address_state(address: str) -> dict[str, object]:
    return {
        "state": "loaded",
        "read": {
            "state": "loaded",
            "address": address,
        },
    }


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
        "runtime-observation",
        "systemd-units",
        "runtime-data",
        "http",
        "compose-services",
        "guest-control-api",
        "disk-health",
        "capabilities",
        "command-dispatch",
        "feature-readiness",
    ):
        if stage_statuses.get(name, ("", ""))[0] == "missing":
            continue
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
                "status": "failed"
                if any(
                    status in {"failed", "timeout", "cleanup-failed"}
                    for status, _ in stage_statuses.values()
                )
                else "passed",
                "stages": stages,
            }
        ),
        encoding="utf-8",
    )

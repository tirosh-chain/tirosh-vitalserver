from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release import runtime_lifecycle
from tirosh_vitalserver.devtools.application.inputs import (
    GoldenRootfsPreflightInput,
    RootfsRunInput,
    RuntimeControlInput,
    RuntimeVmHomeInput,
)


def test_start_runtime_detached_writes_host_time_contract(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_build_config(tmp_path / "config/vm-build.toml")
    runtime_cli = tmp_path / "vitalserver-vm"
    launches: list[tuple[list[str], dict[str, str]]] = []

    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        runtime_lifecycle,
        "load_macos_release_settings",
        lambda *_: SimpleNamespace(runtime_cli=runtime_cli),
    )
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )
    monkeypatch.setattr(runtime_lifecycle, "process_is_running", lambda _: False)
    monkeypatch.setattr(runtime_lifecycle.time, "time", lambda: 1_780_000_000)

    class PopenStub:
        def __init__(self, command, *, env, stdout, stderr, start_new_session):
            launches.append((command, env))

    monkeypatch.setattr(runtime_lifecycle.subprocess, "Popen", PopenStub)

    result = runtime_lifecycle.start_runtime_detached(
        RuntimeVmHomeInput(config=Path("config/vm-build.toml"), vm_home=Path("vm"))
    )

    assert result == 0
    contract = json.loads(
        (tmp_path / "vm/data/deploy/host-time.json").read_text(encoding="utf-8")
    )
    assert contract == {
        "epochSeconds": 1_780_000_000,
        "schemaVersion": 1,
        "updatedAt": "2026-05-28T20:26:40Z",
    }
    relay_config = tmp_path / "vm/data/deploy/redis-relay-config/redis-relay.toml"
    assert relay_config.exists()
    assert 'enabled = false' in relay_config.read_text(encoding="utf-8")
    assert (tmp_path / "vm/data/deploy/redis-relay-secrets").is_dir()
    assert (tmp_path / "vm/data/run/redis-relay-status").is_dir()
    assert launches[0][0] == [str(runtime_cli), "start"]
    assert launches[0][1]["VITALSERVER_VM_HOME"] == str(tmp_path / "vm")
    assert launches[0][1]["VITALSERVER_VM_DETACHED"] == "1"


def test_control_runtime_start_writes_host_time_contract(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_build_config(tmp_path / "config/vm-build.toml")
    runtime_cli = tmp_path / "vitalserver-vm"
    commands: list[list[str]] = []

    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        runtime_lifecycle,
        "load_macos_release_settings",
        lambda *_: SimpleNamespace(runtime_cli=runtime_cli),
    )
    monkeypatch.setattr(runtime_lifecycle.time, "time", lambda: 1_780_000_000)

    def run_stub(command, *, env, check):
        commands.append(command)
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(runtime_lifecycle.subprocess, "run", run_stub)

    result = runtime_lifecycle.control_runtime(
        RuntimeControlInput(
            config=Path("config/vm-build.toml"),
            vm_home=Path("vm"),
            runtime_args=["start"],
        )
    )

    assert result == 0
    assert commands == [[str(runtime_cli), "start"]]
    assert (tmp_path / "vm/data/deploy/host-time.json").exists()
    assert (tmp_path / "vm/data/deploy/redis-relay-config/redis-relay.toml").exists()
    assert (tmp_path / "vm/data/deploy/redis-relay-secrets").is_dir()
    assert (tmp_path / "vm/data/run/redis-relay-status").is_dir()


def test_runtime_start_contract_preserves_existing_redis_relay_config(
    tmp_path: Path,
) -> None:
    config_path = tmp_path / "vm/data/deploy/redis-relay-config/redis-relay.toml"
    config_path.parent.mkdir(parents=True)
    config_path.write_text("existing-config\n", encoding="utf-8")

    runtime_lifecycle.write_default_redis_relay_contract(tmp_path / "vm")

    assert config_path.read_text(encoding="utf-8") == "existing-config\n"
    assert (tmp_path / "vm/data/deploy/redis-relay-secrets").is_dir()
    assert (tmp_path / "vm/data/run/redis-relay-status").is_dir()


def test_begin_golden_rootfs_run_records_runtime_data_disk_contract(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_build_config(tmp_path / "config/vm-build.toml")
    vm_home = tmp_path / "vm"
    stale_ready = vm_home / "data/run/rootfs-ready"
    stale_ready.parent.mkdir(parents=True)
    stale_ready.write_text("stale", encoding="utf-8")
    vm_config = vm_home / "runtime/vm-config.json"
    vm_config.parent.mkdir(parents=True)
    vm_config_text = json.dumps(
        {
            "kernelPath": "/runtime/Image",
            "runtimeDataDiskPath": str(vm_home / "runtime/runtime-data.img"),
        },
        separators=(",", ":"),
    )
    vm_config.write_text(vm_config_text, encoding="utf-8")

    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        runtime_lifecycle,
        "prepare_ephemeral_runtime_data_disk",
        lambda plan: {
            "path": str(plan.disk_image),
            "diskImageName": plan.disk_image_name,
            "diskSize": plan.disk_size,
            "filesystemLabel": plan.filesystem_label,
            "mountPath": plan.mount_path,
            "dockerDataRoot": plan.docker_data_root,
            "containerdRoot": plan.containerd_root,
            "removedStaleDisk": False,
        },
    )

    result = runtime_lifecycle.begin_golden_rootfs_run(
        RootfsRunInput(
            config=Path("config/vm-build.toml"),
            vm_home=Path("vm"),
            run_id="run-test",
        )
    )

    assert result == 0
    assert not stale_ready.exists()
    context = json.loads(
        (vm_home / "run/golden-rootfs-run.json").read_text(encoding="utf-8")
    )
    assert context["runId"] == "run-test"
    assert context["removedStaleProof"] == [str(stale_ready)]
    assert context["runtimeDataDisk"] == {
        "path": str(vm_home / "runtime/runtime-data.img"),
        "diskImageName": "runtime-data.img",
        "diskSize": "16G",
        "filesystemLabel": "vital-runtime",
        "mountPath": "/mnt/runtime",
        "dockerDataRoot": "/mnt/runtime/docker",
        "containerdRoot": "/mnt/runtime/containerd",
        "removedStaleDisk": False,
    }
    assert vm_config.read_text(encoding="utf-8") == vm_config_text


def test_begin_golden_rootfs_run_requires_initialized_vm_config(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_build_config(tmp_path / "config/vm-build.toml")
    stale_ready = tmp_path / "vm/data/run/rootfs-ready"
    stale_ready.parent.mkdir(parents=True)
    stale_ready.write_text("stale", encoding="utf-8")
    prepared = False
    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)

    def prepare(plan):
        nonlocal prepared
        prepared = True
        return {
            "path": str(plan.disk_image),
            "diskImageName": plan.disk_image_name,
            "diskSize": plan.disk_size,
            "filesystemLabel": plan.filesystem_label,
            "mountPath": plan.mount_path,
            "dockerDataRoot": plan.docker_data_root,
            "containerdRoot": plan.containerd_root,
            "removedStaleDisk": False,
        }

    monkeypatch.setattr(
        runtime_lifecycle,
        "prepare_ephemeral_runtime_data_disk",
        prepare,
    )

    with pytest.raises(SystemExit, match="VM config is missing"):
        runtime_lifecycle.begin_golden_rootfs_run(
            RootfsRunInput(
                config=Path("config/vm-build.toml"),
                vm_home=Path("vm"),
                run_id="run-test",
            )
        )
    assert prepared is False
    assert stale_ready.read_text(encoding="utf-8") == "stale"


def test_prepare_runtime_data_disk_preserves_materialized_vm_config(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_build_config(tmp_path / "config/vm-build.toml")
    vm_home = tmp_path / "vm"
    vm_config = vm_home / "runtime/vm-config.json"
    vm_config.parent.mkdir(parents=True)
    vm_config_text = json.dumps(
        {
            "kernelPath": "/runtime/Image",
            "runtimeDataDiskPath": str(vm_home / "runtime/runtime-data.img"),
        },
        separators=(",", ":"),
    )
    vm_config.write_text(vm_config_text, encoding="utf-8")

    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        runtime_lifecycle,
        "prepare_ephemeral_runtime_data_disk",
        lambda plan: {
            "path": str(plan.disk_image),
            "diskImageName": plan.disk_image_name,
            "diskSize": plan.disk_size,
            "filesystemLabel": plan.filesystem_label,
            "mountPath": plan.mount_path,
            "dockerDataRoot": plan.docker_data_root,
            "containerdRoot": plan.containerd_root,
            "removedStaleDisk": True,
        },
    )

    result = runtime_lifecycle.prepare_runtime_data_disk(
        RuntimeVmHomeInput(
            config=Path("config/vm-build.toml"),
            vm_home=Path("vm"),
        )
    )

    assert result == 0
    assert vm_config.read_text(encoding="utf-8") == vm_config_text
    assert not (vm_home / "run/golden-rootfs-run.json").exists()


def test_prepare_runtime_data_disk_rejects_vm_config_path_mismatch_before_write(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    write_build_config(tmp_path / "config/vm-build.toml")
    vm_home = tmp_path / "vm"
    vm_config = vm_home / "runtime/vm-config.json"
    vm_config.parent.mkdir(parents=True)
    vm_config_text = json.dumps(
        {
            "kernelPath": "/runtime/Image",
            "runtimeDataDiskPath": "/unexpected/runtime-data.img",
        },
        separators=(",", ":"),
    )
    vm_config.write_text(vm_config_text, encoding="utf-8")
    prepared = False

    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)

    def prepare(_plan):
        nonlocal prepared
        prepared = True
        raise AssertionError("runtime data disk must not be prepared after contract mismatch")

    monkeypatch.setattr(
        runtime_lifecycle,
        "prepare_ephemeral_runtime_data_disk",
        prepare,
    )

    with pytest.raises(SystemExit, match="runtime data disk path does not match"):
        runtime_lifecycle.prepare_runtime_data_disk(
            RuntimeVmHomeInput(
                config=Path("config/vm-build.toml"),
                vm_home=Path("vm"),
            )
        )

    assert prepared is False
    assert vm_config.read_text(encoding="utf-8") == vm_config_text


def test_golden_rootfs_preflight_rejects_unavailable_apt_snapshot(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    vm_home = tmp_path / "vm"
    write_rootfs_input(vm_home, run_id="run-test")
    write_run_context(vm_home, run_id="run-test")
    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )
    monkeypatch.setattr(
        runtime_lifecycle,
        "check_apt_snapshot_available",
        lambda snapshot: [
            runtime_lifecycle.PreflightCheck(
                name="apt-snapshot",
                status=runtime_lifecycle.PreflightStatus.UNAVAILABLE,
                message="Ubuntu apt snapshot endpoint is unavailable",
                detail=f"snapshot={snapshot} status=503",
            )
        ],
    )

    with pytest.raises(SystemExit):
        runtime_lifecycle.preflight_golden_rootfs(
            GoldenRootfsPreflightInput(
                config=Path("config/vm-build.toml"),
                vm_home=Path("vm"),
                expected_run_id="run-test",
            )
        )


def test_apt_snapshot_probe_retries_transient_timeout(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls: list[int] = []

    class Response:
        def __enter__(self) -> Response:
            return self

        def __exit__(self, *_: object) -> None:
            return None

        def getcode(self) -> int:
            return 200

        def read(self, size: int) -> bytes:
            assert size == 1
            return b"x"

    def urlopen(_: object, *, timeout: int) -> Response:
        calls.append(timeout)
        if len(calls) == 1:
            raise TimeoutError("slow snapshot endpoint")
        return Response()

    monkeypatch.setattr(runtime_lifecycle.urllib.request, "urlopen", urlopen)

    check = runtime_lifecycle.probe_apt_snapshot_url(
        "https://snapshot.example/InRelease",
        attempts=2,
        timeout_seconds=30,
        retry_delay_seconds=0,
    )

    assert check.status == runtime_lifecycle.PreflightStatus.PASSED
    assert calls == [30, 30]


def test_apt_snapshot_probe_preserves_unavailable_after_retries(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    def urlopen(_: object, *, timeout: int) -> object:
        assert timeout == 30
        raise TimeoutError("slow snapshot endpoint")

    monkeypatch.setattr(runtime_lifecycle.urllib.request, "urlopen", urlopen)

    check = runtime_lifecycle.probe_apt_snapshot_url(
        "https://snapshot.example/InRelease",
        attempts=2,
        timeout_seconds=30,
        retry_delay_seconds=0,
    )

    assert check.status == runtime_lifecycle.PreflightStatus.UNAVAILABLE
    assert check.message == "Ubuntu apt snapshot endpoint is unavailable after retries"
    assert check.detail is not None
    assert "attempt=1" in check.detail
    assert "attempt=2" in check.detail


def test_apt_snapshot_probe_default_tolerates_short_cdn_error_window(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    calls = 0
    delays: list[int] = []

    class Response:
        def __enter__(self) -> Response:
            return self

        def __exit__(self, *_: object) -> None:
            return None

        def getcode(self) -> int:
            return 200

        def read(self, size: int) -> bytes:
            assert size == 1
            return b"x"

    def urlopen(_: object, *, timeout: int) -> Response:
        nonlocal calls
        assert timeout == runtime_lifecycle.APT_SNAPSHOT_PROBE_TIMEOUT_SECONDS
        calls += 1
        if calls < runtime_lifecycle.APT_SNAPSHOT_PROBE_ATTEMPTS:
            raise runtime_lifecycle.urllib.error.HTTPError(
                "https://snapshot.example/InRelease",
                503,
                "Service Unavailable",
                {},
                None,
            )
        return Response()

    monkeypatch.setattr(runtime_lifecycle.urllib.request, "urlopen", urlopen)
    monkeypatch.setattr(runtime_lifecycle.time, "sleep", delays.append)

    check = runtime_lifecycle.probe_apt_snapshot_url(
        "https://snapshot.example/InRelease"
    )

    assert check.status == runtime_lifecycle.PreflightStatus.PASSED
    assert calls == 4
    assert delays == [3, 3, 3]


def test_golden_rootfs_preflight_rejects_invalid_rootfs_metadata(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    vm_home = tmp_path / "vm"
    write_run_context(vm_home, run_id="run-test")
    metadata = vm_home / "data/deploy/build-metadata/rootfs-input.json"
    metadata.parent.mkdir(parents=True)
    metadata.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": "run-test",
                "guestClockUtc": "2026-06-13T02:00:00Z",
                "ubuntu": {"aptSnapshot": ""},
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setattr(runtime_lifecycle, "repo_root", lambda: tmp_path)
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )

    report = runtime_lifecycle.golden_rootfs_preflight_report(
        vm_home=vm_home,
        expected_run_id="run-test",
    )

    assert not report.passed
    assert any(
        check.status == runtime_lifecycle.PreflightStatus.INVALID
        and check.name == "rootfs-input-metadata"
        for check in report.blockers
    )


def test_golden_rootfs_preflight_rejects_stale_proof_before_vm_start(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    vm_home = tmp_path / "vm"
    write_rootfs_input(vm_home, run_id="run-test")
    write_run_context(vm_home, run_id="run-test")
    ready = vm_home / "data/run/rootfs-ready"
    ready.parent.mkdir(parents=True)
    ready.write_text(json.dumps({"runId": "old-run"}), encoding="utf-8")
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )
    monkeypatch.setattr(runtime_lifecycle, "check_apt_snapshot_available", lambda _: [])

    report = runtime_lifecycle.golden_rootfs_preflight_report(
        vm_home=vm_home,
        expected_run_id="run-test",
    )

    assert not report.passed
    assert any(check.name == "rootfs-ready" for check in report.blockers)


def test_golden_rootfs_preflight_accepts_explicit_inputs(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    vm_home = tmp_path / "vm"
    write_rootfs_input(vm_home, run_id="run-test")
    write_run_context(vm_home, run_id="run-test")
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )
    monkeypatch.setattr(
        runtime_lifecycle,
        "check_apt_snapshot_available",
        lambda _: [
            runtime_lifecycle.PreflightCheck(
                name="apt-snapshot",
                status=runtime_lifecycle.PreflightStatus.PASSED,
                message="snapshot ok",
            )
        ],
    )

    report = runtime_lifecycle.golden_rootfs_preflight_report(
        vm_home=vm_home,
        expected_run_id="run-test",
    )

    assert report.passed


def test_golden_rootfs_preflight_does_not_probe_network_for_verified_apt_cache(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    vm_home = tmp_path / "vm"
    write_rootfs_input(vm_home, run_id="run-test")
    write_run_context(vm_home, run_id="run-test")
    monkeypatch.setattr(
        runtime_lifecycle,
        "running_vm_processes_for_home",
        lambda _: [],
    )

    def unexpected_network_probe(_: str) -> list[runtime_lifecycle.PreflightCheck]:
        raise AssertionError("verified APT cache must not probe the snapshot network")

    monkeypatch.setattr(
        runtime_lifecycle,
        "check_apt_snapshot_available",
        unexpected_network_probe,
    )

    report = runtime_lifecycle.golden_rootfs_preflight_report(
        vm_home=vm_home,
        expected_run_id="run-test",
        apt_source="verified-cache",
    )

    assert report.passed
    assert any(
        check.name == "apt-source"
        and check.status == runtime_lifecycle.PreflightStatus.PASSED
        for check in report.checks
    )


def write_build_config(path: Path) -> None:
    path.parent.mkdir(parents=True)
    path.write_text(
        """
[guest.runtime]
runtime_dir = "runtime"
rootfs_size = "8G"
disk_image_name = "vm-disk.img"

[guest.runtime_data]
disk_image_name = "runtime-data.img"
disk_size = "16G"
filesystem_label = "vital-runtime"
mount_path = "/mnt/runtime"
docker_data_root = "/mnt/runtime/docker"
containerd_root = "/mnt/runtime/containerd"
""".lstrip(),
        encoding="utf-8",
    )


def write_run_context(vm_home: Path, *, run_id: str) -> None:
    path = vm_home / "run/golden-rootfs-run.json"
    path.parent.mkdir(parents=True)
    path.write_text(
        json.dumps({"schemaVersion": 1, "runId": run_id}),
        encoding="utf-8",
    )


def write_rootfs_input(vm_home: Path, *, run_id: str) -> None:
    path = vm_home / "data/deploy/build-metadata/rootfs-input.json"
    path.parent.mkdir(parents=True)
    path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": run_id,
                "guestClockUtc": "2026-06-13T02:00:00Z",
                "ubuntu": {
                    "aptSnapshot": "20250515T000000Z",
                    "baseUrl": "https://cloud-images.ubuntu.com/releases/noble",
                },
            }
        ),
        encoding="utf-8",
    )

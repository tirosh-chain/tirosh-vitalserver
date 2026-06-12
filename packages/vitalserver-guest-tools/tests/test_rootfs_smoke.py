from __future__ import annotations

import json
import subprocess
from collections.abc import Callable
from pathlib import Path

import pytest

from tirosh_guest_tools.application import rootfs_smoke
from tirosh_guest_tools.application.rootfs_smoke import (
    RootfsSmokeContext,
    RootfsSmokeOperations,
    run_rootfs_smoke,
)


def test_rootfs_smoke_writes_manifest_v2_for_success(tmp_path: Path) -> None:
    context = smoke_context(tmp_path)
    write_metadata(context.deploy_dir)
    write_apt_plan(context.apt_plan_path)
    write_apt_installed(context.apt_installed_path)
    operations = fake_operations()

    run_rootfs_smoke(context=context, operations=operations)

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["schemaVersion"] == 2
    assert document["runId"] == "run-test"
    assert document["ubuntu"]["metadataStatus"] == "loaded"
    assert document["ubuntu"]["aptSnapshot"] == "20250313T000000Z"
    assert document["ubuntu"]["baseUrl"] == "https://example.invalid/release"
    assert document["ubuntu"]["cacheKey"] == "release-abcd"
    assert document["ubuntu"]["kernel"] == "6.8.0-test"
    assert document["apt"]["status"] == "allowed"
    assert document["apt"]["runId"] == "run-test"
    assert document["apt"]["snapshot"] == "20250313T000000Z"
    assert document["apt"]["blockedUpgrades"] == []
    assert document["aptInstalled"]["packages"]["docker.io"] == "26.1.3-test"
    assert stage_status(document, "docker-service") == "passed"
    assert stage_status(document, "runtime-version") == "passed"
    assert stage_status(document, "docker-image-load") == "passed"
    assert stage_details(document, "docker-image-load")["bundleBytes"] == 6
    assert stage_status(document, "docker-smoke") == "passed"
    assert stage_status(document, "disk-space") == "passed"
    assert stage_status(document, "compose-build") == "passed"
    assert stage_status(document, "compose-up") == "passed"
    assert stage_status(document, "edge-ready") == "passed"
    assert document["cleanup"]["status"] == "passed"
    assert document["diagnostics"]["path"] == str(context.diagnostics_dir)


def test_rootfs_smoke_records_timeout_and_diagnostics(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = smoke_context(tmp_path)
    write_metadata(context.deploy_dir)
    write_apt_plan(context.apt_plan_path)
    write_apt_installed(context.apt_installed_path)

    def timeout_http(url: str, timeout_seconds: float) -> int:
        raise TimeoutError("edge did not answer")

    operations = fake_operations(http_status=timeout_http, sleep=lambda _: None)
    monkeypatch.setattr(rootfs_smoke, "EDGE_READY_TIMEOUT_SECONDS", 0.0)

    with pytest.raises(SystemExit):
        run_rootfs_smoke(context=context, operations=operations)

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert stage_status(document, "edge-ready") == "timeout"
    assert document["cleanup"]["status"] == "passed"
    assert (context.diagnostics_dir / "manifest.partial.json").is_file()
    assert (context.diagnostics_dir / "compose-logs.txt").is_file()


def test_rootfs_smoke_records_fault_injected_compose_up_failure(tmp_path: Path) -> None:
    context = smoke_context(
        tmp_path,
        test_mode=True,
        fail_stage="compose-up",
    )
    write_metadata(context.deploy_dir)
    write_apt_plan(context.apt_plan_path)
    write_apt_installed(context.apt_installed_path)

    with pytest.raises(SystemExit):
        run_rootfs_smoke(context=context, operations=fake_operations())

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert stage_status(document, "compose-up") == "failed"
    assert document["cleanup"]["status"] == "passed"


def test_rootfs_smoke_records_docker_image_load_timeout_input(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    context = smoke_context(tmp_path)
    write_metadata(context.deploy_dir)
    write_apt_plan(context.apt_plan_path)
    write_apt_installed(context.apt_installed_path)
    monkeypatch.setattr(rootfs_smoke, "DOCKER_IMAGE_LOAD_TIMEOUT_SECONDS", 2.0)

    def run(arguments: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        if arguments[:2] == ["docker", "load"]:
            raise subprocess.TimeoutExpired(arguments, kwargs["timeout_seconds"])
        return completed(arguments)

    with pytest.raises(SystemExit):
        run_rootfs_smoke(context=context, operations=fake_operations(run=run))

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert stage_status(document, "docker-image-load") == "timeout"
    details = stage_details(document, "docker-image-load")
    assert details["bundle"] == str(context.docker_image_bundle_path)
    assert details["bundleBytes"] == 6
    assert details["timeoutSeconds"] == 2.0
    assert details["command"] == ["docker", "load", "-i", str(context.docker_image_bundle_path)]


def test_rootfs_smoke_fails_when_disk_space_is_too_low(tmp_path: Path) -> None:
    context = smoke_context(tmp_path, minimum_disk_free_kib=999999999)
    write_metadata(context.deploy_dir)
    write_apt_plan(context.apt_plan_path)
    write_apt_installed(context.apt_installed_path)

    with pytest.raises(SystemExit):
        run_rootfs_smoke(context=context, operations=fake_operations())

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert stage_status(document, "disk-space") == "failed"


def test_rootfs_smoke_fails_when_cleanup_fails(tmp_path: Path) -> None:
    context = smoke_context(tmp_path)
    write_metadata(context.deploy_dir)
    write_apt_plan(context.apt_plan_path)
    write_apt_installed(context.apt_installed_path)

    def run(arguments: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        if arguments[-5:] == ["down", "-v", "--remove-orphans", "--rmi", "all"]:
            return subprocess.CompletedProcess(arguments, 1, "", "cleanup failed")
        return completed(arguments)

    with pytest.raises(SystemExit):
        run_rootfs_smoke(context=context, operations=fake_operations(run=run))

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["cleanup"]["status"] == "cleanup-failed"
    assert "cleanup failed" in document["cleanup"]["message"]


def test_rootfs_smoke_prunes_docker_state_before_success(tmp_path: Path) -> None:
    context = smoke_context(tmp_path)
    write_metadata(context.deploy_dir)
    write_apt_plan(context.apt_plan_path)
    write_apt_installed(context.apt_installed_path)
    commands: list[list[str]] = []

    def run(arguments: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        commands.append(arguments)
        return completed(arguments)

    run_rootfs_smoke(context=context, operations=fake_operations(run=run))

    assert compose_command_suffix(commands, ["down", "-v", "--remove-orphans", "--rmi", "all"])
    assert ["docker", "builder", "prune", "--all", "--force"] in commands
    assert ["docker", "system", "prune", "--all", "--force", "--volumes"] in commands
    assert ["docker", "ps", "--all", "--quiet"] in commands
    assert ["docker", "images", "--all", "--quiet"] in commands
    assert ["docker", "volume", "ls", "--quiet"] in commands

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["cleanup"]["status"] == "passed"
    cleanup_commands = document["cleanup"]["commands"]
    assert [item["name"] for item in cleanup_commands] == [
        "compose-down",
        "docker-builder-prune",
        "docker-system-prune",
        "docker-containers-empty",
        "docker-images-empty",
        "docker-volumes-empty",
    ]


def test_rootfs_smoke_fails_when_docker_images_remain_after_cleanup(tmp_path: Path) -> None:
    context = smoke_context(tmp_path)
    write_metadata(context.deploy_dir)
    write_apt_plan(context.apt_plan_path)
    write_apt_installed(context.apt_installed_path)

    def run(arguments: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        if arguments == ["docker", "images", "--all", "--quiet"]:
            return subprocess.CompletedProcess(arguments, 0, "image-id\n", "")
        return completed(arguments)

    with pytest.raises(SystemExit):
        run_rootfs_smoke(context=context, operations=fake_operations(run=run))

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["cleanup"]["status"] == "cleanup-failed"
    assert "docker-images-empty failed" in document["cleanup"]["message"]


def test_rootfs_smoke_records_missing_input_metadata(tmp_path: Path) -> None:
    context = smoke_context(tmp_path)

    run_rootfs_smoke(context=context, operations=fake_operations())

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["ubuntu"]["metadataStatus"] == "missing"
    assert document["ubuntu"]["aptSnapshot"] == ""
    assert document["ubuntu"]["baseUrl"] == ""
    assert document["ubuntu"]["cacheKey"] == ""
    assert document["apt"]["status"] == "missing"


def test_rootfs_smoke_cli_is_registered() -> None:
    pyproject = Path(__file__).parents[1] / "pyproject.toml"
    assert "tirosh-vitalserver-rootfs-smoke" in pyproject.read_text(encoding="utf-8")


def test_rootfs_smoke_runs_docker_smoke_without_seccomp(tmp_path: Path) -> None:
    context = smoke_context(tmp_path)
    write_metadata(context.deploy_dir)
    write_apt_plan(context.apt_plan_path)
    write_apt_installed(context.apt_installed_path)
    commands: list[list[str]] = []

    def run(arguments: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        commands.append(arguments)
        return completed(arguments)

    run_rootfs_smoke(context=context, operations=fake_operations(run=run))

    docker_runs = [command for command in commands if command[:2] == ["docker", "run"]]
    assert docker_runs == [
        [
            "docker",
            "run",
            "--rm",
            "--network",
            "none",
            "--security-opt",
            "seccomp=unconfined",
            "redis:3.2.12-alpine",
            "true",
        ]
    ]


def smoke_context(
    tmp_path: Path,
    *,
    test_mode: bool = False,
    fail_stage: str = "",
    fail_cleanup: bool = False,
    minimum_disk_free_kib: int = 1,
) -> RootfsSmokeContext:
    runtime_dir = tmp_path / "run"
    deploy_dir = tmp_path / "deploy"
    diagnostics_dir = runtime_dir / "rootfs-smoke-diagnostics"
    runtime_dir.mkdir(parents=True)
    deploy_dir.mkdir(parents=True)
    docker_image_bundle = deploy_dir / "docker-images" / "vitalserver-images.tar.gz"
    docker_image_bundle.parent.mkdir(parents=True)
    docker_image_bundle.write_bytes(b"bundle")
    return RootfsSmokeContext(
        runtime_dir=runtime_dir,
        deploy_dir=deploy_dir,
        vital_files_mount=tmp_path / "vital-files",
        manifest_path=runtime_dir / "rootfs-runtime-manifest.json",
        apt_plan_path=runtime_dir / "rootfs-apt-plan.json",
        apt_installed_path=runtime_dir / "rootfs-apt-installed.json",
        docker_image_bundle_path=docker_image_bundle,
        diagnostics_dir=diagnostics_dir,
        compose_project_name="vitalserver-rootfs-smoke",
        docker_smoke_image="redis:3.2.12-alpine",
        local_docker_smoke_image="vitalserver-rootfs-smoke:local",
        run_id="run-test",
        test_mode=test_mode,
        fail_stage=fail_stage,
        fail_cleanup=fail_cleanup,
        minimum_disk_free_kib=minimum_disk_free_kib,
    )


def write_metadata(deploy_dir: Path) -> None:
    metadata = deploy_dir / "build-metadata" / "rootfs-input.json"
    metadata.parent.mkdir(parents=True)
    metadata.write_text(
        json.dumps(
            {
                "ubuntu": {
                    "aptSnapshot": "20250313T000000Z",
                    "baseUrl": "https://example.invalid/release",
                    "cacheKey": "release-abcd",
                }
            }
        ),
        encoding="utf-8",
    )


def write_apt_plan(path: Path, *, status: str = "allowed") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "runId": "run-test",
                "status": status,
                "snapshot": "20250313T000000Z",
                "installPackages": ["docker.io", "python3-venv"],
                "guardPackages": ["docker.io", "python3"],
                "newPackages": ["docker.io"],
                "upgradedPackages": [],
                "removedPackages": [],
                "blockedUpgrades": [],
            }
        ),
        encoding="utf-8",
    )


def write_apt_installed(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "packages": {
                    "docker.io": "26.1.3-test",
                    "python3-venv": "3.12-test",
                },
            }
        ),
        encoding="utf-8",
    )


def fake_operations(
    *,
    run: Callable[..., subprocess.CompletedProcess[str]] | None = None,
    http_status: Callable[[str, float], int] | None = None,
    sleep: Callable[[float], None] | None = None,
) -> RootfsSmokeOperations:
    return RootfsSmokeOperations(
        mount_runtime_share=lambda: None,
        mount_vital_files_share=lambda: None,
        run=run or completed,
        http_status=http_status or (lambda url, timeout_seconds: 200),
        sleep=sleep or (lambda _: None),
    )


def completed(
    arguments: list[str],
    **kwargs: object,
) -> subprocess.CompletedProcess[str]:
    stdout = ""
    if arguments[:2] == ["uname", "-r"]:
        stdout = "6.8.0-test\n"
    elif arguments[:2] == ["docker", "--version"]:
        stdout = "Docker version test\n"
    elif arguments[:2] == ["df", "-Pk"]:
        stdout = (
            "Filesystem 1024-blocks Used Available Capacity Mounted on\n"
            "/dev/vda1 8388608 1024 8387584 1% /\n"
        )
    elif arguments[:2] == ["docker", "compose"] and arguments[-3:] == [
        "ps",
        "--format",
        "json",
    ]:
        stdout = json.dumps(
            [
                {
                    "Service": "edge",
                    "State": "running",
                    "Health": "healthy",
                }
            ]
        )
    return subprocess.CompletedProcess(arguments, 0, stdout, "")


def stage_status(document: dict[str, object], name: str) -> str:
    stages = document["stages"]
    assert isinstance(stages, list)
    for stage in stages:
        assert isinstance(stage, dict)
        if stage["name"] == name:
            return str(stage["status"])
    raise AssertionError(f"missing stage: {name}")


def stage_details(document: dict[str, object], name: str) -> dict[str, object]:
    stages = document["stages"]
    assert isinstance(stages, list)
    for stage in stages:
        assert isinstance(stage, dict)
        if stage["name"] == name:
            details = stage["details"]
            assert isinstance(details, dict)
            return details
    raise AssertionError(f"missing stage: {name}")


def compose_command_suffix(commands: list[list[str]], suffix: list[str]) -> bool:
    return any(command[-len(suffix) :] == suffix for command in commands)

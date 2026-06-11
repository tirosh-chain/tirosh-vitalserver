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
    operations = fake_operations()

    run_rootfs_smoke(context=context, operations=operations)

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["schemaVersion"] == 2
    assert document["ubuntu"]["metadataStatus"] == "loaded"
    assert document["ubuntu"]["baseUrl"] == "https://example.invalid/release"
    assert document["ubuntu"]["cacheKey"] == "release-abcd"
    assert document["ubuntu"]["kernel"] == "6.8.0-test"
    assert stage_status(document, "docker-smoke") == "passed"
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


def test_rootfs_smoke_fails_when_cleanup_fails(tmp_path: Path) -> None:
    context = smoke_context(tmp_path)
    write_metadata(context.deploy_dir)

    def run(arguments: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
        if arguments[-3:] == ["down", "-v", "--remove-orphans"]:
            return subprocess.CompletedProcess(arguments, 1, "", "cleanup failed")
        return completed(arguments)

    with pytest.raises(SystemExit):
        run_rootfs_smoke(context=context, operations=fake_operations(run=run))

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["cleanup"]["status"] == "cleanup-failed"
    assert "cleanup failed" in document["cleanup"]["message"]


def test_rootfs_smoke_records_missing_input_metadata(tmp_path: Path) -> None:
    context = smoke_context(tmp_path)

    run_rootfs_smoke(context=context, operations=fake_operations())

    document = json.loads(context.manifest_path.read_text(encoding="utf-8"))
    assert document["ubuntu"]["metadataStatus"] == "missing"
    assert document["ubuntu"]["baseUrl"] == ""
    assert document["ubuntu"]["cacheKey"] == ""


def test_rootfs_smoke_cli_is_registered() -> None:
    pyproject = Path(__file__).parents[1] / "pyproject.toml"
    assert "tirosh-vitalserver-rootfs-smoke" in pyproject.read_text(encoding="utf-8")


def smoke_context(tmp_path: Path) -> RootfsSmokeContext:
    runtime_dir = tmp_path / "run"
    deploy_dir = tmp_path / "deploy"
    diagnostics_dir = runtime_dir / "rootfs-smoke-diagnostics"
    runtime_dir.mkdir(parents=True)
    deploy_dir.mkdir(parents=True)
    return RootfsSmokeContext(
        runtime_dir=runtime_dir,
        deploy_dir=deploy_dir,
        vital_files_mount=tmp_path / "vital-files",
        manifest_path=runtime_dir / "rootfs-runtime-manifest.json",
        diagnostics_dir=diagnostics_dir,
        compose_project_name="vitalserver-rootfs-smoke",
        docker_smoke_image="redis:3.2.12-alpine",
        local_docker_smoke_image="vitalserver-rootfs-smoke:local",
    )


def write_metadata(deploy_dir: Path) -> None:
    metadata = deploy_dir / "build-metadata" / "rootfs-input.json"
    metadata.parent.mkdir(parents=True)
    metadata.write_text(
        json.dumps(
            {
                "ubuntu": {
                    "baseUrl": "https://example.invalid/release",
                    "cacheKey": "release-abcd",
                }
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

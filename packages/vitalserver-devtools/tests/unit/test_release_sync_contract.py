from __future__ import annotations

import importlib.util
import json
import shutil
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parents[4]
SYNC_RELEASE_SCRIPT = (
    ROOT / "apps/vitalserver-macos-runtime/Support/Build/sync-release.py"
)


def load_sync_release_module() -> ModuleType:
    specification = importlib.util.spec_from_file_location(
        "vitalserver_sync_release",
        SYNC_RELEASE_SCRIPT,
    )
    assert specification is not None
    assert specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def release_workspace(tmp_path: Path) -> tuple[Path, Path, Path, dict[str, object]]:
    workspace = tmp_path / "workspace"
    runtime_dir = workspace / "apps/vitalserver-macos-runtime"
    compose_path = runtime_dir / "Support/Guest/compose.yaml"
    config_path = workspace / "config/vm-build.toml"
    release_path = runtime_dir / "release-dev.json"
    compose_path.parent.mkdir(parents=True)
    config_path.parent.mkdir(parents=True)
    shutil.copy2(
        ROOT / "apps/vitalserver-macos-runtime/Support/Guest/compose.yaml",
        compose_path,
    )
    shutil.copy2(ROOT / "config/vm-build.toml", config_path)
    shutil.copy2(ROOT / "apps/vitalserver-macos-runtime/release-dev.json", release_path)
    return (
        runtime_dir,
        compose_path,
        config_path,
        json.loads(release_path.read_text(encoding="utf-8")),
    )


def test_release_sync_only_materializes_designated_swift_sources(
    tmp_path: Path,
) -> None:
    module = load_sync_release_module()
    runtime_dir, compose_path, config_path, release = release_workspace(tmp_path)
    compose_before = compose_path.read_text(encoding="utf-8")
    config_before = config_path.read_text(encoding="utf-8")

    module.sync_release(runtime_dir, release, runtime_dir / "release-dev.json")

    assert compose_path.read_text(encoding="utf-8") == compose_before
    assert config_path.read_text(encoding="utf-8") == config_before
    assert (
        runtime_dir / "Sources/Bootstrap/Composition/GeneratedVersion.swift"
    ).read_text(encoding="utf-8").startswith(
        "// Generated from release-dev.json by make devtools/release-contract."
    )
    assert (
        runtime_dir
        / "Sources/Adapters/Inbound/MacControlPanel/Generated/GeneratedRelease.swift"
    ).is_file()
    generated_dir = (
        runtime_dir / "Sources/Adapters/Inbound/MacControlPanel/Generated"
    )
    assert (generated_dir / "RuntimeReleaseInfo+Generated.swift").is_file()


def test_release_sync_rejects_compose_image_drift_without_rewriting_it(
    tmp_path: Path,
) -> None:
    module = load_sync_release_module()
    runtime_dir, compose_path, _, release = release_workspace(tmp_path)
    drifted = compose_path.read_text(encoding="utf-8").replace(
        "vitalserver-recorder-recovery:0.2.0",
        "vitalserver-recorder-recovery:0.1.0",
    )
    compose_path.write_text(drifted, encoding="utf-8")

    with pytest.raises(SystemExit, match="Guest compose image mismatch"):
        module.sync_release(runtime_dir, release, runtime_dir / "release-dev.json")

    assert compose_path.read_text(encoding="utf-8") == drifted
    assert not (runtime_dir / "Sources").exists()


def test_release_sync_rejects_vm_docker_image_drift_without_rewriting_it(
    tmp_path: Path,
) -> None:
    module = load_sync_release_module()
    runtime_dir, _, config_path, release = release_workspace(tmp_path)
    drifted = config_path.read_text(encoding="utf-8").replace(
        'recorder_recovery_image = "vitalserver-recorder-recovery:0.2.0"',
        'recorder_recovery_image = "vitalserver-recorder-recovery:0.1.0"',
    )
    config_path.write_text(drifted, encoding="utf-8")

    with pytest.raises(SystemExit, match="VM Docker image field mismatch"):
        module.sync_release(runtime_dir, release, runtime_dir / "release-dev.json")

    assert config_path.read_text(encoding="utf-8") == drifted
    assert not (runtime_dir / "Sources").exists()

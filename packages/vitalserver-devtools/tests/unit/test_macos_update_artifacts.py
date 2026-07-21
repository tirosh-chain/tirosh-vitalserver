from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release import update_artifacts


def test_stage_update_artifacts_uses_shared_staging_cleanup(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    artifact_dir = tmp_path / "update"
    old_metadata = artifact_dir / "deploy/node_modules/.DS_Store"
    old_metadata.parent.mkdir(parents=True)
    old_metadata.write_bytes(b"finder")
    removed: list[Path] = []
    real_remove_staging_tree = update_artifacts.remove_staging_tree

    def remove_staging_tree(path: Path) -> None:
        removed.append(path)
        real_remove_staging_tree(path)

    monkeypatch.setattr(update_artifacts, "remove_staging_tree", remove_staging_tree)
    monkeypatch.setattr(update_artifacts, "tar_directory", lambda *args: None)
    monkeypatch.setattr(update_artifacts, "copy_executable", lambda *args: None)
    monkeypatch.setattr(
        update_artifacts,
        "render_packaging_executable",
        lambda *args: None,
    )
    monkeypatch.setattr(update_artifacts, "copy_tree", lambda *args: None)
    monkeypatch.setattr(update_artifacts, "stage_guest_deploy", lambda plan: None)
    monkeypatch.setattr(
        update_artifacts,
        "settings_install_value",
        lambda settings, key: f"/usr/local/bin/{key}",
    )

    staged = update_artifacts.stage_update_artifacts(
        runtime_dir=tmp_path / "runtime",
        settings=SimpleNamespace(),
        artifact_dir=artifact_dir,
        app_bundle=tmp_path / "VitalServer Helper.app",
        runtime_cli=tmp_path / "vitalserver-vm",
        nginx_bundle=tmp_path / "nginx",
        guest_deploy_plan=SimpleNamespace(),
    )

    assert removed == [artifact_dir]
    assert not old_metadata.exists()
    assert (artifact_dir / "runtime-tools").is_dir()
    assert (artifact_dir / "deploy").is_dir()
    assert staged.guest_deploy == artifact_dir / "guest-deploy.tar.gz"

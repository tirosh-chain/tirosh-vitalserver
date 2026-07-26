from __future__ import annotations

import errno
import tarfile
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.adapters.macos_release import artifact_files


def test_tar_directory_excludes_non_product_metadata(tmp_path: Path) -> None:
    payload = tmp_path / "deploy"
    (payload / "app/__pycache__").mkdir(parents=True)
    (payload / "app/main.py").write_text("print('ready')\n", encoding="utf-8")
    (payload / ".DS_Store").write_bytes(b"finder")
    (payload / "app/._main.py").write_bytes(b"apple-double")
    (payload / "app/__pycache__/main.pyc").write_bytes(b"cache")
    archive = tmp_path / "deploy.tar.gz"

    artifact_files.tar_directory(archive, tmp_path, "deploy")

    with tarfile.open(archive, "r:gz") as tar:
        names = tar.getnames()
    assert "deploy/app/main.py" in names
    assert all(".DS_Store" not in name for name in names)
    assert all("._main.py" not in name for name in names)
    assert all("__pycache__" not in name for name in names)


def test_remove_staging_tree_retries_finder_metadata_race(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    staging = tmp_path / "root"
    node_modules = staging / "node_modules"
    node_modules.mkdir(parents=True)
    (node_modules / ".DS_Store").write_bytes(b"finder")
    real_rmtree = artifact_files.shutil.rmtree
    attempts = 0

    def racing_rmtree(path: Path) -> None:
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise OSError(errno.ENOTEMPTY, "Directory not empty", str(node_modules))
        real_rmtree(path)

    monkeypatch.setattr(artifact_files.shutil, "rmtree", racing_rmtree)
    monkeypatch.setattr(artifact_files.time, "sleep", lambda _: None)

    artifact_files.remove_staging_tree(staging)

    assert attempts == 2
    assert not staging.exists()


def test_remove_staging_tree_preserves_non_finder_failures(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    staging = tmp_path / "root"
    staging.mkdir()

    def denied_rmtree(path: Path) -> None:
        raise PermissionError(errno.EACCES, "Permission denied", str(path))

    monkeypatch.setattr(artifact_files.shutil, "rmtree", denied_rmtree)

    with pytest.raises(PermissionError, match="Permission denied"):
        artifact_files.remove_staging_tree(staging)

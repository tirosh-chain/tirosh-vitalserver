from __future__ import annotations

import shutil
import tarfile
from pathlib import Path


def tar_directory(archive_path: Path, base_dir: Path, *names: str) -> None:
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "w:gz") as archive:
        for name in names:
            archive.add(base_dir / name, arcname=name)


def install_file(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise SystemExit(f"error: missing file: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def copy_executable(source: Path, destination: Path) -> None:
    install_file(source, destination)
    destination.chmod(0o755)


def copy_tree(source: Path, destination: Path, *, merge: bool = False) -> None:
    if not source.is_dir():
        raise SystemExit(f"error: missing directory: {source}")
    if destination.exists() and not merge:
        shutil.rmtree(destination)
    shutil.copytree(
        source,
        destination,
        dirs_exist_ok=merge,
        ignore=shutil.ignore_patterns(".DS_Store", "._*", "__pycache__"),
    )


def remove_apple_double_files(path: Path) -> None:
    for child in path.rglob("._*"):
        if child.is_file():
            child.unlink()


def remove_path(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()

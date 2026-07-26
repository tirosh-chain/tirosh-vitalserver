from __future__ import annotations

import errno
import shutil
import tarfile
import time
from contextlib import suppress
from fnmatch import fnmatchcase
from pathlib import Path, PurePosixPath

ARTIFACT_IGNORED_NAMES = (".DS_Store", "._*", "__pycache__")
STAGING_TREE_REMOVE_ATTEMPTS = 5


def tar_directory(archive_path: Path, base_dir: Path, *names: str) -> None:
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive_path, "w:gz") as archive:
        for name in names:
            archive.add(
                base_dir / name,
                arcname=name,
                filter=_exclude_non_product_metadata,
            )


def _exclude_non_product_metadata(info: tarfile.TarInfo) -> tarfile.TarInfo | None:
    if any(
        fnmatchcase(part, pattern)
        for part in PurePosixPath(info.name).parts
        for pattern in ARTIFACT_IGNORED_NAMES
    ):
        return None
    return info


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
        remove_staging_tree(destination)
    shutil.copytree(
        source,
        destination,
        dirs_exist_ok=merge,
        ignore=shutil.ignore_patterns(*ARTIFACT_IGNORED_NAMES),
    )


def remove_apple_double_files(path: Path) -> None:
    for child in path.rglob("._*"):
        if child.is_file():
            child.unlink()


def remove_path(path: Path) -> None:
    if path.is_dir() and not path.is_symlink():
        remove_staging_tree(path)
    else:
        path.unlink()


def remove_staging_tree(path: Path) -> None:
    for attempt in range(1, STAGING_TREE_REMOVE_ATTEMPTS + 1):
        try:
            shutil.rmtree(path)
            return
        except OSError as error:
            if (
                error.errno != errno.ENOTEMPTY
                or attempt == STAGING_TREE_REMOVE_ATTEMPTS
            ):
                raise
            _remove_finder_metadata(path)
            time.sleep(0.05)


def _remove_finder_metadata(path: Path) -> None:
    if not path.exists():
        return
    for pattern in (".DS_Store", "._*"):
        for metadata in path.rglob(pattern):
            if metadata.is_file():
                with suppress(FileNotFoundError):
                    metadata.unlink()

"""Local `.vital` file discovery."""

from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.core.domain.vital_file.models import PayloadFile


def iter_vital_files(path: str | Path) -> tuple[PayloadFile, ...]:
    """Return `.vital` files from a file or directory, sorted by path."""

    root = Path(path)

    if root.is_file():
        files = [root]
    elif root.is_dir():
        files = sorted(root.rglob("*.vital"))
    else:
        raise FileNotFoundError(root)

    return tuple(
        PayloadFile(path=file_path, size_bytes=file_path.stat().st_size)
        for file_path in files
    )

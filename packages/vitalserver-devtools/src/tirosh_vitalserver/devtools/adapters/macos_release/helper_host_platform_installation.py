from __future__ import annotations

import hashlib
import json
import stat
from pathlib import Path

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_host_platform_installation import (
    ImmutableReleaseFile,
)


def immutable_release_files(
    release_root: Path,
    *,
    exclude_release_manifest: bool = False,
) -> tuple[ImmutableReleaseFile, ...]:
    entries: list[ImmutableReleaseFile] = []
    for path in sorted(release_root.rglob("*")):
        if path.is_dir():
            continue
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
            raise DomainError(f"Helper Host release entry must be regular path={path}")
        relative = path.relative_to(release_root).as_posix()
        if exclude_release_manifest and relative == "installation-manifest.json":
            continue
        entries.append(
            ImmutableReleaseFile(
                relative_path=relative,
                sha256=sha256_file(path),
                executable=bool(mode & 0o111),
            )
        )
    if not entries:
        raise DomainError("Helper Host release must contain immutable files")
    return tuple(entries)


def sha256_regular_file_tree(root: Path) -> str:
    digest = hashlib.sha256()
    for entry in immutable_release_files(root):
        digest.update(b"regular-file\0")
        digest.update(entry.relative_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(entry.sha256.encode("ascii"))
        digest.update(b"\0")
    return digest.hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def write_json_document(path: Path, document: dict[str, object]) -> None:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(document, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    except OSError as error:
        raise DomainError(
            f"Helper Host JSON document write failed path={path}: {error}"
        ) from error

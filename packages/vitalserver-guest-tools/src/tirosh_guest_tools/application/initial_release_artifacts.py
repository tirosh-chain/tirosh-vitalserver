from __future__ import annotations

import hashlib
import json
import os
import stat
import tarfile
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any

from tirosh_guest_tools.domain.initial_update_owner_state import SCHEMA_VERSION

FRESH_INSTALL_RELEASE_SCHEMA_VERSION = (
    "vitalserver.fresh-install-release-identity/v1"
)


def compose_initial_update_owner_artifacts(
    *,
    release_identity_path: Path,
    deploy_dir: Path,
    container_archive: Path,
    guest_tools_home: Path,
) -> Path:
    release_label = load_release_label(release_identity_path)
    output_dir = deploy_dir / "initial-owner-artifacts"
    output_dir.mkdir(parents=True, exist_ok=True)
    guest_runtime_archive = output_dir / "guest-runtime-release.tar"
    write_deterministic_tar(guest_tools_home, guest_runtime_archive)
    container_digest = sha256_file(container_archive)
    guest_runtime_digest = sha256_file(guest_runtime_archive)
    contract = {
        "schemaVersion": SCHEMA_VERSION,
        "releaseLabel": release_label,
        "containerImageSet": owner_document(
            kind="container-image-set",
            release_label=release_label,
            relative_path=container_archive.relative_to(deploy_dir).as_posix(),
            digest=container_digest,
        ),
        "guestRuntimeRelease": owner_document(
            kind="guest-runtime-release",
            release_label=release_label,
            relative_path=guest_runtime_archive.relative_to(deploy_dir).as_posix(),
            digest=guest_runtime_digest,
        ),
    }
    destination = deploy_dir / "initial-update-owner-state.json"
    write_json_atomic(destination, contract)
    return destination


def load_release_label(path: Path) -> str:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"Fresh-install release identity is unavailable or invalid: {path}: {error}"
        ) from error
    if (
        not isinstance(document, dict)
        or set(document) != {"schemaVersion", "releaseLabel"}
        or document.get("schemaVersion") != FRESH_INSTALL_RELEASE_SCHEMA_VERSION
        or not isinstance(document.get("releaseLabel"), str)
        or not document["releaseLabel"]
    ):
        raise RuntimeError(
            f"Fresh-install release identity contract is invalid: {path}"
        )
    return document["releaseLabel"]


def owner_document(
    *,
    kind: str,
    release_label: str,
    relative_path: str,
    digest: str,
) -> dict[str, Any]:
    return {
        "identity": f"{kind}:{release_label}",
        "artifact": {
            "relativePath": relative_path,
            "digest": f"sha256:{digest}",
            "ownerReference": f"{kind}/{digest}.archive",
        },
    }


def write_deterministic_tar(source: Path, destination: Path) -> None:
    if source.is_symlink() or not source.is_dir():
        raise RuntimeError(f"Guest Runtime source must be a directory: {source}")
    temporary = destination.with_name(f".{destination.name}.tmp-{os.getpid()}")
    temporary.unlink(missing_ok=True)
    try:
        with tarfile.open(temporary, "w", format=tarfile.PAX_FORMAT) as archive:
            for path in sorted(source.rglob("*")):
                relative = path.relative_to(source)
                file_status = path.lstat()
                if stat.S_ISLNK(file_status.st_mode):
                    raise RuntimeError(
                        f"Guest Runtime source must not contain symlinks: {path}"
                    )
                if not (
                    stat.S_ISDIR(file_status.st_mode)
                    or stat.S_ISREG(file_status.st_mode)
                ):
                    raise RuntimeError(
                        f"Guest Runtime source entry is unsupported: {path}"
                    )
                info = archive.gettarinfo(str(path), arcname=relative.as_posix())
                info.uid = 0
                info.gid = 0
                info.uname = ""
                info.gname = ""
                info.mtime = 0
                if info.isfile():
                    with path.open("rb") as stream:
                        archive.addfile(info, stream)
                else:
                    archive.addfile(info)
        os.replace(temporary, destination)
    finally:
        temporary.unlink(missing_ok=True)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise RuntimeError(f"Release artifact read failed: {path}: {error}") from error
    return digest.hexdigest()


def write_json_atomic(path: Path, document: dict[str, Any]) -> None:
    encoded = (
        json.dumps(document, indent=2, sort_keys=True).encode("utf-8") + b"\n"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(encoded)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)

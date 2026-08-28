from __future__ import annotations

import gzip
import hashlib
import json
import stat
import tarfile
from contextlib import suppress
from pathlib import Path

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_host_platform_release import (
    HELPER_HOST_ARCHIVE_MEDIA_TYPE,
    validate_helper_host_platform_release_documents,
)


def compose_helper_host_platform_release_archive(
    composition_path: Path,
    output: Path,
) -> tuple[str, int, str]:
    composition = read_json(composition_path, "Helper Host archive composition")
    release_root = Path(str(composition.get("releaseSourceDirectory", "")))
    manifest_path = release_root / "installation-manifest.json"
    manifest = read_json(manifest_path, "Helper Host installation manifest")
    try:
        validate_helper_host_platform_release_documents(composition, manifest)
    except ValueError as error:
        raise DomainError(str(error)) from error
    require_new_output(output)

    entries: list[tuple[str, Path, int]] = [
        ("release/installation-manifest.json", manifest_path, 0o644)
    ]
    expected = {"installation-manifest.json"}
    for declaration in manifest["files"]:
        relative = str(declaration["relativePath"])
        source = release_root / relative
        verify_regular_file_digest(source, str(declaration["sha256"]))
        entries.append(
            (
                f"release/{relative}",
                source,
                0o755 if declaration["executable"] else 0o644,
            )
        )
        expected.add(relative)
    verify_release_closure(release_root, expected)
    operator = manifest["operatorInterface"]
    application_bundle = release_root / str(operator["applicationBundleRelativePath"])
    actual_tree_sha256 = sha256_regular_file_tree(application_bundle)
    expected_tree_sha256 = str(operator["applicationBundleTreeSha256"])
    if actual_tree_sha256 != expected_tree_sha256:
        raise DomainError(
            "Helper Host application bundle tree digest differs "
            f"path={application_bundle} expected={expected_tree_sha256} "
            f"actual={actual_tree_sha256}"
        )

    source_by_role = {
        str(source["role"]): Path(str(source["sourcePath"]))
        for source in composition["serviceDefinitionSources"]
    }
    for service in manifest["replaceableServices"]:
        role = str(service["role"])
        source = source_by_role[role]
        verify_regular_file_digest(source, str(service["definitionSha256"]))
        entries.append((f"service-definitions/{role}.plist", source, 0o644))
    bootstrap = Path(str(composition["operatorInterfaceBootstrapSourcePath"]))
    verify_regular_file_digest(
        bootstrap,
        str(manifest["operatorInterface"]["bootstrapConfigurationSha256"]),
    )
    entries.append(
        ("operator-interface/runtime-console-bootstrap.json", bootstrap, 0o644)
    )
    write_archive(output, sorted(entries))
    return sha256_file(output), output.stat().st_size, HELPER_HOST_ARCHIVE_MEDIA_TYPE


def read_json(path: Path, owner: str) -> dict[str, object]:
    require_regular_file(path, owner)
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise DomainError(f"{owner} decode failed path={path}: {error}") from error
    if not isinstance(document, dict):
        raise DomainError(f"{owner} must be an object path={path}")
    return document


def require_regular_file(path: Path, owner: str) -> None:
    try:
        mode = path.lstat().st_mode
    except OSError as error:
        raise DomainError(f"{owner} inspection failed path={path}: {error}") from error
    if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
        raise DomainError(f"{owner} must be a regular non-symlink file: {path}")


def verify_regular_file_digest(path: Path, expected: str) -> None:
    require_regular_file(path, "Helper Host release source")
    actual = sha256_file(path)
    if actual != expected:
        raise DomainError(
            f"Helper Host release source digest differs path={path} "
            f"expected={expected} actual={actual}"
        )


def verify_release_closure(root: Path, expected: set[str]) -> None:
    try:
        paths = sorted(root.rglob("*"))
    except OSError as error:
        raise DomainError(f"Helper Host release tree read failed: {error}") from error
    actual: set[str] = set()
    for path in paths:
        relative = path.relative_to(root).as_posix()
        if path.is_dir():
            continue
        require_regular_file(path, "Helper Host release tree entry")
        actual.add(relative)
    if actual != expected:
        raise DomainError(
            "Helper Host release tree closure differs "
            f"missing={sorted(expected - actual)} unknown={sorted(actual - expected)}"
        )


def require_new_output(output: Path) -> None:
    if output.exists():
        raise DomainError(f"Helper Host archive output already exists: {output}")
    if not output.is_absolute() or not output.parent.is_dir():
        raise DomainError(
            f"Helper Host archive output parent is unavailable: {output.parent}"
        )


def write_archive(output: Path, entries: list[tuple[str, Path, int]]) -> None:
    try:
        with (
            output.open("xb") as raw,
            gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed,
            tarfile.open(fileobj=compressed, mode="w") as archive,
        ):
            for name, source, mode in entries:
                info = tarfile.TarInfo(name)
                info.size = source.stat().st_size
                info.mode = mode
                info.mtime = 0
                info.uid = info.gid = 0
                with source.open("rb") as stream:
                    archive.addfile(info, stream)
    except (OSError, tarfile.TarError) as error:
        with suppress(OSError):
            output.unlink(missing_ok=True)
        raise DomainError(
            f"Helper Host archive write failed path={output}: {error}"
        ) from error


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise DomainError(
            f"artifact digest read failed path={path}: {error}"
        ) from error
    return digest.hexdigest()


def sha256_regular_file_tree(root: Path) -> str:
    try:
        root_mode = root.lstat().st_mode
    except OSError as error:
        raise DomainError(
            f"Helper Host application bundle inspection failed path={root}: {error}"
        ) from error
    if stat.S_ISLNK(root_mode) or not stat.S_ISDIR(root_mode):
        raise DomainError(
            f"Helper Host application bundle must be a non-symlink directory: {root}"
        )
    digest = hashlib.sha256()
    try:
        descendants = sorted(root.rglob("*"))
    except OSError as error:
        raise DomainError(
            f"Helper Host application bundle walk failed path={root}: {error}"
        ) from error
    for path in descendants:
        try:
            mode = path.lstat().st_mode
        except OSError as error:
            raise DomainError(
                f"Helper Host application bundle inspection failed path={path}: {error}"
            ) from error
        if stat.S_ISDIR(mode):
            continue
        if stat.S_ISLNK(mode) or not stat.S_ISREG(mode):
            raise DomainError(
                "Helper Host application bundle contains unsupported path state: "
                f"{path}"
            )
        relative = path.relative_to(root).as_posix()
        digest.update(b"regular-file\0")
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(sha256_file(path).encode("ascii"))
        digest.update(b"\0")
    return digest.hexdigest()

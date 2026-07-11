#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import zipfile


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build the strict SHA-256 allowlist catalog delivered separately from VitalServer update archives."
    )
    parser.add_argument("--archive", type=Path, action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = build_catalog(args.archive, args.output)
    print(json.dumps(result, sort_keys=True))
    return 0


def build_catalog(archives: list[Path], output: Path) -> dict[str, object]:
    if not archives:
        raise ValueError("at least one update archive is required")
    artifacts: list[dict[str, object]] = []
    names: set[str] = set()
    digests: set[str] = set()
    for candidate in archives:
        metadata = candidate.lstat()
        if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
            raise ValueError(f"update archive must be a non-symlink regular file path={candidate}")
        path = candidate.resolve(strict=True)
        validate_publishable_archive(path)
        if path.name in names:
            raise ValueError(f"update archive basename is duplicated name={path.name}")
        digest = sha256(path)
        if digest in digests:
            raise ValueError(f"update archive content digest is duplicated sha256={digest}")
        names.add(path.name)
        digests.add(digest)
        artifacts.append({"name": path.name, "sha256": digest, "sizeBytes": metadata.st_size})
    document = {"schemaVersion": 1, "sha256": sorted(digests)}
    data = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
    write_atomic(output, data)
    return {
        "schemaVersion": 1,
        "catalogPath": str(output.resolve()),
        "catalogSHA256": hashlib.sha256(data).hexdigest(),
        "artifacts": sorted(artifacts, key=lambda item: str(item["name"])),
    }


def validate_publishable_archive(path: Path) -> None:
    if not zipfile.is_zipfile(path):
        return
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            release_name = "VitalServer-Windows/release.json"
            proof_name = "VitalServer-Windows/proof/windows-hyperv-acceptance.json"
            pending_name = "VitalServer-Windows/proof/acceptance-pending.json"
            if release_name not in names:
                raise ValueError(f"Windows update archive release owner is missing path={path}")
            release = json.loads(archive.read(release_name))
            if (
                not isinstance(release, dict)
                or release.get("schemaVersion") != 1
                or release.get("state") != "releaseCandidate"
                or not isinstance(release.get("installedAcceptanceRunId"), str)
                or not release["installedAcceptanceRunId"]
                or proof_name not in names
                or pending_name in names
            ):
                raise ValueError(
                    f"Windows update archive is not a sealed releaseCandidate path={path}"
                )
    except (zipfile.BadZipFile, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"Windows update archive proof decode failed path={path}: {error}") from error


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    raise SystemExit(main())

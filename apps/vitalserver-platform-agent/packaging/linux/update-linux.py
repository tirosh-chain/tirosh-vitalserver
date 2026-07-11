#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from datetime import UTC, datetime
from typing import BinaryIO


ROOT_NAME = "VitalServer-Linux"
MAX_MEMBERS = 100_000
MAX_EXPANDED_BYTES = 100 * 1024 * 1024 * 1024
CHECKSUM_PATTERN = re.compile(r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9._/+\-]*)")


class UpdateBundleError(ValueError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify or apply a VitalServer Linux offline update bundle.")
    parser.add_argument("action", choices=("summary", "verify", "apply"))
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--operation-id")
    parser.add_argument("--operation-document", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.action == "apply":
        if not args.operation_id or args.operation_document is None:
            raise SystemExit("apply requires --operation-id and --operation-document")
        return apply_bundle(args.bundle, args.operation_id, args.operation_document)
    started_at = _now()
    if args.action == "verify" and (args.operation_id or args.operation_document):
        if not args.operation_id or args.operation_document is None:
            raise SystemExit("verify operation requires both --operation-id and --operation-document")
        _write_operation(
            args.operation_document, args.operation_id, "update-verify", "running",
            started_at, None, None,
        )
    try:
        release = verify_bundle(args.bundle)
    except UpdateBundleError as error:
        if args.action == "verify" and args.operation_id and args.operation_document:
            _write_operation(
                args.operation_document, args.operation_id, "update-verify", "failed",
                started_at, None, {"kind": "updateVerifyFailed", "message": str(error)},
            )
        print(json.dumps({"state": "failed", "failure": {"kind": "updateBundleInvalid", "message": str(error)}}))
        return 1
    if args.action == "summary":
        print(json.dumps({
            "summary": (
                f"VitalServer Linux {release['platformVersion']} / "
                f"Runtime Bundle {release['runtimeBundleVersion']} / linux/amd64"
            ),
            "release": release,
        }, sort_keys=True))
    else:
        if args.operation_id and args.operation_document:
            _write_operation(
                args.operation_document, args.operation_id, "update-verify", "completed",
                started_at, _operation_release(release), None,
            )
        print(json.dumps({"state": "verified", "release": release}, sort_keys=True))
    return 0


def verify_bundle(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise UpdateBundleError(f"update bundle is missing or not a file: {path}")
    try:
        with tarfile.open(path, mode="r:gz") as archive:
            members = _validated_members(archive)
            checksums = _read_checksums(archive, members)
            regular = {
                name.removeprefix(f"{ROOT_NAME}/")
                for name, member in members.items()
                if member.isfile() and name != f"{ROOT_NAME}/checksums.sha256"
            }
            if set(checksums) != regular:
                missing = sorted(regular - set(checksums))
                unexpected = sorted(set(checksums) - regular)
                raise UpdateBundleError(
                    f"checksum inventory differs missing={missing[:10]} unexpected={unexpected[:10]}"
                )
            for relative, expected in checksums.items():
                member = members[f"{ROOT_NAME}/{relative}"]
                source = archive.extractfile(member)
                if source is None:
                    raise UpdateBundleError(f"update bundle member is unreadable: {relative}")
                actual = _stream_sha256(source)
                if actual != expected:
                    raise UpdateBundleError(
                        f"update bundle checksum mismatch member={relative} expected={expected} actual={actual}"
                    )
            release = _read_json_member(archive, members, f"{ROOT_NAME}/release.json")
    except (tarfile.TarError, OSError, EOFError) as error:
        raise UpdateBundleError(f"update bundle read failed path={path}: {error}") from error
    if not isinstance(release, dict):
        raise UpdateBundleError("release.json must be an object")
    if release.get("schemaVersion") != 1:
        raise UpdateBundleError("release.json schemaVersion must be 1")
    target = release.get("target")
    if not isinstance(target, dict) or target.get("os") != "linux" or target.get("architecture") != "amd64":
        raise UpdateBundleError("update bundle target must be linux/amd64")
    for field in ("platformVersion", "runtimeBundleVersion"):
        value = release.get(field)
        if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9._+\-]+", value):
            raise UpdateBundleError(f"release.json {field} is invalid")
    return release


def apply_bundle(path: Path, operation_id: str, operation_document: Path) -> int:
    if not re.fullmatch(r"[A-Za-z0-9._+\-]+", operation_id):
        raise SystemExit("operation id is invalid")
    started_at = _now()
    _write_operation(
        operation_document, operation_id, "update-apply", "running",
        started_at, None, None,
    )
    try:
        with tempfile.TemporaryDirectory(prefix="vitalserver-linux-update-") as temporary:
            root = Path(temporary)
            owned_bundle = root / "update-bundle.tar.gz"
            shutil.copyfile(path, owned_bundle)
            release = verify_bundle(owned_bundle)
            _extract_verified(owned_bundle, root)
            installer = root / ROOT_NAME / "install.sh"
            result = subprocess.run(
                [
                    str(installer),
                    "--acceptance-support-export-mode",
                    "capability-only",
                ],
                cwd=installer.parent,
            )
            if result.returncode != 0:
                raise UpdateBundleError(f"Linux installer failed exitCode={result.returncode}")
        _write_operation(
            operation_document, operation_id, "update-apply", "completed",
            started_at, _operation_release(release), None,
        )
        return 0
    except Exception as error:
        failure = {"kind": "updateApplyFailed", "message": str(error)}
        _write_operation(
            operation_document, operation_id, "update-apply", "failed",
            started_at, None, failure,
        )
        print(f"VitalServer Linux update failed operationId={operation_id}: {error}", file=sys.stderr)
        return 1


def _validated_members(archive: tarfile.TarFile) -> dict[str, tarfile.TarInfo]:
    members: dict[str, tarfile.TarInfo] = {}
    expanded = 0
    for index, member in enumerate(archive):
        if index >= MAX_MEMBERS:
            raise UpdateBundleError(f"update bundle has more than {MAX_MEMBERS} members")
        name = member.name
        path = PurePosixPath(name)
        if (
            not name
            or name.startswith("/")
            or "\\" in name
            or path.parts[0] != ROOT_NAME
            or any(part in {"", ".", ".."} for part in path.parts)
        ):
            raise UpdateBundleError(f"update bundle member path is unsafe: {name!r}")
        if name in members:
            raise UpdateBundleError(f"update bundle has duplicate member: {name}")
        if not (member.isfile() or member.isdir()):
            raise UpdateBundleError(f"update bundle member type is unsupported: {name}")
        if member.isfile():
            expanded += member.size
            if expanded > MAX_EXPANDED_BYTES:
                raise UpdateBundleError("update bundle expanded size exceeds 100 GiB")
        members[name] = member
    required = {
        f"{ROOT_NAME}/release.json",
        f"{ROOT_NAME}/checksums.sha256",
        f"{ROOT_NAME}/install.sh",
    }
    missing = sorted(required - set(members))
    if missing:
        raise UpdateBundleError(f"update bundle required members are missing: {missing}")
    return members


def _read_checksums(
    archive: tarfile.TarFile,
    members: dict[str, tarfile.TarInfo],
) -> dict[str, str]:
    name = f"{ROOT_NAME}/checksums.sha256"
    source = archive.extractfile(members[name])
    if source is None:
        raise UpdateBundleError("checksums.sha256 is unreadable")
    try:
        text = source.read().decode("utf-8")
    except UnicodeDecodeError as error:
        raise UpdateBundleError(f"checksums.sha256 is not UTF-8: {error}") from error
    checksums: dict[str, str] = {}
    for line_number, line in enumerate(text.splitlines(), start=1):
        match = CHECKSUM_PATTERN.fullmatch(line)
        if match is None:
            raise UpdateBundleError(f"checksums.sha256 line is invalid line={line_number}")
        digest, relative = match.groups()
        path = PurePosixPath(relative)
        if path.is_absolute() or ".." in path.parts or "\\" in relative:
            raise UpdateBundleError(f"checksum path is unsafe line={line_number}")
        if relative in checksums:
            raise UpdateBundleError(f"checksum path is duplicated: {relative}")
        checksums[relative] = digest
    if not checksums:
        raise UpdateBundleError("checksums.sha256 is empty")
    return checksums


def _read_json_member(
    archive: tarfile.TarFile,
    members: dict[str, tarfile.TarInfo],
    name: str,
) -> object:
    source = archive.extractfile(members[name])
    if source is None:
        raise UpdateBundleError(f"JSON member is unreadable: {name}")
    try:
        return json.load(source)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise UpdateBundleError(f"JSON member is invalid member={name}: {error}") from error


def _extract_verified(path: Path, output: Path) -> None:
    with tarfile.open(path, mode="r:gz") as archive:
        members = _validated_members(archive)
        for name, member in members.items():
            destination = output.joinpath(*PurePosixPath(name).parts)
            if member.isdir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            source = archive.extractfile(member)
            if source is None:
                raise UpdateBundleError(f"update bundle member is unreadable: {name}")
            with destination.open("wb") as stream:
                shutil.copyfileobj(source, stream, length=1024 * 1024)
            os.chmod(destination, member.mode & 0o777)


def _stream_sha256(source: BinaryIO) -> str:
    digest = hashlib.sha256()
    for block in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(block)
    return digest.hexdigest()


def _write_operation(
    path: Path,
    operation_id: str,
    kind: str,
    state: str,
    started_at: str,
    release: dict[str, object] | None,
    failure: dict[str, str] | None,
) -> None:
    document = {
        "schemaVersion": 1,
        "operationId": operation_id,
        "kind": kind,
        "state": state,
        "startedAt": started_at,
        "updatedAt": _now(),
        "release": release,
        "artifact": None,
        "failure": failure,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(document, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def _now() -> str:
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _operation_release(release: dict[str, object]) -> dict[str, object]:
    return {
        "platformVersion": release["platformVersion"],
        "runtimeBundleVersion": release["runtimeBundleVersion"],
    }


if __name__ == "__main__":
    raise SystemExit(main())

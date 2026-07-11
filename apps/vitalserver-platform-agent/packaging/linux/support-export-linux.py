#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile


DEFAULT_SUPPORT_DIRECTORY = Path("/var/lib/vitalserver/support")
SAFE_OWNER_FILES = (
    Path("/var/lib/vitalserver/install.json"),
    Path("/var/lib/vitalserver/run/runtime-endpoint.json"),
    Path("/var/lib/vitalserver/run/runtime-provider.json"),
)
SERVICE_NAMES = (
    "vitalserver-platform-agent.service",
    "vitalserver-runtime-provider.service",
    "vitalserver-runtime-controller.service",
)
SYSTEMD_STATUS_PROPERTIES = (
    "Id",
    "LoadState",
    "ActiveState",
    "SubState",
    "UnitFileState",
    "ExecMainCode",
    "ExecMainStatus",
    "Result",
    "ActiveEnterTimestamp",
    "InactiveEnterTimestamp",
)
OPERATION_ID_PATTERN = re.compile(r"workflow-[0-9a-f]{32}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a VitalServer Linux support bundle.")
    parser.add_argument("--operation-id", required=True)
    parser.add_argument("--operation-document", type=Path, required=True)
    parser.add_argument("--support-directory", type=Path, default=DEFAULT_SUPPORT_DIRECTORY)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if OPERATION_ID_PATTERN.fullmatch(args.operation_id) is None:
        raise SystemExit("operation id is invalid")
    started_at = now()
    write_operation(args.operation_document, args.operation_id, "running", started_at, None, None)
    try:
        args.support_directory.mkdir(parents=True, exist_ok=True)
        os.chmod(args.support_directory, 0o700)
        destination = args.support_directory / f"vitalserver-support-{args.operation_id}.tar.gz"
        if destination.exists():
            raise RuntimeError(f"support artifact already exists path={destination}")
        with tempfile.TemporaryDirectory(prefix="vitalserver-support-") as temporary:
            bundle = Path(temporary) / "vitalserver-support"
            bundle.mkdir(mode=0o700)
            collected: list[dict[str, object]] = []
            for source in SAFE_OWNER_FILES:
                collect_owner(source, bundle / "owners" / source.name, collected)
            diagnostics = bundle / "diagnostics"
            diagnostics.mkdir()
            for service in SERVICE_NAMES:
                collect_command(
                    [
                        "systemctl",
                        "show",
                        service,
                        "--no-pager",
                        f"--property={','.join(SYSTEMD_STATUS_PROPERTIES)}",
                    ],
                    diagnostics / f"{service}.status.txt",
                    collected,
                )
                collect_command(
                    ["journalctl", "-u", service, "--no-pager", "-n", "2000", "--output=short-iso-precise"],
                    diagnostics / f"{service}.journal.txt",
                    collected,
                )
            manifest = {
                "schemaVersion": 1,
                "operationId": args.operation_id,
                "generatedAt": now(),
                "platform": "linux",
                "files": collected,
                "excluded": [
                    "/etc/vitalserver/platform-agent.json",
                    "/etc/vitalserver/secrets",
                    "runtime product settings and datastore contents",
                ],
            }
            write_json(bundle / "manifest.json", manifest, 0o600)
            temporary_archive = Path(temporary) / destination.name
            with tarfile.open(temporary_archive, "w:gz", format=tarfile.PAX_FORMAT) as archive:
                archive.add(bundle, arcname=bundle.name, recursive=True)
            descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            try:
                with os.fdopen(descriptor, "wb") as target, temporary_archive.open("rb") as source:
                    for block in iter(lambda: source.read(1024 * 1024), b""):
                        target.write(block)
                    target.flush()
                    os.fsync(target.fileno())
            except Exception:
                destination.unlink(missing_ok=True)
                raise
        artifact = {
            "path": str(destination),
            "sha256": file_sha256(destination),
            "sizeBytes": destination.stat().st_size,
        }
        write_operation(args.operation_document, args.operation_id, "completed", started_at, artifact, None)
        return 0
    except Exception as error:
        write_operation(
            args.operation_document,
            args.operation_id,
            "failed",
            started_at,
            None,
            {"kind": "supportExportFailed", "message": str(error)},
        )
        print(f"VitalServer support export failed operationId={args.operation_id}: {error}", file=os.sys.stderr)
        return 1


def collect_owner(source: Path, destination: Path, files: list[dict[str, object]]) -> None:
    archive_path = str(destination.relative_to(destination.parents[1]))
    if not source.exists():
        files.append({"source": str(source), "archivePath": None, "state": "missing"})
        return
    if source.is_symlink() or not source.is_file():
        files.append({
            "source": str(source),
            "archivePath": None,
            "state": "invalid",
            "reason": "not a regular file",
        })
        return
    try:
        data = source.read_bytes()
    except OSError as error:
        files.append({
            "source": str(source),
            "archivePath": None,
            "state": "read-failed",
            "reason": str(error),
        })
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(data)
    os.chmod(destination, 0o600)
    files.append({
        "source": str(source),
        "archivePath": archive_path,
        "state": "collected",
        "sizeBytes": len(data),
    })


def collect_command(command: list[str], destination: Path, files: list[dict[str, object]]) -> None:
    try:
        result = subprocess.run(command, capture_output=True, timeout=30, check=False)
        output = result.stdout + result.stderr
        state = "collected" if result.returncode == 0 else "command-failed"
        reason = None if result.returncode == 0 else f"exitCode={result.returncode}"
    except (OSError, subprocess.TimeoutExpired) as error:
        output = str(error).encode("utf-8", errors="replace")
        state = "command-failed"
        reason = str(error)
    destination.write_bytes(output)
    os.chmod(destination, 0o600)
    entry: dict[str, object] = {
        "command": command,
        "archivePath": str(destination.relative_to(destination.parents[1])),
        "state": state,
        "sizeBytes": len(output),
    }
    if reason is not None:
        entry["reason"] = reason
    files.append(entry)


def write_operation(
    path: Path,
    operation_id: str,
    state: str,
    started_at: str,
    artifact: dict[str, object] | None,
    failure: dict[str, str] | None,
) -> None:
    write_json(path, {
        "schemaVersion": 1,
        "operationId": operation_id,
        "kind": "support-export",
        "state": state,
        "startedAt": started_at,
        "updatedAt": now(),
        "release": None,
        "artifact": artifact,
        "failure": failure,
    }, 0o600)


def write_json(path: Path, document: dict[str, object], mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(document, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


if __name__ == "__main__":
    raise SystemExit(main())

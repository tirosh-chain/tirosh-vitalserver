#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Provision a publisher-supplied SHA-256 as the Linux update trust owner."
    )
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--expected-sha256", required=True)
    parser.add_argument(
        "--config", type=Path, default=Path("/etc/vitalserver/platform-agent.json")
    )
    parser.add_argument(
        "--catalog",
        type=Path,
        default=Path("/etc/vitalserver/trusted-bundle-digests.json"),
    )
    parser.add_argument(
        "--inbox-directory",
        type=Path,
        default=Path("/var/lib/vitalserver/inbox"),
    )
    parser.add_argument("--service", default="vitalserver-platform-agent.service")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if os.geteuid() != 0:
        raise SystemExit("VitalServer update trust provisioning requires root.")
    expected = args.expected_sha256
    if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
        raise SystemExit("Expected SHA-256 must be exactly 64 lowercase hexadecimal characters.")
    require_regular_owner(args.bundle, "update bundle", require_root=False)
    require_regular_owner(args.config, "Platform Agent config", require_root=True)
    require_hardened_directory(args.catalog.parent)

    config = load_object(args.config, "Platform Agent config")
    delivery = config.get("delivery")
    if (
        config.get("schemaVersion") != 1
        or not isinstance(delivery, dict)
        or delivery.get("schedulerKind") != "systemd-transient"
    ):
        raise SystemExit(f"Linux Platform Agent delivery owner is invalid path={args.config}")
    apply_policy = delivery.get("applyPolicy")
    if apply_policy not in ("verify-only", "sha256-allowlist"):
        raise SystemExit(f"Linux Platform Agent apply policy is invalid policy={apply_policy!r}")

    original_config = args.config.read_bytes()
    catalog_existed = args.catalog.exists()
    original_catalog = args.catalog.read_bytes() if catalog_existed else None
    if catalog_existed:
        require_regular_owner(args.catalog, "trusted digest catalog", require_root=True)

    catalog: dict[str, Any] = {"schemaVersion": 1, "sha256": [expected]}
    delivery["applyPolicy"] = "sha256-allowlist"
    delivery["trustedBundleDigests"] = str(args.catalog)
    staged_bundle = args.inbox_directory / f"trusted-{expected}.bundle"
    staged_bundle_created = False
    try:
        require_or_create_hardened_directory(args.inbox_directory)
        staged_bundle, staged_bundle_created = stage_trusted_bundle(
            args.bundle, args.inbox_directory, expected
        )
        write_json_owner(args.catalog, catalog)
        write_json_owner(args.config, config)
        run(["systemctl", "restart", args.service])
        run(["systemctl", "is-active", "--quiet", args.service])
    except Exception as error:
        restore_owner(args.config, original_config)
        if original_catalog is None:
            args.catalog.unlink(missing_ok=True)
        else:
            restore_owner(args.catalog, original_catalog)
        if staged_bundle_created:
            staged_bundle.unlink(missing_ok=True)
        restoration_error: Exception | None = None
        try:
            run(["systemctl", "restart", args.service])
        except Exception as restore_error:
            restoration_error = restore_error
        suffix = "" if restoration_error is None else f"; previous service restart failed: {restoration_error}"
        raise SystemExit(f"Linux update trust provisioning failed and owners were restored: {error}{suffix}")

    print(
        "VitalServer Linux update trust provisioned "
        f"sha256={expected} catalog={args.catalog} bundle={staged_bundle}"
    )
    return 0


def require_regular_owner(path: Path, label: str, *, require_root: bool) -> None:
    try:
        metadata = path.stat()
    except OSError as error:
        raise SystemExit(f"{label} is unavailable path={path}: {error}") from error
    if not stat.S_ISREG(metadata.st_mode):
        raise SystemExit(f"{label} is not a regular file path={path}")
    if require_root and (metadata.st_uid != 0 or metadata.st_mode & 0o022):
        raise SystemExit(f"{label} must be root-owned and not group/world writable path={path}")


def require_hardened_directory(path: Path) -> None:
    try:
        metadata = path.stat()
    except OSError as error:
        raise SystemExit(f"trusted digest catalog directory is unavailable path={path}: {error}") from error
    if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != 0 or metadata.st_mode & 0o022:
        raise SystemExit(
            f"trusted digest catalog directory must be root-owned and not group/world writable path={path}"
        )


def require_or_create_hardened_directory(path: Path) -> None:
    if not path.exists():
        require_hardened_directory(path.parent)
        path.mkdir(mode=0o700)
    require_hardened_directory(path)


def stage_trusted_bundle(source: Path, inbox: Path, expected: str) -> tuple[Path, bool]:
    destination = inbox / f"trusted-{expected}.bundle"
    if destination.exists():
        require_regular_owner(destination, "trusted staged bundle", require_root=True)
        actual = sha256(destination)
        if actual != expected:
            raise SystemExit(
                f"trusted staged bundle digest differs path={destination} expected={expected} actual={actual}"
            )
        return destination, False

    descriptor, temporary = tempfile.mkstemp(
        dir=inbox, prefix=f".{destination.name}.", suffix=".tmp"
    )
    digest = hashlib.sha256()
    try:
        with source.open("rb") as input_stream, os.fdopen(descriptor, "wb") as output_stream:
            for chunk in iter(lambda: input_stream.read(1024 * 1024), b""):
                digest.update(chunk)
                output_stream.write(chunk)
            output_stream.flush()
            os.fsync(output_stream.fileno())
        actual = digest.hexdigest()
        if actual != expected:
            raise SystemExit(
                "Linux update bundle differs from administrator-provided digest "
                f"expected={expected} actual={actual}"
            )
        os.chmod(temporary, 0o600)
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return destination, True


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_object(path: Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"{label} is invalid path={path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"{label} must be a JSON object path={path}")
    return value


def write_json_owner(path: Path, document: dict[str, Any]) -> None:
    data = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")
    write_owner(path, data)


def restore_owner(path: Path, data: bytes) -> None:
    write_owner(path, data)


def write_owner(path: Path, data: bytes) -> None:
    descriptor, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def run(command: list[str]) -> None:
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        reason = result.stderr.strip() or result.stdout.strip() or "no command output"
        raise RuntimeError(
            f"command failed exitCode={result.returncode} command={command[0]} reason={reason}"
        )


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Install the Guest Tools runtime from its verified air-gap wheelhouse."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


class GuestToolsInstallError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Install verified Guest Tools into an isolated runtime venv."
    )
    parser.add_argument("--wheel-dir", type=Path, required=True)
    parser.add_argument("--guest-tools-home", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        proof = install_guest_tools_runtime(
            wheel_dir=args.wheel_dir,
            guest_tools_home=args.guest_tools_home,
        )
    except GuestToolsInstallError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(json.dumps(proof, sort_keys=True))
    return 0


def install_guest_tools_runtime(
    *,
    wheel_dir: Path,
    guest_tools_home: Path,
) -> dict[str, object]:
    manifest = read_manifest(wheel_dir)
    target = guest_runtime_target()
    requirements, guest_wheel = validate_wheelhouse(
        wheel_dir,
        manifest,
        target=target,
    )
    next_venv = guest_tools_home / "venv.next"
    current_venv = guest_tools_home / "venv"
    previous_venv = guest_tools_home / "venv.previous"
    guest_tools_home.mkdir(parents=True, exist_ok=True)
    remove_directory(next_venv, label="pending Guest Tools venv")
    try:
        subprocess.run(
            [sys.executable, "-m", "venv", "--clear", str(next_venv)],
            check=True,
        )
        pip = next_venv / "bin" / "pip"
        python = next_venv / "bin" / "python"
        subprocess.run(
            [
                str(pip),
                "install",
                "--no-index",
                "--only-binary=:all:",
                "--require-hashes",
                "--find-links",
                str(guest_wheel.parent),
                "--find-links",
                str(requirements.parent),
                "-r",
                str(requirements),
            ],
            check=True,
        )
        subprocess.run([str(python), "-m", "pip", "check"], check=True)
        versions = installed_dependency_versions(python)
    except subprocess.CalledProcessError as error:
        remove_directory(next_venv, label="failed Guest Tools venv")
        raise GuestToolsInstallError(
            "Guest Tools offline dependency installation failed: "
            f"exitCode={error.returncode}"
        ) from error

    publish_venv(
        next_venv=next_venv,
        current_venv=current_venv,
        previous_venv=previous_venv,
    )
    proof = {
        "schemaVersion": 1,
        "status": "passed",
        "target": target,
        "guestWheelSHA256": file_sha256(guest_wheel),
        "requirementsSHA256": file_sha256(requirements),
        "dependencies": versions,
    }
    write_json_atomic(guest_tools_home / "install-proof.json", proof)
    return proof


def read_manifest(wheel_dir: Path) -> dict[str, Any]:
    path = wheel_dir / "manifest.json"
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise GuestToolsInstallError(
            f"Guest Tools wheelhouse manifest is unavailable or invalid: {path}"
        ) from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        raise GuestToolsInstallError(
            f"Guest Tools wheelhouse manifest contract is invalid: {path}"
        )
    python = value.get("guestPython")
    if not isinstance(python, dict) or python.get("major") != 3 or python.get(
        "minor"
    ) != 12:
        raise GuestToolsInstallError(
            f"Guest Tools wheelhouse Python contract is invalid: {path}"
        )
    if sys.version_info[:2] != (3, 12):
        raise GuestToolsInstallError(
            "Guest Tools wheelhouse requires CPython 3.12: "
            f"actual={sys.version_info.major}.{sys.version_info.minor}"
        )
    return value


def guest_runtime_target() -> str:
    machine = platform.machine().strip().lower()
    if machine in {"aarch64", "arm64"}:
        return "linux-aarch64"
    if machine in {"x86_64", "amd64"}:
        return "linux-amd64"
    raise GuestToolsInstallError(
        f"unsupported Guest Tools wheelhouse architecture: {machine or '<empty>'}"
    )


def validate_wheelhouse(
    wheel_dir: Path,
    manifest: dict[str, Any],
    *,
    target: str,
) -> tuple[Path, Path]:
    guest_tools = required_object(manifest, "guestTools", label="manifest")
    targets = required_object(manifest, "targets", label="manifest")
    target_document = required_object(targets, target, label="manifest targets")
    requirements = required_relative_file(
        wheel_dir,
        required_string(target_document, "requirementsPath", label=target),
        label="Guest Tools requirements",
    )
    require_hash(
        requirements,
        required_string(target_document, "requirementsSHA256", label=target),
        label="Guest Tools requirements",
    )
    guest_wheel = required_relative_file(
        wheel_dir,
        required_string(guest_tools, "path", label="guestTools"),
        label="Guest Tools wheel",
    )
    require_hash(
        guest_wheel,
        required_string(guest_tools, "sha256", label="guestTools"),
        label="Guest Tools wheel",
    )
    wheel_entries = target_document.get("wheels")
    if not isinstance(wheel_entries, list) or not wheel_entries:
        raise GuestToolsInstallError(
            f"Guest Tools target wheel manifest is invalid: target={target}"
        )
    for entry in wheel_entries:
        if not isinstance(entry, dict):
            raise GuestToolsInstallError(
                f"Guest Tools target wheel manifest is invalid: target={target}"
            )
        wheel = required_relative_file(
            requirements.parent,
            required_string(entry, "path", label="wheel"),
            label="Guest Tools dependency wheel",
        )
        if wheel.suffix != ".whl":
            raise GuestToolsInstallError(
                f"Guest Tools dependency is not a wheel: {wheel}"
            )
        require_hash(
            wheel,
            required_string(entry, "sha256", label="wheel"),
            label="Guest Tools dependency wheel",
        )
    return requirements, guest_wheel


def required_relative_file(root: Path, relative: str, *, label: str) -> Path:
    path = root / relative
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError as error:
        raise GuestToolsInstallError(
            f"{label} path escapes its wheelhouse root: {relative}"
        ) from error
    if not path.is_file():
        raise GuestToolsInstallError(f"{label} is missing: {path}")
    return path


def required_object(
    document: dict[str, Any],
    key: str,
    *,
    label: str,
) -> dict[str, Any]:
    value = document.get(key)
    if not isinstance(value, dict):
        raise GuestToolsInstallError(f"Guest Tools {label} field is invalid: {key}")
    return value


def required_string(document: dict[str, Any], key: str, *, label: str) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not value:
        raise GuestToolsInstallError(f"Guest Tools {label} field is invalid: {key}")
    return value


def require_hash(path: Path, expected: str, *, label: str) -> None:
    actual = file_sha256(path)
    if actual != expected:
        raise GuestToolsInstallError(
            f"{label} SHA-256 mismatch: path={path} expected={expected} actual={actual}"
        )


def installed_dependency_versions(python: Path) -> dict[str, str]:
    probe = (
        "import alembic, sqlalchemy; "
        "print(alembic.__version__); print(sqlalchemy.__version__)"
    )
    try:
        completed = subprocess.run(
            [str(python), "-c", probe],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as error:
        raise GuestToolsInstallError(
            "Guest Tools dependency import proof failed: "
            f"exitCode={error.returncode}"
        ) from error
    values = completed.stdout.splitlines()
    if len(values) != 2 or not all(values):
        raise GuestToolsInstallError("Guest Tools dependency version proof is invalid")
    return {"alembic": values[0], "sqlalchemy": values[1]}


def publish_venv(
    *,
    next_venv: Path,
    current_venv: Path,
    previous_venv: Path,
) -> None:
    remove_directory(previous_venv, label="previous Guest Tools venv")
    moved_current = False
    try:
        if current_venv.exists():
            os.replace(current_venv, previous_venv)
            moved_current = True
        os.replace(next_venv, current_venv)
    except OSError as error:
        if moved_current and not current_venv.exists() and previous_venv.exists():
            os.replace(previous_venv, current_venv)
        raise GuestToolsInstallError(
            f"Guest Tools venv publish failed: {error}"
        ) from error
    remove_directory(previous_venv, label="previous Guest Tools venv")


def remove_directory(path: Path, *, label: str) -> None:
    if not path.exists():
        return
    if not path.is_dir() or path.is_symlink():
        raise GuestToolsInstallError(f"{label} is not a removable directory: {path}")
    shutil.rmtree(path)


def write_json_atomic(path: Path, document: dict[str, object]) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())

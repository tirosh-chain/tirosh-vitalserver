#!/usr/bin/env python3
"""Install the Guest Tools runtime from its verified air-gap wheelhouse."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
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
    guest_tools_home = guest_tools_home.resolve()
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
            cwd=requirements.parent,
        )
        subprocess.run([str(python), "-m", "pip", "check"], check=True)
        versions = installed_dependency_versions(python)
        rewrite_entrypoint_shebangs(
            next_venv=next_venv,
            current_venv=current_venv,
        )
    except (subprocess.CalledProcessError, GuestToolsInstallError) as error:
        remove_directory(next_venv, label="failed Guest Tools venv")
        if isinstance(error, subprocess.CalledProcessError):
            message = (
                "Guest Tools offline dependency installation failed: "
                f"exitCode={error.returncode}"
            )
        else:
            message = (
                "Guest Tools offline dependency installation failed: "
                f"reason={error}"
            )
        raise GuestToolsInstallError(message) from error

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


def rewrite_entrypoint_shebangs(
    *,
    next_venv: Path,
    current_venv: Path,
) -> None:
    """Make generated console scripts valid after the venv directory rename."""

    source_shebang_prefix = f"#!{next_venv}/bin/".encode()
    target_shebang_prefix = f"#!{current_venv}/bin/".encode()
    bin_dir = next_venv / "bin"
    if not bin_dir.is_dir() or bin_dir.is_symlink():
        raise GuestToolsInstallError(
            f"Guest Tools next venv bin directory is invalid: {bin_dir}"
        )
    try:
        rewritten = 0
        for entrypoint in bin_dir.iterdir():
            if entrypoint.is_symlink() or not entrypoint.is_file():
                continue
            content = entrypoint.read_bytes()
            if not content.startswith(source_shebang_prefix):
                continue
            entrypoint.write_bytes(
                target_shebang_prefix + content[len(source_shebang_prefix) :]
            )
            rewritten += 1
    except OSError as error:
        raise GuestToolsInstallError(
            "Guest Tools entrypoint relocation failed: "
            f"next={next_venv} current={current_venv} error={error}"
        ) from error
    if rewritten == 0:
        raise GuestToolsInstallError(
            "Guest Tools next venv has no relocatable entrypoints: "
            f"{bin_dir}"
        )


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
    if (
        not isinstance(python, dict)
        or python.get("major") != 3
        or python.get("minor") != 12
    ):
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
    if guest_wheel.suffix != ".whl":
        raise GuestToolsInstallError(
            f"Guest Tools artifact is not a wheel: {guest_wheel}"
        )
    wheel_entries = target_document.get("wheels")
    if not isinstance(wheel_entries, list) or not wheel_entries:
        raise GuestToolsInstallError(
            f"Guest Tools target wheel manifest is invalid: target={target}"
        )
    wheel_hashes = {file_sha256(guest_wheel)}
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
        wheel_hashes.add(file_sha256(wheel))
    require_requirements_hash_closure(requirements, wheel_hashes)
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


def require_requirements_hash_closure(
    requirements: Path,
    expected_hashes: set[str],
) -> None:
    referenced_hashes: set[str] = set()
    for line in requirements_logical_lines(requirements):
        hash_tokens = re.findall(r"(?:^|\s)--hash=([^\s]+)", line)
        hashes = [
            token.removeprefix("sha256:")
            for token in hash_tokens
            if re.fullmatch(r"sha256:[0-9a-f]{64}", token) is not None
        ]
        invalid_hashes = [
            token
            for token in hash_tokens
            if re.fullmatch(r"sha256:[0-9a-f]{64}", token) is None
        ]
        if invalid_hashes:
            raise GuestToolsInstallError(
                "Guest Tools requirements has an invalid hash: "
                f"path={requirements} values={invalid_hashes}"
            )
        if not hashes:
            raise GuestToolsInstallError(
                "Guest Tools requirements entry is not hash-pinned: "
                f"path={requirements} entry={line!r}"
            )
        referenced_hashes.update(hashes)
    if referenced_hashes != expected_hashes:
        missing = sorted(expected_hashes - referenced_hashes)
        unexpected = sorted(referenced_hashes - expected_hashes)
        raise GuestToolsInstallError(
            "Guest Tools requirements do not pin every manifest wheel: "
            f"path={requirements} missing={missing} unexpected={unexpected}"
        )


def requirements_logical_lines(requirements: Path) -> list[str]:
    try:
        physical_lines = requirements.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as error:
        raise GuestToolsInstallError(
            "Guest Tools requirements cannot be read: "
            f"path={requirements} error={error}"
        ) from error
    joined_lines: list[str] = []
    pending: str | None = None
    for physical_line in physical_lines:
        # Match pip preprocessing order: it joins literal trailing-backslash
        # continuations before it removes whitespace-introduced comments.
        comment_line = re.match(r"(^|\s+)#.*$", physical_line) is not None
        if physical_line.endswith("\\") and not comment_line:
            if pending is None:
                pending = ""
            pending += physical_line.strip("\\")
            continue
        if comment_line:
            # Keep a comment following a continuation a comment after joining.
            physical_line = " " + physical_line
        if pending is None:
            joined_lines.append(physical_line)
        else:
            joined_lines.append(pending + physical_line)
            pending = None
    if pending is not None:
        raise GuestToolsInstallError(
            "Guest Tools requirements has an unterminated line continuation: "
            f"path={requirements}"
        )
    logical_lines: list[str] = []
    for joined_line in joined_lines:
        line = re.sub(r"(^|\s+)#.*$", "", joined_line).strip()
        if not line:
            continue
        if line.endswith("\\"):
            raise GuestToolsInstallError(
                "Guest Tools requirements has a malformed line continuation: "
                f"path={requirements} entry={line!r}"
            )
        logical_lines.append(line)
    if not logical_lines:
        raise GuestToolsInstallError(
            f"Guest Tools requirements has no dependency entries: path={requirements}"
        )
    return logical_lines


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
            f"Guest Tools dependency import proof failed: exitCode={error.returncode}"
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

#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HYPERV_GUEST = ROOT / "apps/vitalserver-platform-agent/packaging/windows/hyperv-guest"
FORBIDDEN_DEPLOY_NAMES = {
    "tirosh-vitalserver-command-poller",
    "tirosh-vitalserver-command-poller.service",
    "tirosh-vitalserver-testkit.service",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Stage the portable Runtime deploy payload "
            "into a mounted amd64 system disk."
        )
    )
    parser.add_argument("--system-root", type=Path, required=True)
    parser.add_argument("--system-raw", type=Path, required=True)
    parser.add_argument("--runtime-data-raw", type=Path, required=True)
    parser.add_argument("--seed-iso", type=Path, required=True)
    parser.add_argument("--deploy-directory", type=Path, required=True)
    parser.add_argument("--rootfs-proof", type=Path, required=True)
    parser.add_argument("--output-proof", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    system_root = args.system_root.resolve()
    if system_root == Path("/") or not system_root.is_dir():
        raise SystemExit(f"mounted system root is unsafe or unavailable: {system_root}")
    proof = _load_json(args.rootfs_proof, "rootfs proof")
    _require_amd64_proof(proof, args.rootfs_proof)
    _validate_deploy(args.deploy_directory)
    _require_file(args.system_raw, "Hyper-V system raw disk")
    _require_file(args.runtime_data_raw, "Hyper-V Runtime data raw disk")
    _require_file(args.seed_iso, "Hyper-V NoCloud seed ISO")

    target = system_root / "opt/vitalserver"
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".vitalserver-hyperv-payload-", dir=target.parent
    ) as temporary:
        staged = Path(temporary) / "vitalserver"
        staged.mkdir()
        shutil.copytree(args.deploy_directory, staged / "deploy")
        shutil.copytree(HYPERV_GUEST, staged / "hyperv-guest")
        (staged / "run").mkdir()
        if target.exists():
            raise SystemExit(
                f"mounted system root already contains a VitalServer payload: {target}"
            )
        os.replace(staged, target)

    os.sync()

    combined = dict(proof)
    combined["portableDeploy"] = {
        "status": "passed",
        "path": "/opt/vitalserver/deploy",
        "treeSHA256": _tree_sha256(args.deploy_directory),
        "hyperVGuestTreeSHA256": _tree_sha256(HYPERV_GUEST),
        "mountMode": "native",
        "hyperVInputs": {
            "systemRaw": _file_identity(args.system_raw),
            "runtimeDataRaw": _file_identity(args.runtime_data_raw),
            "seedISO": _file_identity(args.seed_iso),
        },
    }
    args.output_proof.parent.mkdir(parents=True, exist_ok=True)
    args.output_proof.write_text(
        json.dumps(combined, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"Hyper-V guest payload staged systemRoot={system_root}")
    return 0


def _load_json(path: Path, label: str) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"{label} decode failed path={path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"{label} must be a JSON object: {path}")
    return value


def _require_amd64_proof(proof: dict[str, object], path: Path) -> None:
    docker_images = proof.get("dockerImages")
    cleanup = proof.get("cleanup")
    if not isinstance(proof.get("runId"), str) or not proof["runId"]:
        raise SystemExit(f"rootfs proof runId is missing: {path}")
    if not isinstance(docker_images, dict):
        raise SystemExit(f"rootfs proof dockerImages is missing: {path}")
    if (
        docker_images.get("platform") != "linux/amd64"
        or docker_images.get("guestArchitecture") not in {"amd64", "x86_64"}
        or docker_images.get("status") != "passed"
    ):
        raise SystemExit(f"rootfs proof is not a passed linux/amd64 compile: {path}")
    if not isinstance(cleanup, dict) or cleanup.get("status") != "passed":
        raise SystemExit(f"rootfs proof cleanup stage did not pass: {path}")


def _validate_deploy(path: Path) -> None:
    if not path.is_dir() or not (path / "compose.yaml").is_file():
        raise SystemExit(
            f"portable deploy directory or compose.yaml is missing: {path}"
        )
    for item in path.rglob("*"):
        if item.is_symlink():
            raise SystemExit(f"portable deploy contains unsupported symlink: {item}")
        if item.name in FORBIDDEN_DEPLOY_NAMES:
            raise SystemExit(f"portable deploy contains retired v1 artifact: {item}")
    for required_config in (
        "runtime-config.json",
        "runtime-settings.json",
        "runtime.env",
    ):
        config_path = path / required_config
        if not config_path.is_file() or config_path.stat().st_size == 0:
            raise SystemExit(
                "portable deploy initial Runtime configuration is missing: "
                f"{config_path}"
            )
    relay_config = path / "redis-relay-config/redis-relay.toml"
    if not relay_config.is_file() or relay_config.stat().st_size == 0:
        raise SystemExit(
            "portable deploy initial Redis Relay configuration is missing: "
            f"{relay_config}"
        )
    _require_guest_tools_runtime_payload(path)
    compose = (path / "compose.yaml").read_text(encoding="utf-8")
    if "/v1/" in compose or "/runtime/stack/status" in compose:
        raise SystemExit("portable deploy Compose contains a legacy Runtime API route")


def _require_guest_tools_runtime_payload(deploy: Path) -> None:
    installer = deploy / "install-guest-tools-runtime.py"
    wheelhouse = deploy / "python-wheels"
    manifest = wheelhouse / "manifest.json"
    requirements = wheelhouse / "linux-amd64/requirements.txt"
    control_service = deploy / "systemd/tirosh-vitalserver-guest-control-api.service"
    for path, label in (
        (installer, "Guest Tools runtime installer"),
        (manifest, "Guest Tools wheelhouse manifest"),
        (requirements, "Guest Tools linux/amd64 requirements"),
        (control_service, "Guest Control service lifecycle unit"),
    ):
        if not path.is_file() or path.stat().st_size == 0:
            raise SystemExit(f"portable deploy {label} is missing: {path}")
    for directory, label in (
        (wheelhouse / "guest-tools", "Guest Tools wheel directory"),
        (wheelhouse / "linux-amd64", "Guest Tools linux/amd64 wheel directory"),
    ):
        if not directory.is_dir() or not any(directory.glob("*.whl")):
            raise SystemExit(f"portable deploy {label} is missing: {directory}")
    try:
        document = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(
            f"portable deploy Guest Tools wheelhouse manifest is invalid: {manifest}"
        ) from error
    if not isinstance(document, dict) or document.get("schemaVersion") != 1:
        raise SystemExit(
            "portable deploy Guest Tools wheelhouse manifest contract is invalid: "
            f"{manifest}"
        )
    guest_tools = document.get("guestTools")
    targets = document.get("targets")
    if (
        document.get("guestPython") != {"major": 3, "minor": 12}
        or not isinstance(guest_tools, dict)
        or not isinstance(targets, dict)
    ):
        raise SystemExit(
            "portable deploy Guest Tools wheelhouse manifest contract is invalid: "
            f"{manifest}"
        )
    amd64 = targets.get("linux-amd64")
    if not isinstance(amd64, dict):
        raise SystemExit(
            "portable deploy Guest Tools wheelhouse has no linux/amd64 target: "
            f"{manifest}"
        )
    guest_tools_sha256 = guest_tools.get("sha256")
    guest_wheel = _require_manifested_wheelhouse_file(
        wheelhouse,
        guest_tools.get("path"),
        guest_tools_sha256,
        label="Guest Tools wheel",
    )
    if guest_wheel.suffix != ".whl":
        raise SystemExit(
            f"portable deploy Guest Tools artifact is not a wheel: {guest_wheel}"
        )
    _require_cpython312_linux_amd64_wheel(
        guest_wheel,
        "portable deploy Guest Tools wheel",
    )
    requirements_path = _require_manifested_wheelhouse_file(
        wheelhouse,
        amd64.get("requirementsPath"),
        amd64.get("requirementsSHA256"),
        label="Guest Tools linux/amd64 requirements",
    )
    wheels = amd64.get("wheels")
    if not isinstance(wheels, list) or not wheels:
        raise SystemExit(
            "portable deploy Guest Tools linux/amd64 wheel manifest is invalid: "
            f"{manifest}"
        )
    if not isinstance(guest_tools_sha256, str):
        raise SystemExit(
            "portable deploy Guest Tools wheel manifest SHA-256 is invalid"
        )
    wheel_hashes = {guest_tools_sha256}
    for wheel in wheels:
        if not isinstance(wheel, dict):
            raise SystemExit(
                "portable deploy Guest Tools linux/amd64 wheel manifest is invalid: "
                f"{manifest}"
            )
        wheel_sha256 = wheel.get("sha256")
        dependency = _require_manifested_wheelhouse_file(
            requirements_path.parent,
            wheel.get("path"),
            wheel_sha256,
            label="Guest Tools linux/amd64 dependency wheel",
        )
        if dependency.suffix != ".whl":
            raise SystemExit(
                f"portable deploy Guest Tools dependency is not a wheel: {dependency}"
            )
        _require_cpython312_linux_amd64_wheel(
            dependency,
            "portable deploy Guest Tools linux/amd64 dependency wheel",
        )
        if not isinstance(wheel_sha256, str):
            raise SystemExit(
                "portable deploy Guest Tools linux/amd64 wheel manifest "
                "SHA-256 is invalid"
            )
        wheel_hashes.add(wheel_sha256)
    _require_requirements_hash_closure(requirements_path, wheel_hashes)
    control_service_text = control_service.read_text(encoding="utf-8")
    required_lifecycle = (
        "RequiresMountsFor=/mnt/runtime",
        "ExecStartPre=/opt/tirosh/guest-tools/venv/bin/"
        "tirosh-guest-tools-migrate-control-store",
    )
    if any(token not in control_service_text for token in required_lifecycle):
        raise SystemExit(
            "portable deploy Guest Control service lifecycle is invalid: "
            f"{control_service}"
        )
    if "--control-state-dir" in control_service_text:
        raise SystemExit(
            "portable deploy Guest Control service must resolve its control store "
            f"from Guest Tools settings: {control_service}"
        )


def _require_manifested_wheelhouse_file(
    wheelhouse: Path,
    relative: object,
    expected_sha256: object,
    *,
    label: str,
) -> Path:
    if not isinstance(relative, str) or not relative:
        raise SystemExit(f"portable deploy {label} manifest path is invalid")
    if (
        not isinstance(expected_sha256, str)
        or len(expected_sha256) != 64
        or any(character not in "0123456789abcdef" for character in expected_sha256)
    ):
        raise SystemExit(f"portable deploy {label} manifest SHA-256 is invalid")
    path = wheelhouse / relative
    try:
        path.resolve().relative_to(wheelhouse.resolve())
    except ValueError as error:
        raise SystemExit(
            f"portable deploy {label} manifest path escapes wheelhouse: {relative}"
        ) from error
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f"portable deploy {label} manifest file is missing: {path}")
    actual_sha256 = _file_identity(path)["sha256"]
    if actual_sha256 != expected_sha256:
        raise SystemExit(
            f"portable deploy {label} SHA-256 mismatch: path={path} "
            f"expected={expected_sha256} actual={actual_sha256}"
        )
    return path


def _require_cpython312_linux_amd64_wheel(path: Path, label: str) -> None:
    try:
        prefix, python_tags, abi_tags, platform_tags = path.stem.rsplit("-", 3)
    except ValueError as error:
        raise SystemExit(f"{label} filename is invalid: {path}") from error
    tag_groups = (python_tags, abi_tags, platform_tags)
    if not prefix or any(not tag or ".." in tag for tag in tag_groups):
        raise SystemExit(f"{label} filename is invalid: {path}")

    compatible = any(
        _is_cpython312_linux_amd64_wheel_tag(python_tag, abi_tag, platform_tag)
        for python_tag in python_tags.split(".")
        for abi_tag in abi_tags.split(".")
        for platform_tag in platform_tags.split(".")
    )
    if not compatible:
        raise SystemExit(
            f"{label} is not compatible with CPython 3.12 linux/amd64: {path}"
        )


def _is_cpython312_linux_amd64_wheel_tag(
    python_tag: str,
    abi_tag: str,
    platform_tag: str,
) -> bool:
    if platform_tag == "any":
        return abi_tag == "none" and _is_generic_python312_tag(python_tag)
    if not _is_linux_amd64_platform_tag(platform_tag):
        return False
    if abi_tag == "cp312":
        return python_tag == "cp312"
    if abi_tag == "abi3":
        return _is_cpython_abi3_tag(python_tag)
    if abi_tag == "none":
        return python_tag == "cp312" or _is_generic_python312_tag(python_tag)
    return False


def _is_generic_python312_tag(tag: str) -> bool:
    return tag in {"py3", "py312"}


def _is_cpython_abi3_tag(tag: str) -> bool:
    if not tag.startswith("cp3"):
        return False
    minor = tag.removeprefix("cp3")
    return minor.isdigit() and 2 <= int(minor) <= 12


def _is_linux_amd64_platform_tag(tag: str) -> bool:
    return tag in {
        "manylinux1_x86_64",
        "manylinux2010_x86_64",
        "manylinux2014_x86_64",
        "manylinux_2_5_x86_64",
        "manylinux_2_12_x86_64",
        "manylinux_2_17_x86_64",
    }


def _require_requirements_hash_closure(
    requirements: Path,
    expected_hashes: set[str],
) -> None:
    logical_lines = _requirements_logical_lines(requirements)
    referenced_hashes: set[str] = set()
    for line in logical_lines:
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
            raise SystemExit(
                "portable deploy Guest Tools requirements has an invalid hash: "
                f"path={requirements} values={invalid_hashes}"
            )
        if not hashes:
            raise SystemExit(
                "portable deploy Guest Tools requirements entry is not hash-pinned: "
                f"path={requirements} entry={line!r}"
            )
        referenced_hashes.update(hashes)
    if referenced_hashes != expected_hashes:
        missing = sorted(expected_hashes - referenced_hashes)
        unexpected = sorted(referenced_hashes - expected_hashes)
        raise SystemExit(
            "portable deploy Guest Tools requirements do not pin every manifest "
            f"wheel: path={requirements} missing={missing} unexpected={unexpected}"
        )


def _requirements_logical_lines(requirements: Path) -> list[str]:
    try:
        physical_lines = requirements.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as error:
        raise SystemExit(
            "portable deploy Guest Tools requirements cannot be read: "
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
        raise SystemExit(
            "portable deploy Guest Tools requirements has an unterminated line "
            f"continuation: path={requirements}"
        )
    logical_lines: list[str] = []
    for joined_line in joined_lines:
        line = re.sub(r"(^|\s+)#.*$", "", joined_line).strip()
        if not line:
            continue
        if line.endswith("\\"):
            raise SystemExit(
                "portable deploy Guest Tools requirements has a malformed line "
                f"continuation: path={requirements} entry={line!r}"
            )
        logical_lines.append(line)
    if not logical_lines:
        raise SystemExit(
            "portable deploy Guest Tools requirements has no dependency entries: "
            f"path={requirements}"
        )
    return logical_lines


def _require_file(path: Path, label: str) -> None:
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"{label} is missing or not a regular file: {path}")


def _file_identity(path: Path) -> dict[str, object]:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return {"sha256": digest.hexdigest(), "bytes": path.stat().st_size}


def _tree_sha256(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(hashlib.sha256(path.read_bytes()).digest())
    return digest.hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())

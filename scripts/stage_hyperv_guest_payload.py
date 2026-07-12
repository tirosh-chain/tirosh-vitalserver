#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
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
    if not isinstance(guest_tools, dict) or not isinstance(targets, dict):
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
    _require_manifested_wheelhouse_file(
        wheelhouse,
        guest_tools.get("path"),
        label="Guest Tools wheel",
    )
    _require_manifested_wheelhouse_file(
        wheelhouse,
        amd64.get("requirementsPath"),
        label="Guest Tools linux/amd64 requirements",
    )
    control_service_text = control_service.read_text(encoding="utf-8")
    required_lifecycle = (
        "RequiresMountsFor=/mnt/runtime",
        "ExecStartPre=/opt/tirosh/guest-tools/venv/bin/"
        "tirosh-guest-tools-migrate-control-store --control-state-dir "
        "/mnt/runtime/control",
    )
    if any(token not in control_service_text for token in required_lifecycle):
        raise SystemExit(
            "portable deploy Guest Control service lifecycle is invalid: "
            f"{control_service}"
        )


def _require_manifested_wheelhouse_file(
    wheelhouse: Path,
    relative: object,
    *,
    label: str,
) -> None:
    if not isinstance(relative, str) or not relative:
        raise SystemExit(f"portable deploy {label} manifest path is invalid")
    path = wheelhouse / relative
    try:
        path.resolve().relative_to(wheelhouse.resolve())
    except ValueError as error:
        raise SystemExit(
            f"portable deploy {label} manifest path escapes wheelhouse: {relative}"
        ) from error
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f"portable deploy {label} manifest file is missing: {path}")


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

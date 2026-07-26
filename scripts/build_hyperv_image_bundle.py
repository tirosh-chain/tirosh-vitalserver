#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
import tempfile
import uuid
from pathlib import Path

EFI_SYSTEM_PARTITION = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compile proved linux/amd64 Runtime VM inputs into Hyper-V artifacts."
        )
    )
    parser.add_argument("--system-raw", type=Path, required=True)
    parser.add_argument("--runtime-data-raw", type=Path, required=True)
    parser.add_argument("--seed-iso", type=Path, required=True)
    parser.add_argument("--rootfs-proof", type=Path, required=True)
    parser.add_argument("--guest-address", default="172.24.0.2")
    parser.add_argument("--qemu-img", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    _require_file(args.system_raw, "system raw disk")
    _require_file(args.runtime_data_raw, "Runtime data raw disk")
    _require_file(args.seed_iso, "NoCloud seed ISO")
    _require_file(args.rootfs_proof, "rootfs proof")
    _require_file(args.qemu_img, "qemu-img executable", allow_symlink=True)

    args.output_directory.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".vitalserver-hyperv-", dir=args.output_directory.parent
    ) as temporary:
        inputs = Path(temporary) / "inputs"
        inputs.mkdir()
        system_raw = _snapshot_input(args.system_raw, inputs / "system.raw")
        runtime_data_raw = _snapshot_input(
            args.runtime_data_raw, inputs / "runtime-data.raw"
        )
        seed_iso = _snapshot_input(args.seed_iso, inputs / "vitalserver-seed.iso")
        rootfs_proof = _snapshot_input(args.rootfs_proof, inputs / "rootfs-proof.json")
        proof = _load_proof(rootfs_proof)
        _validate_amd64_proof(proof, rootfs_proof)
        input_identities = {
            "systemRaw": _file_identity(system_raw),
            "runtimeDataRaw": _file_identity(runtime_data_raw),
            "seedISO": _file_identity(seed_iso),
        }
        _validate_proof_inputs(proof, rootfs_proof, input_identities)
        if EFI_SYSTEM_PARTITION not in _gpt_partition_types(system_raw):
            raise SystemExit(
                f"system raw disk has no EFI System Partition: {system_raw}"
            )
        _validate_runtime_data_disk(runtime_data_raw)

        stage = Path(temporary) / "hyperv-image"
        stage.mkdir()
        system_vhdx = stage / "vitalserver-system.vhdx"
        runtime_data_vhdx = stage / "vitalserver-runtime-data.vhdx"
        _convert_vhdx(args.qemu_img, system_raw, system_vhdx)
        _convert_vhdx(args.qemu_img, runtime_data_raw, runtime_data_vhdx)
        shutil.copy2(seed_iso, stage / "vitalserver-seed.iso")
        shutil.copy2(rootfs_proof, stage / "rootfs-proof.json")

        manifest = {
            "schemaVersion": 1,
            "state": "compiled",
            "runId": proof["runId"],
            "architecture": "amd64",
            "guestAddress": args.guest_address,
            "sourceInputs": {
                **input_identities,
                "rootfsProof": _file_identity(rootfs_proof),
            },
            "systemVHDX": {
                "path": system_vhdx.name,
                "sha256": _sha256(system_vhdx),
                "bytes": system_vhdx.stat().st_size,
            },
            "runtimeDataVHDX": {
                "path": runtime_data_vhdx.name,
                "sha256": _sha256(runtime_data_vhdx),
                "bytes": runtime_data_vhdx.stat().st_size,
            },
            "seedISO": {
                "path": "vitalserver-seed.iso",
                "sha256": _sha256(stage / "vitalserver-seed.iso"),
                "bytes": (stage / "vitalserver-seed.iso").stat().st_size,
            },
            "readError": None,
        }
        (stage / "hyperv-image.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        if args.output_directory.exists():
            raise SystemExit(
                f"Hyper-V output directory already exists: {args.output_directory}"
            )
        os.replace(stage, args.output_directory)
    print(f"Hyper-V image bundle compiled: {args.output_directory}")
    return 0


def _load_proof(path: Path) -> dict[str, object]:
    _require_file(path, "rootfs proof")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise SystemExit(f"rootfs proof decode failed path={path}: {error}") from error
    if not isinstance(value, dict):
        raise SystemExit(f"rootfs proof must be a JSON object: {path}")
    return value


def _validate_amd64_proof(proof: dict[str, object], path: Path) -> None:
    run_id = proof.get("runId")
    docker_images = proof.get("dockerImages")
    if not isinstance(run_id, str) or not run_id:
        raise SystemExit(f"rootfs proof runId is missing: {path}")
    if not isinstance(docker_images, dict):
        raise SystemExit(f"rootfs proof dockerImages is missing: {path}")
    if docker_images.get("platform") != "linux/amd64":
        raise SystemExit(
            "rootfs proof is not linux/amd64 "
            f"path={path} platform={docker_images.get('platform')}"
        )
    if docker_images.get("guestArchitecture") not in {"amd64", "x86_64"}:
        raise SystemExit(
            "rootfs proof guest architecture is not amd64 "
            f"path={path} guestArchitecture={docker_images.get('guestArchitecture')}"
        )
    if docker_images.get("status") != "passed":
        raise SystemExit(
            "rootfs proof Docker image stage did not pass "
            f"path={path} status={docker_images.get('status')}"
        )
    cleanup = proof.get("cleanup")
    if not isinstance(cleanup, dict) or cleanup.get("status") != "passed":
        raise SystemExit(f"rootfs proof cleanup stage did not pass: {path}")
    portable_deploy = proof.get("portableDeploy")
    if (
        not isinstance(portable_deploy, dict)
        or portable_deploy.get("status") != "passed"
        or portable_deploy.get("mountMode") != "native"
        or not isinstance(portable_deploy.get("treeSHA256"), str)
    ):
        raise SystemExit(
            f"rootfs proof portable Hyper-V deploy stage did not pass: {path}"
        )


def _validate_proof_inputs(
    proof: dict[str, object],
    path: Path,
    actual: dict[str, dict[str, object]],
) -> None:
    portable_deploy = proof.get("portableDeploy")
    if not isinstance(portable_deploy, dict):
        raise SystemExit(
            f"rootfs proof portable Hyper-V deploy stage is missing: {path}"
        )
    expected = portable_deploy.get("hyperVInputs")
    if not isinstance(expected, dict):
        raise SystemExit(f"rootfs proof Hyper-V input identities are missing: {path}")
    for name, identity in actual.items():
        declared = expected.get(name)
        if not isinstance(declared, dict):
            raise SystemExit(
                "rootfs proof Hyper-V input identity is missing "
                f"path={path} input={name}"
            )
        declared_sha = declared.get("sha256")
        declared_bytes = declared.get("bytes")
        if not isinstance(declared_sha, str) or len(declared_sha) != 64:
            raise SystemExit(
                "rootfs proof Hyper-V input SHA-256 is invalid "
                f"path={path} input={name}"
            )
        if not isinstance(declared_bytes, int) or declared_bytes < 1:
            raise SystemExit(
                "rootfs proof Hyper-V input byte size is invalid "
                f"path={path} input={name}"
            )
        if declared_sha != identity["sha256"] or declared_bytes != identity["bytes"]:
            raise SystemExit(
                "rootfs proof Hyper-V input identity mismatch "
                f"path={path} input={name} expectedSHA256={declared_sha} "
                f"actualSHA256={identity['sha256']} expectedBytes={declared_bytes} "
                f"actualBytes={identity['bytes']}"
            )


def _gpt_partition_types(path: Path) -> set[uuid.UUID]:
    with path.open("rb") as source:
        source.seek(512)
        header = source.read(92)
        if len(header) < 92 or header[:8] != b"EFI PART":
            raise SystemExit(f"system raw disk has no valid GPT header: {path}")
        entries_lba = struct.unpack_from("<Q", header, 72)[0]
        entry_count = struct.unpack_from("<I", header, 80)[0]
        entry_size = struct.unpack_from("<I", header, 84)[0]
        if (
            entry_count < 1
            or entry_count > 4096
            or entry_size < 128
            or entry_size > 4096
        ):
            raise SystemExit(
                "system raw disk GPT entry geometry is invalid "
                f"path={path} count={entry_count} size={entry_size}"
            )
        source.seek(entries_lba * 512)
        result: set[uuid.UUID] = set()
        for _ in range(entry_count):
            entry = source.read(entry_size)
            if len(entry) != entry_size:
                raise SystemExit(f"system raw disk GPT table is truncated: {path}")
            if entry[:16] != b"\0" * 16:
                result.add(uuid.UUID(bytes_le=entry[:16]))
        return result


def _validate_runtime_data_disk(path: Path) -> None:
    with path.open("rb") as source:
        source.seek(1024)
        superblock = source.read(1024)
    if len(superblock) != 1024:
        raise SystemExit(f"Runtime data raw disk ext4 superblock is truncated: {path}")
    magic = struct.unpack_from("<H", superblock, 0x38)[0]
    if magic != 0xEF53:
        raise SystemExit(f"Runtime data raw disk is not ext4: {path}")
    label = superblock[0x78 : 0x78 + 16].split(b"\0", 1)[0]
    try:
        decoded_label = label.decode("ascii")
    except UnicodeDecodeError as error:
        raise SystemExit(
            f"Runtime data raw disk filesystem label is invalid: {path}"
        ) from error
    if decoded_label != "vital-runtime":
        raise SystemExit(
            "Runtime data raw disk filesystem label is invalid "
            f"path={path} expected=vital-runtime actual={decoded_label!r}"
        )


def _convert_vhdx(qemu_img: Path, source: Path, destination: Path) -> None:
    completed = subprocess.run(
        [
            str(qemu_img),
            "convert",
            "-f",
            "raw",
            "-O",
            "vhdx",
            "-o",
            "subformat=dynamic,block_size=2097152",
            str(source),
            str(destination),
        ],
        text=True,
        capture_output=True,
    )
    if completed.returncode != 0:
        raise SystemExit(
            "qemu-img VHDX conversion failed "
            f"source={source} exitCode={completed.returncode} "
            f"stderr={completed.stderr.strip()}"
        )
    info = subprocess.run(
        [str(qemu_img), "info", "--output=json", str(destination)],
        text=True,
        capture_output=True,
    )
    if info.returncode != 0:
        raise SystemExit(
            "qemu-img VHDX inspection failed "
            f"path={destination} exitCode={info.returncode} "
            f"stderr={info.stderr.strip()}"
        )
    try:
        document = json.loads(info.stdout)
    except json.JSONDecodeError as error:
        raise SystemExit(
            "qemu-img VHDX inspection returned invalid JSON "
            f"path={destination}: {error}"
        ) from error
    if not isinstance(document, dict) or document.get("format") != "vhdx":
        output_format = document.get("format") if isinstance(document, dict) else None
        raise SystemExit(
            f"qemu-img output is not VHDX path={destination} format={output_format}"
        )
    if not destination.is_file() or destination.stat().st_size <= 0:
        raise SystemExit(f"qemu-img did not create a non-empty VHDX: {destination}")


def _require_file(path: Path, label: str, *, allow_symlink: bool = False) -> None:
    if not path.is_file() or (path.is_symlink() and not allow_symlink):
        raise SystemExit(f"{label} is missing or not a regular file: {path}")


def _snapshot_input(source: Path, destination: Path) -> Path:
    shutil.copyfile(source, destination)
    return destination


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _file_identity(path: Path) -> dict[str, object]:
    return {"sha256": _sha256(path), "bytes": path.stat().st_size}


if __name__ == "__main__":
    raise SystemExit(main())

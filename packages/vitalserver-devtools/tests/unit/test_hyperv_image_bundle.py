from __future__ import annotations

import json
from pathlib import Path
import struct
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parents[4]
BUILDER = ROOT / "scripts/build_hyperv_image_bundle.py"
EFI = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b")


def test_hyperv_builder_requires_amd64_proof_and_compiles_three_artifacts(
    tmp_path: Path,
) -> None:
    system_raw = tmp_path / "system.raw"
    _write_gpt_disk(system_raw)
    data_raw = tmp_path / "data.raw"
    data_raw.write_bytes(b"runtime-data")
    seed = tmp_path / "seed.iso"
    seed.write_bytes(b"nocloud")
    proof = tmp_path / "proof.json"
    proof.write_text(
        json.dumps(
            {
                "runId": "run-amd64-1",
                "dockerImages": {
                    "platform": "linux/amd64",
                    "guestArchitecture": "x86_64",
                    "status": "passed",
                },
                "cleanup": {"status": "passed"},
                "portableDeploy": {
                    "status": "passed",
                    "mountMode": "native",
                    "treeSHA256": "deploy-sha",
                },
            }
        ),
        encoding="utf-8",
    )
    qemu = tmp_path / "qemu-img"
    qemu.write_text(
        "#!/bin/sh\n"
        "if [ \"$1\" = convert ]; then\n"
        "  previous=\n"
        "  current=\n"
        "  for argument do previous=$current; current=$argument; done\n"
        "  cp \"$previous\" \"$current\"\n"
        "else\n"
        "  printf '%s\\n' '{\"format\":\"vhdx\"}'\n"
        "fi\n",
        encoding="utf-8",
    )
    qemu.chmod(0o755)
    output = tmp_path / "hyperv"

    subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--system-raw",
            str(system_raw),
            "--runtime-data-raw",
            str(data_raw),
            "--seed-iso",
            str(seed),
            "--rootfs-proof",
            str(proof),
            "--qemu-img",
            str(qemu),
            "--output-directory",
            str(output),
        ],
        check=True,
    )

    manifest = json.loads((output / "hyperv-image.json").read_text(encoding="utf-8"))
    assert manifest["state"] == "compiled"
    assert manifest["runId"] == "run-amd64-1"
    assert manifest["architecture"] == "amd64"
    assert manifest["systemVHDX"]["sha256"]
    assert manifest["runtimeDataVHDX"]["sha256"]
    assert manifest["seedISO"]["sha256"]
    assert manifest["readError"] is None


def test_hyperv_builder_rejects_arm64_proof_before_conversion(tmp_path: Path) -> None:
    proof = tmp_path / "proof.json"
    proof.write_text(
        json.dumps(
            {
                "runId": "run-arm64",
                "dockerImages": {"platform": "linux/arm64", "status": "passed"},
                "cleanup": {"status": "passed"},
            }
        ),
        encoding="utf-8",
    )
    missing = tmp_path / "missing"
    result = subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--system-raw",
            str(missing),
            "--runtime-data-raw",
            str(missing),
            "--seed-iso",
            str(missing),
            "--rootfs-proof",
            str(proof),
            "--qemu-img",
            str(missing),
            "--output-directory",
            str(tmp_path / "output"),
        ],
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    assert "not linux/amd64" in result.stderr


def _write_gpt_disk(path: Path) -> None:
    data = bytearray(1024 * 1024)
    header = memoryview(data)[512 : 512 + 92]
    header[:8] = b"EFI PART"
    struct.pack_into("<Q", header, 72, 2)
    struct.pack_into("<I", header, 80, 1)
    struct.pack_into("<I", header, 84, 128)
    data[1024 : 1024 + 16] = EFI.bytes_le
    path.write_bytes(data)

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[4]
TOOL = ROOT / "scripts/build_update_trust_catalog.py"


def test_catalog_is_deterministic_and_matches_exact_archives(tmp_path: Path) -> None:
    linux = tmp_path / "VitalServer-Linux.tar.gz"
    windows = tmp_path / "VitalServer-Windows.zip"
    linux.write_bytes(b"linux archive")
    windows.write_bytes(b"windows archive")
    first = tmp_path / "first.json"
    second = tmp_path / "second.json"

    first_result = run_tool(first, windows, linux)
    second_result = run_tool(second, linux, windows)

    assert first.read_bytes() == second.read_bytes()
    document = json.loads(first.read_text(encoding="utf-8"))
    assert document == {
        "schemaVersion": 1,
        "sha256": sorted((digest(linux), digest(windows))),
    }
    assert first_result["catalogSHA256"] == digest(first)
    assert [item["name"] for item in second_result["artifacts"]] == [
        "VitalServer-Linux.tar.gz",
        "VitalServer-Windows.zip",
    ]


def test_catalog_rejects_duplicate_archive_content(tmp_path: Path) -> None:
    one = tmp_path / "one.zip"
    two = tmp_path / "two.zip"
    one.write_bytes(b"same")
    two.write_bytes(b"same")
    result = subprocess.run(
        [sys.executable, str(TOOL), "--archive", str(one), "--archive", str(two), "--output", str(tmp_path / "catalog.json")],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "content digest is duplicated" in result.stderr


def test_catalog_rejects_unsealed_windows_acceptance_candidate(tmp_path: Path) -> None:
    candidate = tmp_path / "VitalServer-Windows.zip"
    with zipfile.ZipFile(candidate, "w") as archive:
        archive.writestr(
            "VitalServer-Windows/release.json",
            json.dumps({
                "schemaVersion": 1,
                "state": "acceptanceCandidate",
                "installedAcceptanceRunId": None,
            }),
        )
        archive.writestr("VitalServer-Windows/proof/acceptance-pending.json", "{}")
    result = subprocess.run(
        [sys.executable, str(TOOL), "--archive", str(candidate), "--output", str(tmp_path / "catalog.json")],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "not a sealed releaseCandidate" in result.stderr


def test_catalog_accepts_sealed_windows_release_candidate(tmp_path: Path) -> None:
    candidate = tmp_path / "VitalServer-Windows.zip"
    with zipfile.ZipFile(candidate, "w") as archive:
        archive.writestr(
            "VitalServer-Windows/release.json",
            json.dumps({
                "schemaVersion": 1,
                "state": "releaseCandidate",
                "installedAcceptanceRunId": "windows-acceptance-1",
            }),
        )
        archive.writestr("VitalServer-Windows/proof/windows-hyperv-acceptance.json", "{}")
    output = tmp_path / "catalog.json"
    run_tool(output, candidate)
    assert json.loads(output.read_text())["sha256"] == [digest(candidate)]


def run_tool(output: Path, *archives: Path) -> dict[str, object]:
    command = [sys.executable, str(TOOL)]
    for archive in archives:
        command.extend(("--archive", str(archive)))
    command.extend(("--output", str(output)))
    return json.loads(subprocess.check_output(command, text=True))


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

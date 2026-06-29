from __future__ import annotations

import argparse
from pathlib import Path
from types import SimpleNamespace

import pytest

from tirosh_vitalserver.testkit.adapters.inbound.cli import vital_files
from tirosh_vitalserver.testkit.domain.vital_file import PayloadFile


def test_recover_raw_archive_vital_delegates_to_product_cli(
    tmp_path: Path,
    monkeypatch,
) -> None:
    raw_archive = tmp_path / "send-data-raw.jsonl"
    output_dir = tmp_path / "exported"
    raw_archive.write_text("{}\n", encoding="utf-8")
    captured: dict[str, object] = {}

    monkeypatch.setattr(vital_files.shutil, "which", lambda _name: "/bin/recovery")

    def fake_run(command, *, check):
        captured["command"] = command
        captured["check"] = check
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(vital_files.subprocess, "run", fake_run)

    result = vital_files.run_recover_raw_archive_vital(
        argparse.Namespace(
            raw_archive_path=raw_archive,
            output_dir=output_dir,
            vitalserver_url="http://vitalserver.local",
            timeout=12.0,
            vrcode=None,
            concurrency=4,
            repeat=1,
            endpoint="/upload",
            max_failure_rate=0.0,
            skip_filename_check=False,
        )
    )

    assert result == 0
    assert captured["check"] is False
    assert captured["command"] == [
        "/bin/recovery",
        "recover-raw-archive-vital",
        str(raw_archive),
        "--output-dir",
        str(output_dir),
        "--vitalserver-url",
        "http://vitalserver.local",
        "--endpoint",
        "/upload",
        "--timeout",
        "12.0",
        "--concurrency",
        "4",
        "--repeat",
        "1",
        "--max-failure-rate",
        "0.0",
    ]


def test_upload_vital_does_not_require_recorder_recovery(
    tmp_path: Path,
    monkeypatch,
) -> None:
    vital_path = tmp_path / "BED_260101_010101.vital"
    vital_path.write_bytes(b"vital")
    payload = PayloadFile(path=vital_path, size_bytes=5)

    monkeypatch.setattr(vital_files.shutil, "which", lambda _name: None)
    monkeypatch.setattr(
        vital_files,
        "VitalServerClient",
        lambda *args, **kwargs: object(),
    )
    monkeypatch.setattr(vital_files, "iter_vital_files", lambda _path: (payload,))
    monkeypatch.setattr(vital_files, "assert_vital_filenames", lambda _payloads: None)
    monkeypatch.setattr(
        vital_files,
        "upload_vital_files",
        lambda *args, **kwargs: SimpleNamespace(),
    )
    monkeypatch.setattr(vital_files, "print_summary", lambda _summary: None)
    monkeypatch.setattr(
        vital_files,
        "assert_transfer_success",
        lambda *args, **kwargs: None,
    )

    result = vital_files.run_upload_vital(
        argparse.Namespace(
            path=vital_path,
            skip_filename_check=False,
            vitalserver_url="http://vitalserver.local",
            timeout=12.0,
            vrcode=None,
            concurrency=1,
            repeat=1,
            endpoint="/upload",
            max_failure_rate=0.0,
        )
    )

    assert result == 0


def test_raw_archive_export_reports_missing_recorder_recovery(monkeypatch) -> None:
    monkeypatch.setattr(vital_files.shutil, "which", lambda _name: None)

    with pytest.raises(RuntimeError, match=r"raw archive \.vital recovery requires"):
        vital_files.run_export_raw_archive_vital(
            argparse.Namespace(
                raw_archive_path=Path("/raw/send-data-raw.jsonl"),
                output_dir=Path("/exports"),
            )
        )

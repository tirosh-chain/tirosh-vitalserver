from __future__ import annotations

from pathlib import Path

import pytest

from tirosh_vitalserver.testkit.cli import main


def test_cli_help_returns_usage(capsys: pytest.CaptureFixture[str]) -> None:
    exit_code = main([])

    captured = capsys.readouterr()
    assert exit_code == 2
    assert "usage: vitalserver-testkit" in captured.out


def test_cli_subcommand_help(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc_info:
        main(["send-recorder", "--help"])

    captured = capsys.readouterr()
    assert exc_info.value.code == 0
    assert "sample_data.json" not in captured.out
    assert "payload" in captured.out
    assert "--dataset-manifest" in captured.out
    assert "Socket.IO" in captured.out


def test_cli_list_recorder_dataset_prints_recommended_sets(
    tmp_path: Path,
    capsys: pytest.CaptureFixture[str],
) -> None:
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        """
        {
          "schemaVersion": 1,
          "dataset": "mo-real-vital-recorder-json-120s",
          "recommendedSets": {
            "baseline": {
              "source": "source.vital",
              "payload": "payload.json",
              "payloadTrackCount": 50,
              "recordCount": 5000,
              "sampleCount": 79000,
              "devices": ["Bx50", "Primus"],
              "tags": ["high_track_count"]
            }
          },
          "payloads": []
        }
        """,
        encoding="utf-8",
    )

    exit_code = main(["list-recorder-dataset", str(manifest)])

    captured = capsys.readouterr()
    assert exit_code == 0
    assert "dataset: mo-real-vital-recorder-json-120s" in captured.out
    assert "key=baseline" in captured.out
    assert "tracks=50" in captured.out


def test_cli_serve_help(capsys: pytest.CaptureFixture[str]) -> None:
    with pytest.raises(SystemExit) as exc_info:
        main(["serve", "--help"])

    captured = capsys.readouterr()
    assert exc_info.value.code == 0
    assert "Run the loopback TestKit API server" in captured.out
    assert "--port" in captured.out


def test_cli_bed_scenario_parse_error_is_user_facing(
    capsys: pytest.CaptureFixture[str],
) -> None:
    with pytest.raises(SystemExit) as exc_info:
        main(["stream-recorder", "--bed-scenario", "bad"])

    captured = capsys.readouterr()
    assert exc_info.value.code == 2
    assert "bed scenario must be INDEX=SCENARIO" in captured.err

from __future__ import annotations

from pathlib import Path

import pytest

from tirosh_vitalserver.testkit.domain.vital_file import (
    assert_vital_filenames,
    iter_vital_files,
    playback_time_for_sequence,
)
from tirosh_vitalserver.testkit.errors import InvalidVitalFilenameError


def test_iter_vital_files_returns_only_vital_files(tmp_path: Path) -> None:
    vital_file = tmp_path / "DEMO_260509_120000.vital"
    ignored_file = tmp_path / "README.txt"
    vital_file.write_bytes(b"payload")
    ignored_file.write_text("ignored")

    payloads = iter_vital_files(tmp_path)

    assert len(payloads) == 1
    assert payloads[0].path == vital_file
    assert payloads[0].size_bytes == len(b"payload")


def test_assert_vital_filenames_accepts_vitaldb_upload_shape(tmp_path: Path) -> None:
    vital_file = tmp_path / "DEMO_260509_120000.vital"
    vital_file.write_bytes(b"payload")

    assert_vital_filenames(iter_vital_files(vital_file))


def test_assert_vital_filenames_accepts_auto_export_suffix(tmp_path: Path) -> None:
    vital_file = tmp_path / "DEMO_260509_120000_auto_export.vital"
    vital_file.write_bytes(b"payload")

    assert_vital_filenames(iter_vital_files(vital_file))


def test_assert_vital_filenames_rejects_unknown_shape(tmp_path: Path) -> None:
    vital_file = tmp_path / "DEMO.vital"
    vital_file.write_bytes(b"payload")

    with pytest.raises(
        InvalidVitalFilenameError,
        match="invalid vital filename format",
    ):
        assert_vital_filenames(iter_vital_files(vital_file))


def test_playback_time_for_sequence_skips_pause_window() -> None:
    assert playback_time_for_sequence(
        2,
        started_at=100.0,
        frame_seconds=1.0,
        playback_events=(
            ("started", 100.0),
            ("paused", 101.5),
            ("resumed", 111.5),
            ("stopped", 115.0),
        ),
    ) == 112.0


def test_playback_time_rejects_unmatched_resume() -> None:
    with pytest.raises(ValueError, match="resumed without paused"):
        playback_time_for_sequence(
            1,
            started_at=100.0,
            frame_seconds=1.0,
            playback_events=(
                ("started", 100.0),
                ("resumed", 101.0),
            ),
        )

import os
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.outbound.vital_files import FileVitalFileLibrary
from tirosh_guest_tools.domain.guest_control.models import GuestControlDependencyError


def test_imports_multiple_vital_files_as_one_batch(tmp_path: Path) -> None:
    library = tmp_path / "library"
    library.mkdir()

    result = FileVitalFileLibrary(library).import_files(
        [("first.vital", b"first"), ("second.VITAL", b"second")]
    )

    assert result == [
        {"fileName": "first.vital", "relativePath": "first.vital", "sizeBytes": 5},
        {"fileName": "second.VITAL", "relativePath": "second.VITAL", "sizeBytes": 6},
    ]
    assert (library / "first.vital").read_bytes() == b"first"
    assert (library / "second.VITAL").read_bytes() == b"second"


def test_rejects_entire_batch_when_one_file_is_not_vital(tmp_path: Path) -> None:
    library = tmp_path / "library"
    library.mkdir()

    with pytest.raises(GuestControlDependencyError) as raised:
        FileVitalFileLibrary(library).import_files(
            [("accepted.vital", b"vital"), ("rejected.txt", b"text")]
        )

    assert raised.value.kind == "vitalFileUploadInvalid"
    assert list(library.iterdir()) == []


def test_rejects_entire_batch_before_copying_when_destination_exists(
    tmp_path: Path,
) -> None:
    library = tmp_path / "library"
    library.mkdir()
    (library / "existing.vital").write_bytes(b"existing")

    with pytest.raises(GuestControlDependencyError) as raised:
        FileVitalFileLibrary(library).import_files(
            [("new.vital", b"new"), ("existing.vital", b"replacement")]
        )

    assert raised.value.kind == "vitalFileUploadConflict"
    assert not (library / "new.vital").exists()
    assert (library / "existing.vital").read_bytes() == b"existing"


def test_does_not_overwrite_file_created_during_batch_commit(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    library = tmp_path / "library"
    library.mkdir()
    original_link = os.link

    def link_with_competing_writer(source: Path, destination: Path) -> None:
        if Path(destination).name == "raced.vital":
            Path(destination).write_bytes(b"competing-writer")
        original_link(source, destination)

    monkeypatch.setattr(os, "link", link_with_competing_writer)

    with pytest.raises(GuestControlDependencyError) as raised:
        FileVitalFileLibrary(library).import_files(
            [("first.vital", b"first"), ("raced.vital", b"requested")]
        )

    assert raised.value.kind == "vitalFileUploadFailed"
    assert not (library / "first.vital").exists()
    assert (library / "raced.vital").read_bytes() == b"competing-writer"

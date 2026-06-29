"""Compatibility policy for `.vital` upload files."""

from __future__ import annotations

from collections.abc import Iterable

from tirosh_vitalserver.core.domain.vital_file import (
    VITAL_FILENAME_RE,
    PayloadFile,
)
from tirosh_vitalserver.core.domain.vital_file import (
    assert_vital_filenames as assert_core_vital_filenames,
)
from tirosh_vitalserver.core.errors import InvalidVitalFilenameError as CoreError
from tirosh_vitalserver.testkit.errors import InvalidVitalFilenameError


def assert_vital_filenames(payloads: Iterable[PayloadFile]) -> None:
    """Validate filenames while preserving TestKit's public error contract."""

    try:
        assert_core_vital_filenames(payloads)
    except CoreError as exc:
        raise InvalidVitalFilenameError(exc.filenames) from exc


__all__ = ["VITAL_FILENAME_RE", "assert_vital_filenames"]

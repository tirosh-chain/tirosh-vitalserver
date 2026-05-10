"""Validation policy for `.vital` upload files."""

from __future__ import annotations

import re
from collections.abc import Iterable

from tirosh_vitalserver.testkit.domain.vital_file.models import PayloadFile

VITAL_FILENAME_RE = re.compile(r"^.+_\d{6}_\d{6}\.vital$")


def assert_vital_filenames(payloads: Iterable[PayloadFile]) -> None:
    """Validate the filename shape documented by VitalDB upload API."""

    invalid = [
        payload.path.name
        for payload in payloads
        if not VITAL_FILENAME_RE.match(payload.path.name)
    ]

    if invalid:
        joined = ", ".join(invalid)
        raise ValueError(f"invalid vital filename format: {joined}")

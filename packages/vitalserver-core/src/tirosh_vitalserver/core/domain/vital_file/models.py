"""Value objects for local `.vital` files."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class PayloadFile:
    """Local file selected for VitalServer upload."""

    path: Path
    size_bytes: int

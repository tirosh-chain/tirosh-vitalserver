from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class HelperHostPlatformReleaseOperations:
    compose_archive: Callable[[Path, Path], tuple[str, int, str]]


def compose(
    composition: Path,
    output: Path,
    operations: HelperHostPlatformReleaseOperations,
) -> int:
    sha256, size_bytes, media_type = operations.compose_archive(
        composition,
        output,
    )
    print(
        "Helper Host Platform release archive is ready: "
        f"{output} sha256={sha256} sizeBytes={size_bytes} "
        f"mediaType={media_type}"
    )
    return 0

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BuildUpdateBootstrapBundleInput:
    update_id: str
    product_version: str
    runtime_version: str
    target_platform: str
    target_architecture: str
    layer_order: list[str]
    next_updater: Path
    specification: Path
    publisher_key_id: str
    publisher_private_key: Path
    issued_at: str
    output: Path


@dataclass(frozen=True)
class BuildUpdateBootstrapBundleResult:
    archive: Path
    envelope_sha256: str


@dataclass(frozen=True)
class VerifyUpdateBootstrapBundleInput:
    bundle: Path
    publisher_public_key: Path

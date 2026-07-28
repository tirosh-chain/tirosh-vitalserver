from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any

from tirosh_guest_tools.domain.container_image_set import ContainerImageSet
from tirosh_guest_tools.domain.guest_runtime_release import GuestRuntimeRelease

SCHEMA_VERSION = "vitalserver.initial-update-owner-state/v1"


class InitialUpdateOwnerStateContractError(ValueError):
    pass


@dataclass(frozen=True)
class InitialOwnerArtifact:
    relative_path: str
    digest: str
    owner_reference: str

    def source(self, deploy_dir: Path) -> Path:
        return deploy_dir.joinpath(*PurePosixPath(self.relative_path).parts)


@dataclass(frozen=True)
class InitialUpdateOwnerState:
    contract_digest: str
    release_label: str
    container_image_set: ContainerImageSet
    container_artifact: InitialOwnerArtifact
    guest_runtime_release: GuestRuntimeRelease
    guest_runtime_artifact: InitialOwnerArtifact


def load_initial_update_owner_state(path: Path) -> InitialUpdateOwnerState:
    try:
        source = path.read_bytes()
        document = json.loads(source.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise InitialUpdateOwnerStateContractError(
            f"Initial update owner state is unreadable or invalid: {path}: {error}"
        ) from error
    return parse_initial_update_owner_state(
        document,
        contract_digest=f"sha256:{hashlib.sha256(source).hexdigest()}",
    )


def parse_initial_update_owner_state(
    document: object,
    *,
    contract_digest: str,
) -> InitialUpdateOwnerState:
    contract_digest = _sha256(contract_digest, "contractDigest")
    root = _object(
        document,
        "initial update owner state",
        {"schemaVersion", "releaseLabel", "containerImageSet", "guestRuntimeRelease"},
    )
    if root["schemaVersion"] != SCHEMA_VERSION:
        raise InitialUpdateOwnerStateContractError(
            "Initial update owner state schemaVersion is unsupported."
        )
    release_label = _non_empty_string(root["releaseLabel"], "releaseLabel")
    container = _owner(
        root["containerImageSet"],
        "containerImageSet",
        release_label=release_label,
        kind="container-image-set",
    )
    guest_runtime = _owner(
        root["guestRuntimeRelease"],
        "guestRuntimeRelease",
        release_label=release_label,
        kind="guest-runtime-release",
    )
    container_image_set = ContainerImageSet.validated(
        container["identity"],
        container["artifact"].digest,
    )
    guest_runtime_release = GuestRuntimeRelease.validated(
        guest_runtime["identity"],
        guest_runtime["artifact"].owner_reference,
        guest_runtime["artifact"].digest,
    )
    return InitialUpdateOwnerState(
        contract_digest=contract_digest,
        release_label=release_label,
        container_image_set=container_image_set,
        container_artifact=container["artifact"],
        guest_runtime_release=guest_runtime_release,
        guest_runtime_artifact=guest_runtime["artifact"],
    )


def _owner(
    value: object,
    name: str,
    *,
    release_label: str,
    kind: str,
) -> dict[str, Any]:
    owner = _object(value, name, {"identity", "artifact"})
    identity = _non_empty_string(owner["identity"], f"{name}.identity")
    expected_identity = f"{kind}:{release_label}"
    if identity != expected_identity:
        raise InitialUpdateOwnerStateContractError(
            f"{name}.identity must equal {expected_identity}."
        )
    artifact_value = _object(
        owner["artifact"],
        f"{name}.artifact",
        {"relativePath", "digest", "ownerReference"},
    )
    relative_path = _safe_relative_path(
        artifact_value["relativePath"],
        f"{name}.artifact.relativePath",
    )
    digest = _sha256(artifact_value["digest"], f"{name}.artifact.digest")
    owner_reference = _non_empty_string(
        artifact_value["ownerReference"],
        f"{name}.artifact.ownerReference",
    )
    expected_reference = f"{kind}/{digest.removeprefix('sha256:')}.archive"
    if owner_reference != expected_reference:
        raise InitialUpdateOwnerStateContractError(
            f"{name}.artifact.ownerReference disagrees with kind and digest."
        )
    return {
        "identity": identity,
        "artifact": InitialOwnerArtifact(
            relative_path=relative_path,
            digest=digest,
            owner_reference=owner_reference,
        ),
    }


def _object(
    value: object,
    name: str,
    keys: set[str],
) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        actual = sorted(value) if isinstance(value, dict) else type(value).__name__
        raise InitialUpdateOwnerStateContractError(
            f"{name} keys disagree expected={sorted(keys)} actual={actual}."
        )
    return value


def _non_empty_string(value: object, name: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise InitialUpdateOwnerStateContractError(f"{name} must be non-empty.")
    return value.strip()


def _sha256(value: object, name: str) -> str:
    text = _non_empty_string(value, name)
    if not text.startswith("sha256:"):
        raise InitialUpdateOwnerStateContractError(
            f"{name} must use sha256:<hex>."
        )
    digest = text.removeprefix("sha256:")
    if len(digest) != 64 or any(
        character not in "0123456789abcdef" for character in digest
    ):
        raise InitialUpdateOwnerStateContractError(
            f"{name} must contain 64 lowercase hex characters."
        )
    return text


def _safe_relative_path(value: object, name: str) -> str:
    text = _non_empty_string(value, name)
    path = PurePosixPath(text)
    if path.is_absolute() or any(part in {"", ".", ".."} for part in path.parts):
        raise InitialUpdateOwnerStateContractError(
            f"{name} must be a safe relative path."
        )
    return path.as_posix()

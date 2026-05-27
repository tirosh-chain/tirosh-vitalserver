from __future__ import annotations

from datetime import datetime
from pathlib import Path
from typing import Any

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.update_bundle_models import (
    ArchiveMember,
    BuildUpdateBundleInput,
)

PRODUCT_ID = "com.tirosh.vitalserver"
SUPPORTED_BUNDLE_KINDS = {"product-update", "vm-image-update"}
SUPPORTED_CHANNELS = {"stable", "dev"}


def default_bundle_name(spec: BuildUpdateBundleInput) -> str:
    return f"update-bundle-{spec.channel}-{spec.bundle_kind}-{spec.version}"


def resolve_bundle_name(spec: BuildUpdateBundleInput) -> str:
    bundle_name = spec.bundle_name or default_bundle_name(spec)
    if not is_safe_bundle_name(bundle_name):
        raise DomainError(f"invalid bundle name: {bundle_name}")
    return bundle_name


def build_manifest(
    *,
    spec: BuildUpdateBundleInput,
    artifact_entries: list[dict[str, object]],
    migration_entries: list[dict[str, object]],
    created_at: datetime,
) -> dict[str, object]:
    helper_version = spec.helper_version or spec.version
    release_label = spec.release_label or spec.version
    return {
        "schemaVersion": 3,
        "product": PRODUCT_ID,
        "bundleKind": spec.bundle_kind,
        "channel": spec.channel,
        "helperVersion": helper_version,
        "releaseLabel": release_label,
        "targetPlatform": spec.target_platform,
        "components": component_versions(spec.component, helper_version),
        "minUpdaterVersion": (
            spec.min_updater_version or spec.runtime_version or helper_version
        ),
        "requiresGuestActivation": (
            spec.requires_guest_activation
            if spec.requires_guest_activation is not None
            else spec.guest_deploy is not None
        ),
        "requiresTwoPhaseUpdate": spec.requires_two_phase_update,
        "createdAt": created_at.replace(microsecond=0).isoformat(),
        "artifacts": artifact_entries,
        "migrations": migration_entries,
    }


def validate_manifest(manifest: dict[str, Any]) -> None:
    required = {
        "schemaVersion": int,
        "product": str,
        "bundleKind": str,
        "channel": str,
        "helperVersion": str,
        "releaseLabel": str,
        "targetPlatform": str,
        "components": dict,
        "minUpdaterVersion": str,
        "requiresGuestActivation": bool,
        "requiresTwoPhaseUpdate": bool,
        "createdAt": str,
        "artifacts": list,
        "migrations": list,
    }
    for key, expected_type in required.items():
        if key not in manifest:
            raise DomainError(f"manifest missing key: {key}")
        if not isinstance(manifest[key], expected_type):
            raise DomainError(f"manifest key has wrong type: {key}")

    if manifest["schemaVersion"] != 3:
        raise DomainError(f"unsupported schemaVersion: {manifest['schemaVersion']}")
    if manifest["product"] != PRODUCT_ID:
        raise DomainError(f"unsupported product: {manifest['product']}")
    if manifest["bundleKind"] not in SUPPORTED_BUNDLE_KINDS:
        raise DomainError(f"unsupported bundleKind: {manifest['bundleKind']}")
    if manifest["channel"] not in SUPPORTED_CHANNELS:
        raise DomainError(f"unsupported channel: {manifest['channel']}")
    if not manifest["releaseLabel"]:
        raise DomainError("releaseLabel must be non-empty")
    if not manifest["targetPlatform"]:
        raise DomainError("targetPlatform must be non-empty")
    for key, value in manifest["components"].items():
        if not isinstance(key, str) or not key:
            raise DomainError("components keys must be non-empty strings")
        if not isinstance(value, str) or not value:
            raise DomainError(f"component version must be a non-empty string: {key}")

    for artifact in manifest["artifacts"]:
        validate_artifact_entry(artifact)

    for migration in manifest["migrations"]:
        validate_migration_entry(migration)


def validate_artifact_entry(artifact: object) -> None:
    if not isinstance(artifact, dict):
        raise DomainError("artifact entry must be an object")
    for key in ("name", "type", "sha256", "size"):
        if key not in artifact:
            raise DomainError(f"artifact missing key: {key}")
    if not isinstance(artifact["name"], str) or not is_safe_bundle_name(
        artifact["name"]
    ):
        raise DomainError(f"invalid artifact name: {artifact['name']}")
    if not isinstance(artifact["type"], str):
        raise DomainError(f"invalid artifact type for {artifact['name']}")
    if not isinstance(artifact["sha256"], str) or len(artifact["sha256"]) != 64:
        raise DomainError(f"invalid sha256 for {artifact['name']}")
    if not isinstance(artifact["size"], int) or artifact["size"] < 0:
        raise DomainError(f"invalid size for {artifact['name']}")


def validate_migration_entry(migration: object) -> None:
    if not isinstance(migration, dict):
        raise DomainError("migration entry must be an object")
    for key in ("name", "sha256", "size"):
        if key not in migration:
            raise DomainError(f"migration missing key: {key}")
    if not isinstance(migration["name"], str) or not is_safe_bundle_name(
        migration["name"]
    ):
        raise DomainError(f"invalid migration name: {migration['name']}")
    if not isinstance(migration["sha256"], str) or len(migration["sha256"]) != 64:
        raise DomainError(f"invalid sha256 for migration {migration['name']}")
    if not isinstance(migration["size"], int) or migration["size"] < 0:
        raise DomainError(f"invalid size for migration {migration['name']}")


def validated_archive_root(members: list[ArchiveMember]) -> str:
    root_name: str | None = None
    if not members:
        raise DomainError("empty update bundle archive")
    for member in members:
        name = member.name
        if (
            member.is_symlink
            or member.is_hardlink
            or not (member.is_file or member.is_dir)
        ):
            raise DomainError(f"unsafe archive entry type: {name}")
        if name.startswith("/") or "\\" in name:
            raise DomainError(f"unsafe archive path: {name}")
        parts = [part for part in Path(name).parts if part not in {"", "."}]
        if not parts or any(part == ".." for part in parts):
            raise DomainError(f"unsafe archive path: {name}")
        if root_name is None:
            root_name = parts[0]
        elif root_name != parts[0]:
            raise DomainError(
                "update bundle archive must contain a single root directory"
            )
    if root_name is None:
        raise DomainError("empty update bundle archive")
    return root_name


def is_update_bundle_archive(path: Path) -> bool:
    name = path.name
    return name.endswith(".tar.gz") or name.endswith(".tgz")


def is_safe_bundle_name(name: str) -> bool:
    path = Path(name)
    return name not in {"", ".", ".."} and path.name == name


def component_versions(entries: list[str], helper_version: str) -> dict[str, str]:
    components = {
        "helperUI": helper_version,
        "updater": helper_version,
        "supervisor": helper_version,
        "vmDriver": helper_version,
    }
    for entry in entries:
        if "=" not in entry:
            raise DomainError(f"component must be key=value: {entry}")
        key, value = entry.split("=", 1)
        if not key or not value:
            raise DomainError(f"component must be key=value: {entry}")
        components[key] = value
    return components

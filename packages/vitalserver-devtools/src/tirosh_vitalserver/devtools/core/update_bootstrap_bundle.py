from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Any

from tirosh_vitalserver.devtools.core.errors import DomainError

SCHEMA_VERSION = "v2"
PRODUCT_ID = "ai.tirosh.vitalserver.helper"
SUPPORTED_PLATFORMS = {"macos", "windows", "linux"}
SUPPORTED_ARCHITECTURES = {"arm64", "amd64"}
SUPPORTED_LAYERS = {"container", "guest-runtime", "host-platform"}
IDENTIFIER = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
VERSION = re.compile(r"^[A-Za-z0-9.+_-]{1,128}$")
CANONICAL_UTC = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def artifact(
    *,
    artifact_id: str,
    relative_path: str,
    source: Path,
    media_type: str,
) -> dict[str, object]:
    if not source.is_file():
        raise DomainError(f"bootstrap artifact is missing: {source}")
    entry = {
        "id": artifact_id,
        "relativePath": relative_path,
        "sha256": sha256_file(source),
        "sizeBytes": source.stat().st_size,
        "mediaType": media_type,
    }
    validate_artifact(entry)
    return entry


def unsigned_envelope(
    *,
    update_id: str,
    product_version: str,
    runtime_version: str,
    target_platform: str,
    target_architecture: str,
    layer_order: list[str],
    next_updater_artifact: dict[str, object],
    specification_artifact: dict[str, object],
    payload_artifacts: list[dict[str, object]],
    issued_at: str,
) -> dict[str, object]:
    envelope: dict[str, object] = {
        "schemaVersion": SCHEMA_VERSION,
        "id": update_id,
        "productId": PRODUCT_ID,
        "target": {
            "platform": target_platform,
            "architecture": target_architecture,
        },
        "targetRelease": {
            "productVersion": product_version,
            "runtimeVersion": runtime_version,
        },
        "layerOrder": layer_order,
        "nextUpdaterArtifact": next_updater_artifact,
        "specification": specification_artifact,
        "payloadArtifacts": payload_artifacts,
        "issuedAt": issued_at,
    }
    validate_unsigned_envelope(envelope)
    return envelope


def canonical_payload(envelope: dict[str, object]) -> bytes:
    validate_unsigned_envelope(envelope)
    ordered = {
        "schemaVersion": envelope["schemaVersion"],
        "id": envelope["id"],
        "productId": envelope["productId"],
        "target": {
            "platform": _object(envelope["target"])["platform"],
            "architecture": _object(envelope["target"])["architecture"],
        },
        "targetRelease": {
            "productVersion": _object(envelope["targetRelease"])["productVersion"],
            "runtimeVersion": _object(envelope["targetRelease"])["runtimeVersion"],
        },
        "layerOrder": envelope["layerOrder"],
        "nextUpdaterArtifact": _ordered_artifact(
            _object(envelope["nextUpdaterArtifact"])
        ),
        "specification": _ordered_artifact(_object(envelope["specification"])),
        "payloadArtifacts": [
            _ordered_artifact(_object(entry)) for entry in envelope["payloadArtifacts"]
        ],
        "issuedAt": envelope["issuedAt"],
    }
    return json.dumps(
        ordered,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")


def seal_envelope(
    *,
    unsigned: dict[str, object],
    publisher_key_id: str,
    signature_base64: str,
) -> dict[str, object]:
    require_identifier(publisher_key_id, "signature.keyId")
    if not signature_base64:
        raise DomainError("signature.value must be non-empty")
    payload = canonical_payload(unsigned)
    sealed = dict(unsigned)
    sealed["signature"] = {
        "algorithm": "ed25519",
        "keyId": publisher_key_id,
        "signedSha256": hashlib.sha256(payload).hexdigest(),
        "value": signature_base64,
    }
    validate_envelope(sealed)
    return sealed


def validate_envelope(envelope: dict[str, Any]) -> None:
    require_exact_keys(
        envelope,
        {
            "schemaVersion",
            "id",
            "productId",
            "target",
            "targetRelease",
            "layerOrder",
            "nextUpdaterArtifact",
            "specification",
            "payloadArtifacts",
            "signature",
            "issuedAt",
        },
        "bootstrap envelope",
    )
    unsigned = dict(envelope)
    signature = _object(unsigned.pop("signature"))
    validate_unsigned_envelope(unsigned)
    require_exact_keys(
        signature,
        {"algorithm", "keyId", "signedSha256", "value"},
        "signature",
    )
    if signature["algorithm"] != "ed25519":
        raise DomainError(f"unsupported signature algorithm: {signature['algorithm']}")
    require_identifier(signature["keyId"], "signature.keyId")
    if not isinstance(signature["signedSha256"], str) or not SHA256.fullmatch(
        signature["signedSha256"]
    ):
        raise DomainError("signature.signedSha256 must be lowercase SHA-256")
    expected = hashlib.sha256(canonical_payload(unsigned)).hexdigest()
    if signature["signedSha256"] != expected:
        raise DomainError(
            "signature.signedSha256 does not match canonical bootstrap payload"
        )
    if not isinstance(signature["value"], str) or not signature["value"]:
        raise DomainError("signature.value must be non-empty")


def validate_unsigned_envelope(envelope: dict[str, Any]) -> None:
    require_exact_keys(
        envelope,
        {
            "schemaVersion",
            "id",
            "productId",
            "target",
            "targetRelease",
            "layerOrder",
            "nextUpdaterArtifact",
            "specification",
            "payloadArtifacts",
            "issuedAt",
        },
        "unsigned bootstrap envelope",
    )
    if envelope["schemaVersion"] != SCHEMA_VERSION:
        raise DomainError(
            f"unsupported bootstrap schemaVersion: {envelope['schemaVersion']}"
        )
    if envelope["productId"] != PRODUCT_ID:
        raise DomainError(f"unsupported bootstrap productId: {envelope['productId']}")
    require_identifier(envelope["id"], "id")
    target = _object(envelope["target"])
    require_exact_keys(target, {"platform", "architecture"}, "target")
    if target["platform"] not in SUPPORTED_PLATFORMS:
        raise DomainError(f"unsupported target platform: {target['platform']}")
    if target["architecture"] not in SUPPORTED_ARCHITECTURES:
        raise DomainError(f"unsupported target architecture: {target['architecture']}")
    release = _object(envelope["targetRelease"])
    require_exact_keys(
        release,
        {"productVersion", "runtimeVersion"},
        "targetRelease",
    )
    require_version(release["productVersion"], "targetRelease.productVersion")
    require_version(release["runtimeVersion"], "targetRelease.runtimeVersion")
    layers = envelope["layerOrder"]
    if not isinstance(layers, list) or not layers:
        raise DomainError("layerOrder must be a non-empty list")
    if any(layer not in SUPPORTED_LAYERS for layer in layers):
        raise DomainError(f"layerOrder contains unsupported layer: {layers}")
    if len(layers) > len(SUPPORTED_LAYERS):
        raise DomainError(f"layerOrder contains too many layers: {len(layers)}")
    if len(set(layers)) != len(layers):
        raise DomainError("layerOrder contains a duplicate layer")
    if "host-platform" in layers and layers[-1] != "host-platform":
        raise DomainError("host-platform must be the last update layer")
    next_updater = _object(envelope["nextUpdaterArtifact"])
    specification = _object(envelope["specification"])
    validate_artifact(next_updater)
    validate_artifact(specification)
    if next_updater["id"] == specification["id"]:
        raise DomainError("bootstrap artifact ids must be distinct")
    if next_updater["relativePath"] == specification["relativePath"]:
        raise DomainError("bootstrap artifact paths must be distinct")
    payload_artifacts = envelope["payloadArtifacts"]
    if not isinstance(payload_artifacts, list) or not payload_artifacts:
        raise DomainError("payloadArtifacts must be a non-empty list")
    bootstrap_paths = {
        next_updater["relativePath"],
        specification["relativePath"],
    }
    seen_paths: set[str] = set()
    seen_ids: set[str] = set()
    for entry in payload_artifacts:
        validate_artifact(_object(entry))
        artifact_entry = _object(entry)
        if artifact_entry["relativePath"] in seen_paths:
            raise DomainError(
                f"payloadArtifacts contains a duplicate path: "
                f"{artifact_entry['relativePath']}"
            )
        if artifact_entry["id"] in seen_ids:
            raise DomainError(
                f"payloadArtifacts contains a duplicate id: {artifact_entry['id']}"
            )
        if artifact_entry["relativePath"] in bootstrap_paths:
            raise DomainError(
                "payloadArtifacts conflicts with a bootstrap-owned path: "
                f"{artifact_entry['relativePath']}"
            )
        seen_paths.add(artifact_entry["relativePath"])
        seen_ids.add(artifact_entry["id"])
    require_canonical_utc(envelope["issuedAt"], "issuedAt")


def validate_artifact(entry: dict[str, Any]) -> None:
    require_exact_keys(
        entry,
        {"id", "relativePath", "sha256", "sizeBytes", "mediaType"},
        "bootstrap artifact",
    )
    require_identifier(entry["id"], "artifact.id")
    require_safe_relative_path(entry["relativePath"], "artifact.relativePath")
    if not isinstance(entry["sha256"], str) or not SHA256.fullmatch(entry["sha256"]):
        raise DomainError("artifact.sha256 must be lowercase SHA-256")
    if (
        not isinstance(entry["sizeBytes"], int)
        or isinstance(entry["sizeBytes"], bool)
        or entry["sizeBytes"] <= 0
    ):
        raise DomainError("artifact.sizeBytes must be a positive integer")
    media_type = entry["mediaType"]
    if (
        not isinstance(media_type, str)
        or media_type.count("/") != 1
        or any(
            not (character.isascii() and (character.isalnum() or character in ".+-/"))
            for character in media_type
        )
    ):
        raise DomainError("artifact.mediaType must be an ASCII type/subtype")


def require_exact_keys(
    value: dict[str, Any],
    expected: set[str],
    owner: str,
) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unknown = sorted(actual - expected)
        raise DomainError(f"{owner} fields differ: missing={missing} unknown={unknown}")


def require_identifier(value: object, field: str) -> None:
    if not isinstance(value, str) or not IDENTIFIER.fullmatch(value):
        raise DomainError(f"{field} is not a stable ASCII identifier: {value}")


def require_version(value: object, field: str) -> None:
    if not isinstance(value, str) or not VERSION.fullmatch(value):
        raise DomainError(f"{field} is not a stable ASCII version: {value}")


def require_canonical_utc(value: object, field: str) -> None:
    if not isinstance(value, str) or not CANONICAL_UTC.fullmatch(value):
        raise DomainError(f"{field} must be canonical UTC YYYY-MM-DDTHH:MM:SSZ")
    try:
        datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError as exc:
        raise DomainError(f"{field} is not a real UTC timestamp: {value}") from exc


def require_safe_relative_path(value: object, field: str) -> None:
    if not isinstance(value, str):
        raise DomainError(f"{field} must be a string")
    path = Path(value)
    if (
        not value
        or not value.startswith("payload/")
        or "\\" in value
        or any(part in {"", ".", ".."} for part in value.split("/"))
        or path.is_absolute()
        or any(
            not (character.isascii() and (character.isalnum() or character in "._/-"))
            for character in value
        )
    ):
        raise DomainError(f"{field} is unsafe: {value}")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _object(value: object) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise DomainError("bootstrap nested value must be an object")
    return value


def _ordered_artifact(entry: dict[str, Any]) -> dict[str, object]:
    return {
        "id": entry["id"],
        "relativePath": entry["relativePath"],
        "sha256": entry["sha256"],
        "sizeBytes": entry["sizeBytes"],
        "mediaType": entry["mediaType"],
    }

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.update_bootstrap_bundle import (
    SHA256,
    require_exact_keys,
    require_identifier,
    require_safe_relative_path,
)

SCHEMA_VERSION = "vitalserver.product-update-specification/v1"
LAYERS = {"container", "guest-runtime", "host-platform"}


def load_product_update_specification(
    path: Path,
    *,
    update_id: str,
    layer_order: list[str],
) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise DomainError(f"product update specification read failed: {error}") from error
    if not isinstance(value, dict):
        raise DomainError("product update specification must be an object")
    artifacts = validate_product_update_specification(
        value,
        update_id=update_id,
        layer_order=layer_order,
    )
    return value, artifacts


def validate_product_update_specification(
    value: dict[str, Any],
    *,
    update_id: str,
    layer_order: list[str],
) -> dict[str, dict[str, Any]]:
    require_exact_keys(
        value,
        {"schemaVersion", "id", "bootstrapEnvelopeId", "layerPlan"},
        "product update specification",
    )
    if value["schemaVersion"] != SCHEMA_VERSION:
        raise DomainError(
            "unsupported product update specification schemaVersion: "
            f"{value['schemaVersion']}"
        )
    require_identifier(value["id"], "product update specification.id")
    if value["bootstrapEnvelopeId"] != update_id:
        raise DomainError(
            "product update specification bootstrapEnvelopeId mismatch "
            f"expected={update_id} actual={value['bootstrapEnvelopeId']}"
        )
    plan = value["layerPlan"]
    if not isinstance(plan, list) or not plan:
        raise DomainError("product update specification layerPlan must be non-empty")
    actual_order: list[str] = []
    artifacts: dict[str, dict[str, Any]] = {}
    seen_layers: set[str] = set()
    for index, raw_layer in enumerate(plan):
        layer = _object(raw_layer, f"layerPlan[{index}]")
        require_exact_keys(
            layer,
            {"layer", "dependsOn", "artifact", "effectExecutor", "rollback"},
            f"layerPlan[{index}]",
        )
        layer_name = layer["layer"]
        if layer_name not in LAYERS or layer_name in seen_layers:
            raise DomainError(f"invalid or duplicate update layer: {layer_name}")
        dependencies = layer["dependsOn"]
        if not isinstance(dependencies, list) or any(
            dependency not in seen_layers for dependency in dependencies
        ):
            raise DomainError(
                f"layer dependencies must refer only to earlier layers: {layer_name}"
            )
        if len(set(dependencies)) != len(dependencies):
            raise DomainError(f"layer dependencies contain duplicates: {layer_name}")
        seen_layers.add(layer_name)
        actual_order.append(layer_name)
        _add_artifact(
            artifacts,
            _artifact(layer["artifact"], f"{layer_name}.artifact"),
        )
        executor = _object(layer["effectExecutor"], f"{layer_name}.effectExecutor")
        require_exact_keys(
            executor,
            {
                "id",
                "relativePath",
                "sha256",
                "sizeBytes",
                "mediaType",
                "configurationArtifact",
            },
            f"{layer_name}.effectExecutor",
        )
        _add_artifact(
            artifacts,
            _artifact(
                {
                    key: executor[key]
                    for key in (
                        "id",
                        "relativePath",
                        "sha256",
                        "sizeBytes",
                        "mediaType",
                    )
                },
                f"{layer_name}.effectExecutor",
            ),
        )
        _add_artifact(
            artifacts,
            _artifact(
                executor["configurationArtifact"],
                f"{layer_name}.effectExecutor.configurationArtifact",
            ),
        )
        rollback = _object(layer["rollback"], f"{layer_name}.rollback")
        require_exact_keys(
            rollback,
            {"state", "artifact", "reason"},
            f"{layer_name}.rollback",
        )
        if rollback["state"] == "available":
            if rollback["artifact"] is None or rollback["reason"] is not None:
                raise DomainError(
                    f"available rollback must declare artifact only: {layer_name}"
                )
            _add_artifact(
                artifacts,
                _artifact(rollback["artifact"], f"{layer_name}.rollback.artifact"),
            )
        elif rollback["state"] == "unsupported":
            if rollback["artifact"] is not None or not isinstance(
                rollback["reason"], str
            ) or not rollback["reason"]:
                raise DomainError(
                    f"unsupported rollback must declare a reason only: {layer_name}"
                )
        else:
            raise DomainError(f"unsupported rollback state: {rollback['state']}")
    if actual_order != layer_order:
        raise DomainError(
            "product update specification layer order mismatch "
            f"expected={layer_order} actual={actual_order}"
        )
    return artifacts


def _artifact(value: object, owner: str) -> dict[str, Any]:
    artifact = _object(value, owner)
    require_exact_keys(
        artifact,
        {"id", "relativePath", "sha256", "sizeBytes", "mediaType"},
        owner,
    )
    require_identifier(artifact["id"], f"{owner}.id")
    require_safe_relative_path(artifact["relativePath"], f"{owner}.relativePath")
    if not isinstance(artifact["sha256"], str) or not SHA256.fullmatch(
        artifact["sha256"]
    ):
        raise DomainError(f"{owner}.sha256 must be lowercase SHA-256")
    if (
        not isinstance(artifact["sizeBytes"], int)
        or isinstance(artifact["sizeBytes"], bool)
        or artifact["sizeBytes"] <= 0
    ):
        raise DomainError(f"{owner}.sizeBytes must be a positive integer")
    media_type = artifact["mediaType"]
    if not isinstance(media_type, str) or media_type.count("/") != 1:
        raise DomainError(f"{owner}.mediaType must be a type/subtype")
    return artifact


def _add_artifact(
    artifacts: dict[str, dict[str, Any]],
    artifact: dict[str, Any],
) -> None:
    path = artifact["relativePath"]
    if path in artifacts:
        raise DomainError(f"product update artifact path is duplicated: {path}")
    if any(existing["id"] == artifact["id"] for existing in artifacts.values()):
        raise DomainError(
            f"product update artifact id is duplicated: {artifact['id']}"
        )
    artifacts[path] = artifact


def _object(value: object, owner: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise DomainError(f"{owner} must be an object")
    return value

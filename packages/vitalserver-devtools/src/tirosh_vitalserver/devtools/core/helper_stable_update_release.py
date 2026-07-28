from __future__ import annotations

import json

from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_stable_update_release_models import (
    HelperStableUpdateArtifactDeclaration,
    HelperStableUpdateLayerRelease,
    HelperStableUpdateReleasePlan,
)
from tirosh_vitalserver.devtools.core.product_update_specification import (
    SCHEMA_VERSION,
    validate_product_update_specification,
)

EFFECT_EXECUTOR_MEDIA_TYPE = (
    "application/vnd.tirosh.vitalserver.update-layer-effect-executor"
)
EFFECT_CONFIGURATION_MEDIA_TYPE = (
    "application/vnd.tirosh.vitalserver.update-layer-effect-configuration+json"
)


def helper_stable_update_specification_document(
    release: HelperStableUpdateReleasePlan,
) -> dict[str, object]:
    """Create the strict specification owned by one Helper release.

    This function consumes declarations only. Filesystem observation and
    payload publication stay outside the pure release-policy boundary.
    """

    for layer_release in release.layers:
        _validate_next_updater_layer_contract(layer_release)

    document: dict[str, object] = {
        "schemaVersion": SCHEMA_VERSION,
        "id": release.specification_id,
        "bootstrapEnvelopeId": release.update_id,
        "layerPlan": [
            _layer_document(layer_release) for layer_release in release.layers
        ],
    }
    validate_product_update_specification(
        document,
        update_id=release.update_id,
        layer_order=[layer_release.layer.value for layer_release in release.layers],
    )
    return document


def encode_helper_stable_update_specification(
    release: HelperStableUpdateReleasePlan,
) -> bytes:
    return (
        json.dumps(
            helper_stable_update_specification_document(release),
            indent=2,
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")


def _layer_document(
    release: HelperStableUpdateLayerRelease,
) -> dict[str, object]:
    executor = release.effect_executor
    rollback = release.rollback
    return {
        "layer": release.layer.value,
        "dependsOn": [dependency.value for dependency in release.depends_on],
        "artifact": _artifact_document(release.artifact),
        "effectExecutor": {
            **_artifact_document(executor.executable),
            "configurationArtifact": _artifact_document(executor.configuration),
        },
        "rollback": {
            "state": rollback.state.value,
            "artifact": (
                _artifact_document(rollback.artifact)
                if rollback.artifact is not None
                else None
            ),
            "reason": rollback.reason,
        },
    }


def _artifact_document(
    artifact: HelperStableUpdateArtifactDeclaration,
) -> dict[str, object]:
    return {
        "id": artifact.artifact_id,
        "relativePath": artifact.relative_path,
        "sha256": artifact.sha256,
        "sizeBytes": artifact.size_bytes,
        "mediaType": artifact.media_type,
    }


def _validate_next_updater_layer_contract(
    release: HelperStableUpdateLayerRelease,
) -> None:
    executor = release.effect_executor
    if executor.executable.media_type != EFFECT_EXECUTOR_MEDIA_TYPE:
        raise DomainError(
            f"{release.layer.value} effect executor media type is unsupported: "
            f"{executor.executable.media_type}"
        )
    if executor.configuration.media_type != EFFECT_CONFIGURATION_MEDIA_TYPE:
        raise DomainError(
            f"{release.layer.value} effect configuration media type is unsupported: "
            f"{executor.configuration.media_type}"
        )
    declarations = [
        release.artifact,
        executor.executable,
        executor.configuration,
    ]
    if release.rollback.artifact is not None:
        declarations.append(release.rollback.artifact)
    digests = [artifact.sha256 for artifact in declarations]
    if len(set(digests)) != len(digests):
        raise DomainError(
            f"{release.layer.value} artifact digests must be distinct by role"
        )

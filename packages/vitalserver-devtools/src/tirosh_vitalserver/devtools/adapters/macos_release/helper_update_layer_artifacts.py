from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from tirosh_vitalserver.devtools.application.inputs import (
    HelperStableUpdateLayerArtifactInput,
    MaterializedHelperUpdatePayload,
)
from tirosh_vitalserver.devtools.core.errors import DomainError
from tirosh_vitalserver.devtools.core.helper_effect_configuration import (
    validate_guest_owner_effect_configuration,
    validate_host_platform_effect_configuration,
)
from tirosh_vitalserver.devtools.core.helper_stable_update_release import (
    EFFECT_CONFIGURATION_MEDIA_TYPE,
    EFFECT_EXECUTOR_MEDIA_TYPE,
)
from tirosh_vitalserver.devtools.core.helper_stable_update_release_models import (
    HelperStableUpdateArtifactDeclaration,
    HelperStableUpdateEffectExecutorDeclaration,
    HelperStableUpdateLayer,
    HelperStableUpdateLayerRelease,
    HelperStableUpdateRollbackPlan,
)


@contextmanager
def materialized_helper_update_payload(
    sources: tuple[HelperStableUpdateLayerArtifactInput, ...],
) -> Iterator[MaterializedHelperUpdatePayload]:
    expected_layers = tuple(HelperStableUpdateLayer)
    actual_layers = tuple(source.layer for source in sources)
    if actual_layers != expected_layers:
        raise DomainError(
            "Helper stable update layers must be supplied exactly once in order "
            f"expected={[layer.value for layer in expected_layers]} "
            f"actual={[layer.value for layer in actual_layers]}"
        )

    with tempfile.TemporaryDirectory(prefix="helper-stable-update-payload-") as temp:
        root = Path(temp)
        releases: list[HelperStableUpdateLayerRelease] = []
        dependencies: list[HelperStableUpdateLayer] = []
        for source in sources:
            layer = source.layer
            effect_executor_id, effect_configuration = (
                _materialize_effect_configuration(
                    source.effect_configuration,
                    root / f"payload/layers/{layer.value}/effect-configuration.json",
                    payload_root=root,
                    layer=layer,
                )
            )
            artifact = _copy_and_observe(
                source.artifact,
                root / f"payload/layers/{layer.value}/artifact",
                payload_root=root,
                artifact_id=f"helper-{layer.value}-artifact",
                media_type=source.artifact_media_type,
                owner=f"{layer.value} artifact",
            )
            effect_executor = _copy_and_observe(
                source.effect_executor,
                root / f"payload/layers/{layer.value}/effect-executor",
                payload_root=root,
                artifact_id=effect_executor_id,
                media_type=EFFECT_EXECUTOR_MEDIA_TYPE,
                owner=f"{layer.value} effect executor",
                executable=True,
            )
            rollback = _copy_and_observe(
                source.rollback_artifact,
                root / f"payload/layers/{layer.value}/rollback-artifact",
                payload_root=root,
                artifact_id=f"helper-{layer.value}-rollback",
                media_type=source.rollback_media_type,
                owner=f"{layer.value} rollback artifact",
            )
            releases.append(
                HelperStableUpdateLayerRelease(
                    layer=layer,
                    depends_on=tuple(dependencies),
                    artifact=artifact,
                    effect_executor=HelperStableUpdateEffectExecutorDeclaration(
                        executable=effect_executor,
                        configuration=effect_configuration,
                    ),
                    rollback=HelperStableUpdateRollbackPlan.available(rollback),
                )
            )
            dependencies.append(layer)
        yield MaterializedHelperUpdatePayload(root=root, layers=tuple(releases))


def _materialize_effect_configuration(
    source: Path,
    destination: Path,
    *,
    payload_root: Path,
    layer: HelperStableUpdateLayer,
) -> tuple[str, HelperStableUpdateArtifactDeclaration]:
    """Read, validate, and materialize the effect configuration from one read.

    The validated bytes are exactly the bytes written to the payload and the
    bytes whose digest and size are recorded, so a source change between
    validation and materialization cannot desynchronize the signed closure.
    """
    owner = f"{layer.value} effect configuration"
    raw = _read_effect_configuration_bytes(source, owner)
    effect_executor_id = _effect_executor_id_from_bytes(raw, layer, owner)
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        destination.write_bytes(raw)
    except OSError as error:
        raise DomainError(
            f"{owner} materialization failed path={destination}: {error}"
        ) from error
    return effect_executor_id, HelperStableUpdateArtifactDeclaration(
        artifact_id=f"helper-{layer.value}-effect-configuration",
        relative_path=destination.relative_to(payload_root).as_posix(),
        sha256=hashlib.sha256(raw).hexdigest(),
        size_bytes=len(raw),
        media_type=EFFECT_CONFIGURATION_MEDIA_TYPE,
    )


def _read_effect_configuration_bytes(path: Path, owner: str) -> bytes:
    _require_regular_file(path, owner)
    try:
        return path.read_bytes()
    except OSError as error:
        raise DomainError(f"{owner} read failed path={path}: {error}") from error


def _effect_executor_id_from_bytes(
    raw: bytes,
    layer: HelperStableUpdateLayer,
    owner: str,
) -> str:
    value = _decode_effect_configuration(raw, owner)
    if layer is HelperStableUpdateLayer.HOST_PLATFORM:
        return validate_host_platform_effect_configuration(value, owner=owner)
    return validate_guest_owner_effect_configuration(
        value,
        expected_layer=layer.value,
        owner=owner,
    ).effect_executor_id


def _decode_effect_configuration(raw: bytes, owner: str) -> dict[str, object]:
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise DomainError(f"{owner} decode failed: {error}") from error
    try:
        value = json.loads(text)
    except json.JSONDecodeError as error:
        raise DomainError(f"{owner} JSON parse failed: {error}") from error
    if not isinstance(value, dict):
        raise DomainError(f"{owner} must be a JSON object")
    return value


def _copy_and_observe(
    source: Path,
    destination: Path,
    *,
    payload_root: Path,
    artifact_id: str,
    media_type: str,
    owner: str,
    executable: bool = False,
) -> HelperStableUpdateArtifactDeclaration:
    _require_regular_file(source, owner)
    if not media_type:
        raise DomainError(f"{owner} media type must not be empty")
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        shutil.copyfile(source, destination)
        if executable:
            destination.chmod(0o755)
        size_bytes = destination.stat().st_size
        digest = _sha256(destination)
    except OSError as error:
        raise DomainError(
            f"{owner} materialization failed source={source} "
            f"destination={destination}: {error}"
        ) from error
    return HelperStableUpdateArtifactDeclaration(
        artifact_id=artifact_id,
        relative_path=destination.relative_to(payload_root).as_posix(),
        sha256=digest,
        size_bytes=size_bytes,
        media_type=media_type,
    )


def _require_regular_file(path: Path, owner: str) -> None:
    try:
        mode = os.lstat(path).st_mode
    except OSError as error:
        raise DomainError(f"{owner} inspection failed path={path}: {error}") from error
    if not stat.S_ISREG(mode):
        raise DomainError(f"{owner} must be a regular file: {path}")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        raise DomainError(
            f"artifact digest read failed path={path}: {error}"
        ) from error
    return digest.hexdigest()

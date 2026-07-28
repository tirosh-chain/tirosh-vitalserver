from __future__ import annotations

import hashlib
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
                artifact_id=f"helper-{layer.value}-effect-executor",
                media_type=EFFECT_EXECUTOR_MEDIA_TYPE,
                owner=f"{layer.value} effect executor",
                executable=True,
            )
            effect_configuration = _copy_and_observe(
                source.effect_configuration,
                root / f"payload/layers/{layer.value}/effect-configuration.json",
                payload_root=root,
                artifact_id=f"helper-{layer.value}-effect-configuration",
                media_type=EFFECT_CONFIGURATION_MEDIA_TYPE,
                owner=f"{layer.value} effect configuration",
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

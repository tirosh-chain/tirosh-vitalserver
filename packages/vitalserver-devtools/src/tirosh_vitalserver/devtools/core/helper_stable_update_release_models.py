from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum


class HelperStableUpdateLayer(StrEnum):
    CONTAINER = "container"
    GUEST_RUNTIME = "guest-runtime"
    HOST_PLATFORM = "host-platform"


@dataclass(frozen=True)
class HelperStableUpdateArtifactDeclaration:
    """Immutable bytes already observed by the release-composition boundary."""

    artifact_id: str
    relative_path: str
    sha256: str
    size_bytes: int
    media_type: str


@dataclass(frozen=True)
class HelperStableUpdateEffectExecutorDeclaration:
    executable: HelperStableUpdateArtifactDeclaration
    configuration: HelperStableUpdateArtifactDeclaration


class HelperStableUpdateRollbackAvailability(StrEnum):
    AVAILABLE = "available"
    UNSUPPORTED = "unsupported"


@dataclass(frozen=True)
class HelperStableUpdateRollbackPlan:
    state: HelperStableUpdateRollbackAvailability
    artifact: HelperStableUpdateArtifactDeclaration | None
    reason: str | None

    @classmethod
    def available(
        cls,
        artifact: HelperStableUpdateArtifactDeclaration,
    ) -> HelperStableUpdateRollbackPlan:
        return cls(
            state=HelperStableUpdateRollbackAvailability.AVAILABLE,
            artifact=artifact,
            reason=None,
        )

    @classmethod
    def unsupported(cls, reason: str) -> HelperStableUpdateRollbackPlan:
        return cls(
            state=HelperStableUpdateRollbackAvailability.UNSUPPORTED,
            artifact=None,
            reason=reason,
        )


@dataclass(frozen=True)
class HelperStableUpdateLayerRelease:
    layer: HelperStableUpdateLayer
    depends_on: tuple[HelperStableUpdateLayer, ...]
    artifact: HelperStableUpdateArtifactDeclaration
    effect_executor: HelperStableUpdateEffectExecutorDeclaration
    rollback: HelperStableUpdateRollbackPlan


@dataclass(frozen=True)
class HelperStableUpdateReleasePlan:
    update_id: str
    specification_id: str
    layers: tuple[HelperStableUpdateLayerRelease, ...]

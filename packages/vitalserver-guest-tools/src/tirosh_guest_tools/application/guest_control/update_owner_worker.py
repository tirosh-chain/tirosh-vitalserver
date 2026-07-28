from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from tirosh_guest_tools.application.guest_control.container_image_set import (
    ContainerImageSetStateOwner,
)
from tirosh_guest_tools.application.guest_control.guest_runtime_release import (
    GuestRuntimeReleaseStateOwner,
)
from tirosh_guest_tools.application.guest_control.ports import Clock
from tirosh_guest_tools.domain.container_image_set import (
    ContainerImageSetFailure,
    ContainerImageSetOperation,
    ContainerImageSetOperationState,
    transition_container_image_set_operation,
)
from tirosh_guest_tools.domain.guest_runtime_release import (
    GuestRuntimeReleaseFailure,
    GuestRuntimeReleaseOperation,
    GuestRuntimeReleaseOperationState,
    transition_guest_runtime_release_operation,
)


class UpdateArtifactUnavailable(RuntimeError):
    pass


class UpdateEffectFailed(RuntimeError):
    pass


class UpdateArtifactResolver(Protocol):
    def resolve(self, *, kind: str, digest: str) -> Path:
        raise NotImplementedError


class ContainerImageSetEffect(Protocol):
    def reconcile(self, archive: Path) -> None:
        raise NotImplementedError


class GuestRuntimeReleaseEffect(Protocol):
    def activate(self, operation: GuestRuntimeReleaseOperation, archive: Path) -> None:
        raise NotImplementedError


class ContainerImageSetWorkOwner(ContainerImageSetStateOwner, Protocol):
    def list_container_image_set_operations(
        self,
        states: frozenset[ContainerImageSetOperationState],
    ) -> list[ContainerImageSetOperation]:
        raise NotImplementedError


class GuestRuntimeReleaseWorkOwner(GuestRuntimeReleaseStateOwner, Protocol):
    def list_guest_runtime_release_operations(
        self,
        states: frozenset[GuestRuntimeReleaseOperationState],
    ) -> list[GuestRuntimeReleaseOperation]:
        raise NotImplementedError


@dataclass(frozen=True)
class GuestUpdateOwnerWorker:
    """Claims durable Guest-owned update operations and executes explicit effects."""

    container_owner: ContainerImageSetWorkOwner
    guest_runtime_owner: GuestRuntimeReleaseWorkOwner
    artifacts: UpdateArtifactResolver
    container_effect: ContainerImageSetEffect
    guest_runtime_effect: GuestRuntimeReleaseEffect
    clock: Clock

    def recover_and_run_pending(self) -> None:
        self._mark_interrupted_container_work_unavailable()
        self._mark_interrupted_guest_runtime_work_unavailable()
        for operation in self.container_owner.list_container_image_set_operations(
            frozenset({ContainerImageSetOperationState.PENDING})
        ):
            self.run_container(operation.operation_id)
        for operation in self.guest_runtime_owner.list_guest_runtime_release_operations(
            frozenset({GuestRuntimeReleaseOperationState.PENDING})
        ):
            self.run_guest_runtime(operation.operation_id)

    def run_container(self, operation_id: str) -> ContainerImageSetOperation:
        pending = self.container_owner.get_operation(operation_id)
        if pending is None:
            raise UpdateEffectFailed(
                f"Container image-set operation is missing: {operation_id}."
            )
        running = transition_container_image_set_operation(
            pending,
            state=ContainerImageSetOperationState.RUNNING,
            updated_at=self.clock.now(),
        )
        self.container_owner.record_container_image_set_transition(running)
        try:
            archive = self.artifacts.resolve(
                kind="container-image-set",
                digest=running.target.digest,
            )
            self.container_effect.reconcile(archive)
        except UpdateArtifactUnavailable as error:
            terminal = transition_container_image_set_operation(
                running,
                state=ContainerImageSetOperationState.UNAVAILABLE,
                updated_at=self.clock.now(),
                failure=ContainerImageSetFailure(
                    kind="containerImageSetArtifactUnavailable",
                    message=str(error),
                ),
            )
        except Exception as error:
            terminal = transition_container_image_set_operation(
                running,
                state=ContainerImageSetOperationState.FAILED,
                updated_at=self.clock.now(),
                failure=ContainerImageSetFailure(
                    kind="containerImageSetEffectFailed",
                    message=str(error),
                ),
            )
        else:
            terminal = transition_container_image_set_operation(
                running,
                state=ContainerImageSetOperationState.SUCCEEDED,
                updated_at=self.clock.now(),
            )
        self.container_owner.record_container_image_set_transition(terminal)
        return terminal

    def run_guest_runtime(self, operation_id: str) -> GuestRuntimeReleaseOperation:
        pending = self.guest_runtime_owner.get_guest_runtime_release_operation(
            operation_id
        )
        if pending is None:
            raise UpdateEffectFailed(
                f"Guest Runtime release operation is missing: {operation_id}."
            )
        running = transition_guest_runtime_release_operation(
            pending,
            state=GuestRuntimeReleaseOperationState.RUNNING,
            updated_at=self.clock.now(),
        )
        self.guest_runtime_owner.record_guest_runtime_release_transition(running)
        try:
            archive = self.artifacts.resolve(
                kind="guest-runtime-release",
                digest=running.target.digest,
            )
            self.guest_runtime_effect.activate(running, archive)
        except UpdateArtifactUnavailable as error:
            terminal = transition_guest_runtime_release_operation(
                running,
                state=GuestRuntimeReleaseOperationState.UNAVAILABLE,
                updated_at=self.clock.now(),
                failure=GuestRuntimeReleaseFailure(
                    kind="guestRuntimeReleaseArtifactUnavailable",
                    message=str(error),
                ),
            )
        except Exception as error:
            terminal = transition_guest_runtime_release_operation(
                running,
                state=GuestRuntimeReleaseOperationState.FAILED,
                updated_at=self.clock.now(),
                failure=GuestRuntimeReleaseFailure(
                    kind="guestRuntimeReleaseEffectFailed",
                    message=str(error),
                ),
            )
        else:
            terminal = transition_guest_runtime_release_operation(
                running,
                state=GuestRuntimeReleaseOperationState.SUCCEEDED,
                updated_at=self.clock.now(),
            )
        self.guest_runtime_owner.record_guest_runtime_release_transition(terminal)
        return terminal

    def _mark_interrupted_container_work_unavailable(self) -> None:
        operations = self.container_owner.list_container_image_set_operations(
            frozenset({ContainerImageSetOperationState.RUNNING})
        )
        for operation in operations:
            unavailable = transition_container_image_set_operation(
                operation,
                state=ContainerImageSetOperationState.UNAVAILABLE,
                updated_at=self.clock.now(),
                failure=ContainerImageSetFailure(
                    kind="containerImageSetWorkerInterrupted",
                    message=(
                        "Guest restarted while the container image-set effect "
                        "outcome was unknown."
                    ),
                ),
            )
            self.container_owner.record_container_image_set_transition(unavailable)

    def _mark_interrupted_guest_runtime_work_unavailable(self) -> None:
        operations = self.guest_runtime_owner.list_guest_runtime_release_operations(
            frozenset({GuestRuntimeReleaseOperationState.RUNNING})
        )
        for operation in operations:
            unavailable = transition_guest_runtime_release_operation(
                operation,
                state=GuestRuntimeReleaseOperationState.UNAVAILABLE,
                updated_at=self.clock.now(),
                failure=GuestRuntimeReleaseFailure(
                    kind="guestRuntimeReleaseWorkerInterrupted",
                    message=(
                        "Guest restarted while the Guest Runtime release effect "
                        "outcome was unknown."
                    ),
                ),
            )
            self.guest_runtime_owner.record_guest_runtime_release_transition(
                unavailable
            )

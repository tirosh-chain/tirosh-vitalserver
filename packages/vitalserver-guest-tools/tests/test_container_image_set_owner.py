from __future__ import annotations

from datetime import UTC, datetime, timedelta
from http import HTTPStatus

import pytest

from tirosh_guest_tools.adapters.inbound.guest_control_api import route_request
from tirosh_guest_tools.adapters.outbound.sqlite_control import SQLiteControlRepository
from tirosh_guest_tools.adapters.outbound.sqlite_control.migrations import _upgrade_0001
from tirosh_guest_tools.adapters.outbound.sqlite_control.repository import (
    build_sqlite_engine,
)
from tirosh_guest_tools.application.guest_control.container_image_set import (
    ContainerImageSetUseCases,
)
from tirosh_guest_tools.domain.container_image_set import (
    ContainerImageSet,
    ContainerImageSetConflictError,
    ContainerImageSetFailure,
    ContainerImageSetOperationState,
    transition_container_image_set_operation,
)

DIGEST_A = "sha256:" + ("a" * 64)
DIGEST_B = "sha256:" + ("b" * 64)


class FixedClock:
    def __init__(self, now: datetime) -> None:
        self.value = now

    def now(self) -> datetime:
        return self.value


class FixedOperationIds:
    def new_operation_id(self, *, service: str, command: str) -> str:
        return f"{service}-{command}-1"


def test_missing_owner_is_an_explicit_unavailable_read() -> None:
    clock = FixedClock(datetime(2026, 7, 29, tzinfo=UTC))
    usecases = ContainerImageSetUseCases(
        state_owner=None,
        operation_ids=FixedOperationIds(),
        clock=clock,
    )

    read = usecases.read_current()

    assert read.state == "unavailable"
    assert read.image_set is None
    assert read.failure is not None
    assert read.failure.kind == "containerImageSetOwnerUnavailable"


def test_sqlite_owner_accepts_pending_apply_with_atomic_current_identity_cas(
    tmp_path,
) -> None:
    now = datetime(2026, 7, 29, tzinfo=UTC)
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    repository.provision_current_container_image_set(
        ContainerImageSet.validated("images-0.2.1", DIGEST_A),
        observed_at=now,
    )
    usecases = ContainerImageSetUseCases(
        state_owner=repository,
        operation_ids=FixedOperationIds(),
        clock=FixedClock(now),
    )

    operation = usecases.apply(
        {
            "expectedCurrentIdentity": "images-0.2.1",
            "target": {"identity": "images-0.2.2", "digest": DIGEST_B},
        }
    )

    assert operation.state == ContainerImageSetOperationState.PENDING
    assert repository.read_current().identity == "images-0.2.1"
    assert repository.get_operation(operation.operation_id) == operation

    with pytest.raises(ContainerImageSetConflictError) as failure:
        usecases.rollback(
            {
                "expectedCurrentIdentity": "images-stale",
                "target": {"identity": "images-0.2.0", "digest": DIGEST_A},
            }
        )
    assert failure.value.kind == "containerImageSetRevisionConflict"


def test_existing_control_schema_is_explicitly_migrated_to_image_set_owner(
    tmp_path,
) -> None:
    database = tmp_path / "control.sqlite"
    engine = build_sqlite_engine(database)
    with engine.begin() as connection:
        _upgrade_0001(connection)
    engine.dispose()
    repository = SQLiteControlRepository(database)

    repository.migrate_schema()

    repository.check_ready()
    read = ContainerImageSetUseCases(
        state_owner=repository,
        operation_ids=FixedOperationIds(),
        clock=FixedClock(datetime(2026, 7, 29, tzinfo=UTC)),
    ).read_current()
    assert read.state == "unavailable"
    assert read.failure is not None
    assert read.failure.kind == "containerImageSetCurrentMissing"


def test_succeeded_transition_activates_target_and_identity_digest_is_immutable(
    tmp_path,
) -> None:
    now = datetime(2026, 7, 29, tzinfo=UTC)
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    repository.provision_current_container_image_set(
        ContainerImageSet.validated("images-0.2.1", DIGEST_A),
        observed_at=now,
    )
    usecases = ContainerImageSetUseCases(
        state_owner=repository,
        operation_ids=FixedOperationIds(),
        clock=FixedClock(now),
    )
    pending = usecases.apply(
        {
            "expectedCurrentIdentity": "images-0.2.1",
            "target": {"identity": "images-0.2.2", "digest": DIGEST_B},
        }
    )
    running = transition_container_image_set_operation(
        pending,
        state=ContainerImageSetOperationState.RUNNING,
        updated_at=now + timedelta(seconds=1),
    )
    repository.record_container_image_set_transition(running)
    succeeded = transition_container_image_set_operation(
        running,
        state=ContainerImageSetOperationState.SUCCEEDED,
        updated_at=now + timedelta(seconds=2),
    )
    repository.record_container_image_set_transition(succeeded)

    assert repository.read_current() == ContainerImageSet(
        identity="images-0.2.2",
        digest=DIGEST_B,
    )

    with pytest.raises(ContainerImageSetConflictError) as failure:
        repository.provision_current_container_image_set(
            ContainerImageSet.validated("images-0.2.2", DIGEST_A),
            observed_at=now + timedelta(seconds=3),
        )
    assert failure.value.kind == "containerImageSetIdentityDigestConflict"


def test_failed_and_unavailable_are_persisted_as_distinct_terminal_states(
    tmp_path,
) -> None:
    now = datetime(2026, 7, 29, tzinfo=UTC)
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    repository.provision_current_container_image_set(
        ContainerImageSet.validated("images-0.2.1", DIGEST_A),
        observed_at=now,
    )
    usecases = ContainerImageSetUseCases(
        state_owner=repository,
        operation_ids=FixedOperationIds(),
        clock=FixedClock(now),
    )
    pending = usecases.rollback(
        {
            "expectedCurrentIdentity": "images-0.2.1",
            "target": {"identity": "images-0.2.0", "digest": DIGEST_B},
        }
    )
    unavailable = transition_container_image_set_operation(
        pending,
        state=ContainerImageSetOperationState.UNAVAILABLE,
        updated_at=now + timedelta(seconds=1),
        failure=ContainerImageSetFailure(
            kind="containerExecutorUnavailable",
            message="No container layer effect executor is configured.",
        ),
    )

    repository.record_container_image_set_transition(unavailable)

    persisted = repository.get_operation(pending.operation_id)
    assert persisted is not None
    assert persisted.state == ContainerImageSetOperationState.UNAVAILABLE
    assert persisted.failure is not None
    assert persisted.failure.kind == "containerExecutorUnavailable"
    assert repository.read_current().identity == "images-0.2.1"


class UnavailableContainerImageSetRouteUseCases:
    def get_current_container_image_set(self):
        usecases = ContainerImageSetUseCases(
            state_owner=None,
            operation_ids=FixedOperationIds(),
            clock=FixedClock(datetime(2026, 7, 29, tzinfo=UTC)),
        )
        return usecases.read_current()


def test_guest_api_preserves_unavailable_current_state_document() -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/container-image-set",
        usecases=UnavailableContainerImageSetRouteUseCases(),  # type: ignore[arg-type]
    )

    assert status == HTTPStatus.SERVICE_UNAVAILABLE
    assert document["state"] == "unavailable"
    assert document["imageSet"] is None
    assert document["failure"]["kind"] == "containerImageSetOwnerUnavailable"

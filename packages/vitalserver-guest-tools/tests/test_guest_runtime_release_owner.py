from __future__ import annotations

from datetime import UTC, datetime, timedelta
from http import HTTPStatus

import pytest

from tirosh_guest_tools.adapters.inbound.guest_control_api import route_request
from tirosh_guest_tools.adapters.outbound.sqlite_control import SQLiteControlRepository
from tirosh_guest_tools.adapters.outbound.sqlite_control.migrations import (
    _upgrade_0001,
    _upgrade_0002,
)
from tirosh_guest_tools.adapters.outbound.sqlite_control.repository import (
    build_sqlite_engine,
)
from tirosh_guest_tools.application.guest_control.guest_runtime_release import (
    GuestRuntimeReleaseUseCases,
)
from tirosh_guest_tools.domain.guest_runtime_release import (
    GuestRuntimeRelease,
    GuestRuntimeReleaseConflictError,
    GuestRuntimeReleaseFailure,
    GuestRuntimeReleaseOperationState,
    transition_guest_runtime_release_operation,
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


def release(identity: str, archive: str, digest: str) -> GuestRuntimeRelease:
    return GuestRuntimeRelease.validated(identity, archive, digest)


def owner(tmp_path) -> tuple[SQLiteControlRepository, datetime]:
    now = datetime(2026, 7, 29, tzinfo=UTC)
    repository = SQLiteControlRepository(tmp_path / "control.sqlite")
    repository.migrate_schema()
    repository.provision_active_guest_runtime_release(
        release("guest-0.2.1", "releases/guest-0.2.1.tar", DIGEST_A),
        observed_at=now,
    )
    return repository, now


def usecases(
    repository: SQLiteControlRepository,
    now: datetime,
) -> GuestRuntimeReleaseUseCases:
    return GuestRuntimeReleaseUseCases(
        state_owner=repository,
        operation_ids=FixedOperationIds(),
        clock=FixedClock(now),
    )


def test_missing_owner_is_explicit_unavailable_active_release() -> None:
    read = GuestRuntimeReleaseUseCases(
        state_owner=None,
        operation_ids=FixedOperationIds(),
        clock=FixedClock(datetime(2026, 7, 29, tzinfo=UTC)),
    ).read_active()

    assert read.state == "unavailable"
    assert read.release is None
    assert read.failure is not None
    assert read.failure.kind == "guestRuntimeReleaseOwnerUnavailable"


def test_existing_0002_control_schema_migrates_without_guessing_active_release(
    tmp_path,
) -> None:
    database = tmp_path / "control.sqlite"
    engine = build_sqlite_engine(database)
    with engine.begin() as connection:
        _upgrade_0001(connection)
        _upgrade_0002(connection)
    engine.dispose()
    repository = SQLiteControlRepository(database)

    repository.migrate_schema()

    repository.check_ready()
    read = usecases(
        repository,
        datetime(2026, 7, 29, tzinfo=UTC),
    ).read_active()
    assert read.state == "unavailable"
    assert read.failure is not None
    assert read.failure.kind == "guestRuntimeReleaseActiveMissing"


def test_apply_is_pending_and_expected_active_identity_is_atomic_cas(
    tmp_path,
) -> None:
    repository, now = owner(tmp_path)
    application = usecases(repository, now)

    pending = application.apply(
        {
            "expectedActiveIdentity": "guest-0.2.1",
            "target": {
                "identity": "guest-0.2.2",
                "archive": "releases/guest-0.2.2.tar",
                "digest": DIGEST_B,
            },
        }
    )

    assert pending.state == GuestRuntimeReleaseOperationState.PENDING
    assert repository.read_active_guest_runtime_release().identity == "guest-0.2.1"
    assert repository.get_guest_runtime_release_operation(
        pending.operation_id
    ) == pending

    with pytest.raises(GuestRuntimeReleaseConflictError) as failure:
        application.rollback(
            {
                "expectedActiveIdentity": "guest-stale",
                "target": {
                    "identity": "guest-0.2.0",
                    "archive": "releases/guest-0.2.0.tar",
                    "digest": DIGEST_A,
                },
            }
        )
    assert failure.value.kind == "guestRuntimeReleaseRevisionConflict"


def test_only_succeeded_transition_changes_active_release(tmp_path) -> None:
    repository, now = owner(tmp_path)
    pending = usecases(repository, now).apply(
        {
            "expectedActiveIdentity": "guest-0.2.1",
            "target": {
                "identity": "guest-0.2.2",
                "archive": "releases/guest-0.2.2.tar",
                "digest": DIGEST_B,
            },
        }
    )
    running = transition_guest_runtime_release_operation(
        pending,
        state=GuestRuntimeReleaseOperationState.RUNNING,
        updated_at=now + timedelta(seconds=1),
    )
    repository.record_guest_runtime_release_transition(running)
    assert repository.read_active_guest_runtime_release().identity == "guest-0.2.1"
    succeeded = transition_guest_runtime_release_operation(
        running,
        state=GuestRuntimeReleaseOperationState.SUCCEEDED,
        updated_at=now + timedelta(seconds=2),
    )

    repository.record_guest_runtime_release_transition(succeeded)

    assert repository.read_active_guest_runtime_release() == release(
        "guest-0.2.2",
        "releases/guest-0.2.2.tar",
        DIGEST_B,
    )


def test_unavailable_operation_remains_terminal_without_active_change(tmp_path) -> None:
    repository, now = owner(tmp_path)
    pending = usecases(repository, now).rollback(
        {
            "expectedActiveIdentity": "guest-0.2.1",
            "target": {
                "identity": "guest-0.2.0",
                "archive": "releases/guest-0.2.0.tar",
                "digest": DIGEST_B,
            },
        }
    )
    unavailable = transition_guest_runtime_release_operation(
        pending,
        state=GuestRuntimeReleaseOperationState.UNAVAILABLE,
        updated_at=now + timedelta(seconds=1),
        failure=GuestRuntimeReleaseFailure(
            kind="guestRuntimeExecutorUnavailable",
            message="No Guest Runtime release effect executor is configured.",
        ),
    )

    repository.record_guest_runtime_release_transition(unavailable)

    persisted = repository.get_guest_runtime_release_operation(
        pending.operation_id
    )
    assert persisted is not None
    assert persisted.state == GuestRuntimeReleaseOperationState.UNAVAILABLE
    assert repository.read_active_guest_runtime_release().identity == "guest-0.2.1"


def test_release_identity_and_archive_references_are_immutable(tmp_path) -> None:
    repository, now = owner(tmp_path)

    with pytest.raises(GuestRuntimeReleaseConflictError) as identity_failure:
        repository.provision_active_guest_runtime_release(
            release("guest-0.2.1", "releases/other.tar", DIGEST_B),
            observed_at=now,
        )
    assert identity_failure.value.kind == "guestRuntimeReleaseIdentityConflict"

    with pytest.raises(GuestRuntimeReleaseConflictError) as archive_failure:
        usecases(repository, now).apply(
            {
                "expectedActiveIdentity": "guest-0.2.1",
                "target": {
                    "identity": "guest-other",
                    "archive": "releases/guest-0.2.1.tar",
                    "digest": DIGEST_A,
                },
            }
        )
    assert archive_failure.value.kind == "guestRuntimeReleaseArchiveConflict"


class UnavailableGuestRuntimeReleaseRouteUseCases:
    def get_active_guest_runtime_release(self):
        return GuestRuntimeReleaseUseCases(
            state_owner=None,
            operation_ids=FixedOperationIds(),
            clock=FixedClock(datetime(2026, 7, 29, tzinfo=UTC)),
        ).read_active()


def test_guest_api_preserves_unavailable_active_release_document() -> None:
    status, document = route_request(
        method="GET",
        path="/runtime/guest-runtime-release",
        usecases=UnavailableGuestRuntimeReleaseRouteUseCases(),  # type: ignore[arg-type]
    )

    assert status == HTTPStatus.SERVICE_UNAVAILABLE
    assert document["state"] == "unavailable"
    assert document["release"] is None
    assert document["failure"]["kind"] == "guestRuntimeReleaseOwnerUnavailable"

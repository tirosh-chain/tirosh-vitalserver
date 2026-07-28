from __future__ import annotations

import hashlib
import io
import tarfile
from datetime import UTC, datetime
from http import HTTPStatus
from pathlib import Path

import pytest

from tirosh_guest_tools.adapters.inbound.guest_control_api import route_request
from tirosh_guest_tools.adapters.outbound.sqlite_control import (
    SQLiteControlRepository,
)
from tirosh_guest_tools.adapters.outbound.update_artifacts import (
    AtomicGuestRuntimeReleaseEffect,
    ImmutableUpdateArtifactStore,
)
from tirosh_guest_tools.application.guest_control.container_image_set import (
    ContainerImageSetUseCases,
)
from tirosh_guest_tools.application.guest_control.guest_runtime_release import (
    GuestRuntimeReleaseUseCases,
)
from tirosh_guest_tools.application.guest_control.update_owner_worker import (
    GuestUpdateOwnerWorker,
    UpdateEffectFailed,
)
from tirosh_guest_tools.domain.container_image_set import (
    ContainerImageSet,
    ContainerImageSetOperationState,
    transition_container_image_set_operation,
)
from tirosh_guest_tools.domain.guest_runtime_release import (
    GuestRuntimeRelease,
    GuestRuntimeReleaseOperationState,
)


class Clock:
    def now(self) -> datetime:
        return datetime(2026, 7, 29, 12, 0, tzinfo=UTC)


class Ids:
    value = 0

    def new_operation_id(self, *, service: str, command: str) -> str:
        self.value += 1
        return f"{service}-{command}-{self.value}"


class ContainerEffect:
    def __init__(self) -> None:
        self.archives: list[Path] = []

    def reconcile(self, archive: Path) -> None:
        self.archives.append(archive)


class RuntimeEffect:
    def __init__(self) -> None:
        self.archives: list[Path] = []

    def activate(self, operation, archive: Path) -> None:
        self.archives.append(archive)


def digest(content: bytes) -> str:
    return "sha256:" + hashlib.sha256(content).hexdigest()


def fixture(tmp_path):
    now = Clock().now()
    owner = SQLiteControlRepository(tmp_path / "control.sqlite")
    owner.migrate_schema()
    initial_content = b"initial"
    owner.provision_current_container_image_set(
        ContainerImageSet.validated("images-0.2.1", digest(initial_content)),
        observed_at=now,
    )
    owner.provision_active_guest_runtime_release(
        GuestRuntimeRelease.validated(
            "guest-0.2.1",
            "releases/guest-0.2.1.tar",
            digest(initial_content),
        ),
        observed_at=now,
    )
    artifacts = ImmutableUpdateArtifactStore(tmp_path / "artifacts")
    container_effect = ContainerEffect()
    runtime_effect = RuntimeEffect()
    worker = GuestUpdateOwnerWorker(
        container_owner=owner,
        guest_runtime_owner=owner,
        artifacts=artifacts,
        container_effect=container_effect,
        guest_runtime_effect=runtime_effect,
        clock=Clock(),
    )
    return owner, artifacts, container_effect, runtime_effect, worker


def test_worker_claims_container_operation_and_only_then_activates_target(
    tmp_path,
) -> None:
    owner, artifacts, effect, _, worker = fixture(tmp_path)
    content = b"docker image archive"
    target_digest = digest(content)
    artifacts.import_bytes(
        kind="container-image-set",
        digest=target_digest,
        content=content,
    )
    operation = ContainerImageSetUseCases(
        state_owner=owner,
        operation_ids=Ids(),
        clock=Clock(),
    ).apply(
        {
            "expectedCurrentIdentity": "images-0.2.1",
            "target": {"identity": "images-0.2.2", "digest": target_digest},
        }
    )

    terminal = worker.run_container(operation.operation_id)

    assert terminal.state == ContainerImageSetOperationState.SUCCEEDED
    assert owner.read_current().identity == "images-0.2.2"
    assert len(effect.archives) == 1


def test_worker_keeps_missing_artifact_distinct_as_unavailable(tmp_path) -> None:
    owner, _, _, _, worker = fixture(tmp_path)
    operation = ContainerImageSetUseCases(
        state_owner=owner,
        operation_ids=Ids(),
        clock=Clock(),
    ).apply(
        {
            "expectedCurrentIdentity": "images-0.2.1",
            "target": {"identity": "images-0.2.2", "digest": "sha256:" + "b" * 64},
        }
    )

    terminal = worker.run_container(operation.operation_id)

    assert terminal.state == ContainerImageSetOperationState.UNAVAILABLE
    assert owner.read_current().identity == "images-0.2.1"


def test_restart_marks_unknown_running_effect_unavailable(tmp_path) -> None:
    owner, _, _, _, worker = fixture(tmp_path)
    pending = ContainerImageSetUseCases(
        state_owner=owner,
        operation_ids=Ids(),
        clock=Clock(),
    ).apply(
        {
            "expectedCurrentIdentity": "images-0.2.1",
            "target": {"identity": "images-0.2.2", "digest": "sha256:" + "b" * 64},
        }
    )
    running = transition_container_image_set_operation(
        pending,
        state=ContainerImageSetOperationState.RUNNING,
        updated_at=Clock().now(),
    )
    owner.record_container_image_set_transition(running)

    worker.recover_and_run_pending()

    persisted = owner.get_operation(pending.operation_id)
    assert persisted is not None
    assert persisted.state == ContainerImageSetOperationState.UNAVAILABLE
    assert persisted.failure is not None
    assert persisted.failure.kind == "containerImageSetWorkerInterrupted"


def test_guest_runtime_worker_uses_verified_imported_archive(tmp_path) -> None:
    owner, artifacts, _, effect, worker = fixture(tmp_path)
    content = tar_bytes("bin/runtime", b"runtime")
    target_digest = digest(content)
    reference = artifacts.import_bytes(
        kind="guest-runtime-release",
        digest=target_digest,
        content=content,
    )
    operation = GuestRuntimeReleaseUseCases(
        state_owner=owner,
        operation_ids=Ids(),
        clock=Clock(),
    ).apply(
        {
            "expectedActiveIdentity": "guest-0.2.1",
            "target": {
                "identity": "guest-0.2.2",
                "archive": reference,
                "digest": target_digest,
            },
        }
    )

    terminal = worker.run_guest_runtime(operation.operation_id)

    assert terminal.state == GuestRuntimeReleaseOperationState.SUCCEEDED
    assert owner.read_active_guest_runtime_release().identity == "guest-0.2.2"
    assert len(effect.archives) == 1


def test_atomic_runtime_effect_rejects_archive_path_traversal(tmp_path) -> None:
    archive = tmp_path / "release.tar"
    archive.write_bytes(tar_bytes("../escaped", b"bad"))
    operation = GuestRuntimeReleaseUseCases
    release_operation = _runtime_operation(tmp_path)
    effect = AtomicGuestRuntimeReleaseEffect(
        releases_root=tmp_path / "releases",
        active_link=tmp_path / "active",
        reconcile=lambda: None,
    )

    with pytest.raises(UpdateEffectFailed, match="unsafe"):
        effect.activate(release_operation, archive)

    assert not (tmp_path / "escaped").exists()
    assert operation is GuestRuntimeReleaseUseCases


def test_atomic_runtime_effect_restores_previous_active_link_on_reconcile_failure(
    tmp_path,
) -> None:
    releases = tmp_path / "releases"
    previous = releases / "guest-0.2.1"
    previous.mkdir(parents=True)
    active = tmp_path / "active"
    active.symlink_to(previous)
    archive = tmp_path / "release.tar"
    archive.write_bytes(tar_bytes("bin/runtime", b"new"))
    effect = AtomicGuestRuntimeReleaseEffect(
        releases_root=releases,
        active_link=active,
        reconcile=lambda: (_ for _ in ()).throw(RuntimeError("restart failed")),
    )

    with pytest.raises(RuntimeError, match="restart failed"):
        effect.activate(_runtime_operation(tmp_path), archive)

    assert active.resolve() == previous


def test_atomic_runtime_effect_can_rollback_to_verified_existing_slot(
    tmp_path,
) -> None:
    operation = _runtime_operation(tmp_path / "owner")
    releases = tmp_path / "releases"
    current = releases / "guest-current"
    target = releases / operation.target.identity
    current.mkdir(parents=True)
    target.mkdir()
    (target / ".artifact-sha256").write_text(
        operation.target.digest + "\n",
        encoding="utf-8",
    )
    active = tmp_path / "active"
    active.symlink_to(current)
    reconciled: list[str] = []
    effect = AtomicGuestRuntimeReleaseEffect(
        releases_root=releases,
        active_link=active,
        reconcile=lambda: reconciled.append("reconciled"),
    )

    effect.activate(operation, tmp_path / "archive-is-not-read-for-existing-slot")

    assert active.resolve() == target
    assert reconciled == ["reconciled"]


def test_import_reverifies_existing_content_addressed_archive(tmp_path) -> None:
    store = ImmutableUpdateArtifactStore(tmp_path / "artifacts")
    content = b"archive"
    expected = digest(content)
    store.import_bytes(
        kind="container-image-set",
        digest=expected,
        content=content,
    )
    resolved = store.resolve(kind="container-image-set", digest=expected)
    resolved.write_bytes(b"corrupt")

    with pytest.raises(Exception, match="digest mismatch"):
        store.resolve(kind="container-image-set", digest=expected)


def test_stream_import_rejects_short_body_without_leaving_staging_file(
    tmp_path,
) -> None:
    store = ImmutableUpdateArtifactStore(tmp_path / "artifacts")
    content = b"short"

    with pytest.raises(Exception, match="Content-Length"):
        store.import_stream(
            kind="container-image-set",
            digest=digest(content),
            stream=io.BytesIO(content),
            size_bytes=len(content) + 1,
        )

    assert list((tmp_path / "artifacts").rglob(".import-*")) == []


def test_guest_api_imports_archive_into_explicit_owner_contract() -> None:
    content = b"archive"
    expected = digest(content)

    class UseCases:
        def import_update_artifact(self, *, kind, digest, content):
            assert kind == "container-image-set"
            assert digest == expected
            assert content == b"archive"
            return {
                "kind": kind,
                "digest": digest,
                "ownerReference": f"{kind}/{digest}.archive",
            }

    status, document = route_request(
        method="PUT",
        path=f"/runtime/update-artifacts/container-image-set/{expected}",
        body=content,
        usecases=UseCases(),  # type: ignore[arg-type]
    )

    assert status == HTTPStatus.CREATED
    assert document["digest"] == expected


def tar_bytes(name: str, content: bytes) -> bytes:
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w") as archive:
        info = tarfile.TarInfo(name)
        info.size = len(content)
        archive.addfile(info, io.BytesIO(content))
    return output.getvalue()


def _runtime_operation(tmp_path):
    owner, artifacts, _, _, _ = fixture(tmp_path / "owner")
    content = tar_bytes("bin/runtime", b"runtime")
    target_digest = digest(content)
    reference = artifacts.import_bytes(
        kind="guest-runtime-release",
        digest=target_digest,
        content=content,
    )
    return GuestRuntimeReleaseUseCases(
        state_owner=owner,
        operation_ids=Ids(),
        clock=Clock(),
    ).apply(
        {
            "expectedActiveIdentity": "guest-0.2.1",
            "target": {
                "identity": "guest-0.2.2",
                "archive": reference,
                "digest": target_digest,
            },
        }
    )

from __future__ import annotations

import hashlib
import io
import tarfile
from datetime import UTC, datetime
from http import HTTPStatus
from pathlib import Path
from types import SimpleNamespace

import pytest

from tirosh_guest_tools.adapters.inbound.guest_control_api import route_request
from tirosh_guest_tools.adapters.outbound.sqlite_control import (
    SQLiteControlRepository,
)
from tirosh_guest_tools.adapters.outbound.update_artifacts import (
    GUEST_RUNTIME_RESTART_SERVICES,
    AtomicGuestRuntimeReleaseEffect,
    GuestRuntimeServiceReconciler,
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
    UpdateEffectCompensationFailed,
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


def test_worker_persists_runtime_compensation_failure_as_distinct_kind(
    tmp_path,
) -> None:
    owner, artifacts, container_effect, _, _ = fixture(tmp_path)
    content = tar_bytes("version", b"target")
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

    class CompensationFailureEffect:
        def activate(self, operation, archive) -> None:
            raise UpdateEffectCompensationFailed(
                effect_failure=RuntimeError("new restart failed"),
                compensation_failure=RuntimeError("old restart failed"),
            )

    worker = GuestUpdateOwnerWorker(
        container_owner=owner,
        guest_runtime_owner=owner,
        artifacts=artifacts,
        container_effect=container_effect,
        guest_runtime_effect=CompensationFailureEffect(),
        clock=Clock(),
    )

    terminal = worker.run_guest_runtime(operation.operation_id)

    assert terminal.failure is not None
    assert terminal.failure.kind == "guestRuntimeReleaseCompensationFailed"
    assert owner.read_active_guest_runtime_release().identity == "guest-0.2.1"


def test_container_apply_and_rollback_consume_target_and_previous_archives(
    tmp_path,
) -> None:
    owner, artifacts, effect, _, worker = fixture(tmp_path)
    previous = b"initial"
    target = b"target compose image-set"
    previous_digest = digest(previous)
    target_digest = digest(target)
    artifacts.import_bytes(
        kind="container-image-set",
        digest=previous_digest,
        content=previous,
    )
    artifacts.import_bytes(
        kind="container-image-set",
        digest=target_digest,
        content=target,
    )
    usecases = ContainerImageSetUseCases(
        state_owner=owner,
        operation_ids=Ids(),
        clock=Clock(),
    )
    applied = usecases.apply(
        {
            "expectedCurrentIdentity": "images-0.2.1",
            "target": {
                "identity": "images-0.2.2",
                "digest": target_digest,
            },
        }
    )
    worker.run_container(applied.operation_id)
    rolled_back = usecases.rollback(
        {
            "expectedCurrentIdentity": "images-0.2.2",
            "target": {
                "identity": "images-0.2.1",
                "digest": previous_digest,
            },
        }
    )
    worker.run_container(rolled_back.operation_id)

    assert [archive.read_bytes() for archive in effect.archives] == [
        target,
        previous,
    ]
    assert owner.read_current().identity == "images-0.2.1"


def test_guest_runtime_apply_and_rollback_execute_through_active_release_link(
    tmp_path,
) -> None:
    now = Clock().now()
    owner = SQLiteControlRepository(tmp_path / "control.sqlite")
    owner.migrate_schema()
    artifacts = ImmutableUpdateArtifactStore(tmp_path / "artifacts")
    previous_archive = tar_bytes("version", b"previous")
    target_archive = tar_bytes("version", b"target")
    previous_digest = digest(previous_archive)
    target_digest = digest(target_archive)
    previous_reference = artifacts.import_bytes(
        kind="guest-runtime-release",
        digest=previous_digest,
        content=previous_archive,
    )
    target_reference = artifacts.import_bytes(
        kind="guest-runtime-release",
        digest=target_digest,
        content=target_archive,
    )
    previous_release = GuestRuntimeRelease.validated(
        "guest-0.2.1",
        previous_reference,
        previous_digest,
    )
    owner.provision_active_guest_runtime_release(
        previous_release,
        observed_at=now,
    )
    releases = tmp_path / "releases"
    previous_slot = releases / previous_release.identity
    previous_slot.mkdir(parents=True)
    (previous_slot / "version").write_bytes(b"previous")
    (previous_slot / ".artifact-sha256").write_text(
        previous_digest + "\n",
        encoding="utf-8",
    )
    active = tmp_path / "guest-tools"
    active.symlink_to(previous_slot)
    executed_versions: list[bytes] = []
    effect = AtomicGuestRuntimeReleaseEffect(
        releases_root=releases,
        active_link=active,
        reconcile=lambda: executed_versions.append(
            (active / "version").read_bytes()
        ),
    )
    worker = GuestUpdateOwnerWorker(
        container_owner=owner,
        guest_runtime_owner=owner,
        artifacts=artifacts,
        container_effect=ContainerEffect(),
        guest_runtime_effect=effect,
        clock=Clock(),
    )
    usecases = GuestRuntimeReleaseUseCases(
        state_owner=owner,
        operation_ids=Ids(),
        clock=Clock(),
    )
    applied = usecases.apply(
        {
            "expectedActiveIdentity": previous_release.identity,
            "target": {
                "identity": "guest-0.2.2",
                "archive": target_reference,
                "digest": target_digest,
            },
        }
    )
    worker.run_guest_runtime(applied.operation_id)
    rolled_back = usecases.rollback(
        {
            "expectedActiveIdentity": "guest-0.2.2",
            "target": previous_release.as_json(),
        }
    )
    worker.run_guest_runtime(rolled_back.operation_id)

    assert executed_versions == [b"target", b"previous"]
    assert active.resolve() == previous_slot
    assert owner.read_active_guest_runtime_release() == previous_release


def test_guest_runtime_reconciler_restarts_services_after_compose(
    monkeypatch,
) -> None:
    events: list[str] = []

    def run(arguments, **_):
        events.append(arguments[-1])
        return SimpleNamespace(returncode=0, stderr="")

    monkeypatch.setattr(
        "tirosh_guest_tools.adapters.outbound.update_artifacts.subprocess.run",
        run,
    )
    GuestRuntimeServiceReconciler(
        compose_reconcile=lambda: events.append("compose")
    ).reconcile()

    assert events == ["compose", *GUEST_RUNTIME_RESTART_SERVICES]


def test_long_running_guest_wrappers_resolve_the_active_runtime_link() -> None:
    root = Path(__file__).resolve().parents[3]
    wrapper_dir = (
        root / "apps/vitalserver-macos-runtime/Support/Guest/bin"
    )

    for wrapper in (
        "tirosh-vitalserver-guest-control-api",
        "tirosh-runtime-observation",
        "tirosh-vitalserver-container-logs",
    ):
        assert "/opt/tirosh/guest-tools/venv/bin/" in (
            wrapper_dir / wrapper
        ).read_text(encoding="utf-8")


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
    (previous / "version").write_bytes(b"previous")
    active = tmp_path / "active"
    active.symlink_to(previous)
    archive = tmp_path / "release.tar"
    archive.write_bytes(tar_bytes("version", b"new"))
    executed_versions: list[bytes] = []

    def reconcile() -> None:
        executed_versions.append((active / "version").read_bytes())
        if len(executed_versions) == 1:
            raise RuntimeError("restart failed")

    effect = AtomicGuestRuntimeReleaseEffect(
        releases_root=releases,
        active_link=active,
        reconcile=reconcile,
    )

    with pytest.raises(RuntimeError, match="restart failed"):
        effect.activate(_runtime_operation(tmp_path), archive)

    assert active.resolve() == previous
    assert executed_versions == [b"new", b"previous"]


def test_atomic_runtime_effect_reports_failed_compensation_separately(
    tmp_path,
) -> None:
    releases = tmp_path / "releases"
    previous = releases / "guest-0.2.1"
    previous.mkdir(parents=True)
    active = tmp_path / "active"
    active.symlink_to(previous)
    archive = tmp_path / "release.tar"
    archive.write_bytes(tar_bytes("version", b"new"))
    effect = AtomicGuestRuntimeReleaseEffect(
        releases_root=releases,
        active_link=active,
        reconcile=lambda: (_ for _ in ()).throw(RuntimeError("restart failed")),
    )

    with pytest.raises(
        UpdateEffectCompensationFailed,
        match="compensation both failed",
    ):
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

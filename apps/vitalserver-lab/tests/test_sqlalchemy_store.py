from __future__ import annotations

import re
from collections.abc import Callable
from pathlib import Path

import pytest

from vitalserver_lab.model import (
    LabSessionCreateInput,
    LabSessionFailure,
    LabSessionStoreUnavailable,
)
from vitalserver_lab.persistence import SQLAlchemyLabSessionStore
from vitalserver_lab.persistence.records import (
    PRODUCT_LAB_SCHEMA,
    LabRecordBase,
)


def provisioned_store(
    url: str,
    *,
    id_factory: Callable[[], str] | None = None,
) -> SQLAlchemyLabSessionStore:
    store = SQLAlchemyLabSessionStore(
        url,
        id_factory=id_factory,
        schema_translate_map={PRODUCT_LAB_SCHEMA: None},
    )
    LabRecordBase.metadata.create_all(store._engine)
    return store


def test_sqlalchemy_store_uses_same_domain_contract_with_sqlite(tmp_path: Path) -> None:
    url = f"sqlite:///{tmp_path / 'lab.sqlite'}"
    store = provisioned_store(url, id_factory=lambda: "lab_session_1")
    store.ensure_ready()
    created = store.create(
        LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Portable persistence",
            recorder_count=1,
            target_url="http://edge/",
        )
    )

    reopened = provisioned_store(url)
    loaded = reopened.get(created.session_id)
    beds = reopened.list_beds()
    recorders = reopened.list_recorders()

    assert loaded == created
    assert re.fullmatch(r"bed_[A-Z0-9]{6}", beds[0].bed_id)
    assert re.fullmatch(r"rec_[A-Z0-9]{6}", recorders[0].recorder_id)
    assert re.fullmatch(r"LAB-[A-Z0-9]{6}", recorders[0].vrcode)


def test_sqlalchemy_store_reports_missing_managed_schema(tmp_path: Path) -> None:
    store = SQLAlchemyLabSessionStore(
        f"sqlite:///{tmp_path / 'missing.sqlite'}",
        schema_translate_map={PRODUCT_LAB_SCHEMA: None},
    )

    with pytest.raises(LabSessionStoreUnavailable) as error:
        store.ensure_ready()

    assert "schema verification failed" in error.value.message


def test_sqlalchemy_store_persists_session_and_children_as_one_start_transition(
    tmp_path: Path,
) -> None:
    url = f"sqlite:///{tmp_path / 'lab.sqlite'}"
    store = provisioned_store(url, id_factory=lambda: "lab_session_1")
    created = store.create(
        LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Atomic transition",
            recorder_count=1,
            target_url="http://edge/",
        )
    )

    started = store.start(created.session_id)
    reopened = provisioned_store(url)

    assert started is not None
    assert started.state == "running"
    assert reopened.get(created.session_id).state == "running"
    assert {bed.state for bed in reopened.list_beds()} == {"running"}
    assert {recorder.state for recorder in reopened.list_recorders()} == {"running"}


def test_sqlalchemy_store_persists_session_failure_and_children_atomically(
    tmp_path: Path,
) -> None:
    url = f"sqlite:///{tmp_path / 'lab.sqlite'}"
    store = provisioned_store(url, id_factory=lambda: "lab_session_1")
    created = store.create(
        LabSessionCreateInput(
            scenario_id="vital-file-replay",
            name="Failed replay",
            recorder_count=1,
            target_url="http://edge/",
        )
    )
    store.start(created.session_id)

    failed = store.fail(
        created.session_id,
        LabSessionFailure(
            stage="fileValidation",
            code="invalidWaveformSampleRate",
            message="invalid waveform sample rate",
            failed_at="2026-07-21T03:00:00Z",
        ),
    )
    reopened = provisioned_store(url)
    loaded = reopened.get(created.session_id)

    assert failed is not None
    assert failed.state == "failed"
    assert loaded is not None
    assert loaded.failure == failed.failure
    assert {bed.state for bed in reopened.list_beds()} == {"failed"}
    assert {recorder.state for recorder in reopened.list_recorders()} == {"failed"}


def test_sqlalchemy_store_deletes_session_and_owned_children_atomically(
    tmp_path: Path,
) -> None:
    url = f"sqlite:///{tmp_path / 'lab.sqlite'}"
    store = provisioned_store(url, id_factory=lambda: "lab_session_1")
    created = store.create(
        LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Delete aggregate",
            recorder_count=1,
            target_url="http://edge/",
        )
    )

    remaining = store.delete_session(created.session_id)
    reopened = provisioned_store(url)

    assert remaining == ()
    assert reopened.list_sessions() == ()
    assert reopened.list_beds() == ()
    assert reopened.list_recorders() == ()


def test_sqlalchemy_store_persists_only_archive_finalization_request_reference(
    tmp_path: Path,
) -> None:
    url = f"sqlite:///{tmp_path / 'lab.sqlite'}"
    store = provisioned_store(url, id_factory=lambda: "lab_session_1")
    created = store.create(
        LabSessionCreateInput(
            scenario_id="baseline-monitoring",
            name="Archive reference",
            recorder_count=1,
            target_url="http://edge/",
        )
    )

    stored = store.save_archive_finalization_request_ids(
        created.session_id,
        ("ingress-request-1",),
    )
    reopened = provisioned_store(url)

    assert stored is not None
    assert stored.archive_finalization_request_ids == ("ingress-request-1",)
    assert reopened.get(created.session_id).archive_finalization_request_ids == (
        "ingress-request-1",
    )
    assert "archiveFinalizationRequestIds" not in stored.as_json()

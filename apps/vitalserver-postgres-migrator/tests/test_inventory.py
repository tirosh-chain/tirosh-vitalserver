from __future__ import annotations

import json

import pytest
from vitalserver_postgres_migrator import inventory_cli
from vitalserver_postgres_migrator.inventory_contract import (
    EXPECTATION_REVISION,
    EXPECTED_RELATIONS,
    MANAGED_SCHEMAS,
    DatabaseInventorySnapshot,
    MigrationGraph,
    RelationInventory,
    build_inventory_document,
    classify_migration,
)


def test_inventory_preserves_estimated_and_unavailable_row_counts() -> None:
    snapshot = _snapshot(
        revisions=(EXPECTATION_REVISION,),
        relations=tuple(
            _relation(
                qualified_name,
                estimated_rows=None if index == 0 else index,
            )
            for index, qualified_name in enumerate(EXPECTED_RELATIONS)
        ),
    )

    document = build_inventory_document(snapshot, _current_graph())

    assert document["state"] == "loaded"
    assert document["contract"]["state"] == "ready"
    assert document["migration"]["state"] == "current"
    assert document["migration"]["expectationRevisionState"] == "applied"
    public_relation = document["schemas"][0]["relations"][0]
    assert public_relation["rowCount"] == {
        "state": "unavailable",
        "value": None,
        "source": None,
    }
    recorder_schema = next(
        schema
        for schema in document["schemas"]
        if schema["name"] == "recorder_observability"
    )
    assert recorder_schema["relations"][0]["rowCount"]["state"] == "estimated"
    assert document["totals"]["managedRelationCount"] == len(EXPECTED_RELATIONS)


def test_inventory_reports_missing_and_unexpected_relations_explicitly() -> None:
    expected_without_expectation = tuple(
        _relation(name)
        for name in EXPECTED_RELATIONS
        if name != "recorder_observability.expectations"
    )
    snapshot = _snapshot(
        revisions=("0001_initial_schema",),
        relations=(
            *expected_without_expectation,
            _relation("recorder_observability.future_events"),
        ),
    )
    graph = MigrationGraph(
        target_revision=EXPECTATION_REVISION,
        target_lineage=frozenset({"0001_initial_schema", EXPECTATION_REVISION}),
        applied_lineage=frozenset({"0001_initial_schema"}),
    )

    document = build_inventory_document(snapshot, graph)

    assert document["contract"] == {
        "state": "missingAndUnexpectedObjects",
        "expectedSchemas": list(MANAGED_SCHEMAS),
        "discoveredSchemas": list(MANAGED_SCHEMAS),
        "missingSchemas": [],
        "unexpectedSchemas": [],
        "expectedRelations": list(EXPECTED_RELATIONS),
        "missingRelations": ["recorder_observability.expectations"],
        "unexpectedRelations": ["recorder_observability.future_events"],
    }
    assert document["migration"]["state"] == "behind"
    assert document["migration"]["expectationRevisionState"] == "notApplied"


def test_inventory_reports_unexpected_user_schema_explicitly() -> None:
    snapshot = _snapshot(
        revisions=(EXPECTATION_REVISION,),
        installed_schemas=(*MANAGED_SCHEMAS, "legacy_runtime"),
        relations=tuple(_relation(name) for name in EXPECTED_RELATIONS),
    )

    document = build_inventory_document(snapshot, _current_graph())

    assert document["contract"]["state"] == "unexpectedObjects"
    assert document["contract"]["unexpectedSchemas"] == ["legacy_runtime"]
    assert document["contract"]["unexpectedRelations"] == []


@pytest.mark.parametrize(
    ("revisions", "applied_lineage", "state", "expectation_state"),
    [
        ((), None, "unversioned", "notApplied"),
        (
            ("0001_initial_schema", "other_head"),
            None,
            "multipleRevisions",
            "unknown",
        ),
        (("unrecognized",), None, "unknownRevision", "unknown"),
    ],
)
def test_migration_classification_does_not_guess_unknown_state(
    revisions: tuple[str, ...],
    applied_lineage: frozenset[str] | None,
    state: str,
    expectation_state: str,
) -> None:
    graph = MigrationGraph(
        target_revision=EXPECTATION_REVISION,
        target_lineage=frozenset({"0001_initial_schema", EXPECTATION_REVISION}),
        applied_lineage=applied_lineage,
    )

    migration = classify_migration(revisions=revisions, graph=graph)

    assert migration["state"] == state
    assert migration["expectationRevisionState"] == expectation_state


def test_inventory_cli_requires_explicit_database_url(
    capsys: pytest.CaptureFixture[str],
) -> None:
    exit_code = inventory_cli.run([], environment={})

    assert exit_code == 1
    failure = json.loads(capsys.readouterr().err)
    assert failure["state"] == "failed"
    assert failure["failure"] == {
        "stage": "postgres-inventory-configuration",
        "code": "databaseUrlMissing",
        "detail": "missing VITALSERVER_DATABASE_URL",
    }


def test_inventory_cli_resolves_applied_revision_lineage(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    monkeypatch.setattr(
        inventory_cli,
        "_collect_snapshot",
        lambda _database_url: _snapshot(
            revisions=(EXPECTATION_REVISION,),
            relations=tuple(_relation(name) for name in EXPECTED_RELATIONS),
        ),
    )

    exit_code = inventory_cli.run(
        [],
        environment={
            "VITALSERVER_DATABASE_URL": ("postgresql://inventory.invalid/vitalserver")
        },
    )

    assert exit_code == 0
    document = json.loads(capsys.readouterr().out)
    assert document["migration"]["state"] == "current"
    assert document["migration"]["expectationRevisionState"] == "applied"


def _snapshot(
    *,
    revisions: tuple[str, ...],
    relations: tuple[RelationInventory, ...],
    installed_schemas: tuple[str, ...] = MANAGED_SCHEMAS,
) -> DatabaseInventorySnapshot:
    return DatabaseInventorySnapshot(
        captured_at="2026-07-23T12:00:00+00:00",
        database_name="vitalserver",
        database_user="inventory_reader",
        server_version="17.5",
        database_bytes=4096,
        data_directory="/var/lib/postgresql/data",
        transaction_read_only=True,
        installed_schemas=installed_schemas,
        revisions=revisions,
        relations=relations,
    )


def _relation(
    qualified_name: str,
    *,
    estimated_rows: int | None = 1,
) -> RelationInventory:
    schema_name, relation_name = qualified_name.split(".", maxsplit=1)
    return RelationInventory(
        schema_name=schema_name,
        relation_name=relation_name,
        estimated_row_count=estimated_rows,
        table_bytes=100,
        index_bytes=25,
        total_bytes=125,
    )


def _current_graph() -> MigrationGraph:
    return MigrationGraph(
        target_revision=EXPECTATION_REVISION,
        target_lineage=frozenset({"0001_initial_schema", EXPECTATION_REVISION}),
        applied_lineage=frozenset({"0001_initial_schema", EXPECTATION_REVISION}),
    )

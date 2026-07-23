from __future__ import annotations

from dataclasses import dataclass
from typing import Any

INVENTORY_SCHEMA_VERSION = 1
EXPECTATION_REVISION = "0002_recorder_observability_expectations"
MANAGED_SCHEMAS = (
    "public",
    "vitaldb_read_model",
    "product_lab",
    "recorder_observability",
)
EXPECTED_RELATIONS = (
    "public.alembic_version",
    "vitaldb_read_model.observation_snapshots",
    "vitaldb_read_model.recorder_activity_buckets",
    "vitaldb_read_model.relationship_history_snapshots",
    "vitaldb_read_model.entity_visibility",
    "product_lab.sessions",
    "product_lab.beds",
    "product_lab.recorders",
    "recorder_observability.requests",
    "recorder_observability.records",
    "recorder_observability.current",
    "recorder_observability.expectations",
)


@dataclass(frozen=True)
class RelationInventory:
    schema_name: str
    relation_name: str
    estimated_row_count: int | None
    table_bytes: int
    index_bytes: int
    total_bytes: int

    @property
    def qualified_name(self) -> str:
        return f"{self.schema_name}.{self.relation_name}"


@dataclass(frozen=True)
class DatabaseInventorySnapshot:
    captured_at: str
    database_name: str
    database_user: str
    server_version: str
    database_bytes: int
    data_directory: str
    transaction_read_only: bool
    installed_schemas: tuple[str, ...]
    revisions: tuple[str, ...]
    relations: tuple[RelationInventory, ...]


@dataclass(frozen=True)
class MigrationGraph:
    target_revision: str
    target_lineage: frozenset[str]
    applied_lineage: frozenset[str] | None


def build_inventory_document(
    snapshot: DatabaseInventorySnapshot,
    graph: MigrationGraph,
) -> dict[str, Any]:
    actual_names = {relation.qualified_name for relation in snapshot.relations}
    expected_names = set(EXPECTED_RELATIONS)
    actual_schemas = set(snapshot.installed_schemas)
    expected_schemas = set(MANAGED_SCHEMAS)
    missing_schemas = sorted(expected_schemas - actual_schemas)
    unexpected_schemas = sorted(actual_schemas - expected_schemas)
    missing_relations = sorted(expected_names - actual_names)
    unexpected_relations = sorted(actual_names - expected_names)
    contract_state = _contract_state(
        missing=bool(missing_schemas or missing_relations),
        unexpected=bool(unexpected_schemas or unexpected_relations),
    )
    migration = classify_migration(
        revisions=snapshot.revisions,
        graph=graph,
    )
    relations_by_schema = {
        schema_name: tuple(
            relation
            for relation in snapshot.relations
            if relation.schema_name == schema_name
        )
        for schema_name in MANAGED_SCHEMAS
    }
    schemas = [
        {
            "name": schema_name,
            "state": (
                "loaded" if schema_name in snapshot.installed_schemas else "missing"
            ),
            "totalBytes": sum(
                relation.total_bytes for relation in relations_by_schema[schema_name]
            ),
            "relations": [
                {
                    "name": relation.relation_name,
                    "qualifiedName": relation.qualified_name,
                    "rowCount": {
                        "state": (
                            "estimated"
                            if relation.estimated_row_count is not None
                            else "unavailable"
                        ),
                        "value": relation.estimated_row_count,
                        "source": (
                            "pg_class.reltuples"
                            if relation.estimated_row_count is not None
                            else None
                        ),
                    },
                    "tableBytes": relation.table_bytes,
                    "indexBytes": relation.index_bytes,
                    "totalBytes": relation.total_bytes,
                }
                for relation in relations_by_schema[schema_name]
            ],
        }
        for schema_name in MANAGED_SCHEMAS
    ]
    managed_relations = [
        relation
        for relation in snapshot.relations
        if relation.qualified_name in expected_names
    ]
    return {
        "schemaVersion": INVENTORY_SCHEMA_VERSION,
        "state": "loaded",
        "capturedAt": snapshot.captured_at,
        "database": {
            "name": snapshot.database_name,
            "user": snapshot.database_user,
            "serverVersion": snapshot.server_version,
            "databaseBytes": snapshot.database_bytes,
            "dataDirectory": snapshot.data_directory,
            "transactionReadOnly": snapshot.transaction_read_only,
        },
        "migration": migration,
        "contract": {
            "state": contract_state,
            "expectedSchemas": list(MANAGED_SCHEMAS),
            "discoveredSchemas": list(snapshot.installed_schemas),
            "missingSchemas": missing_schemas,
            "unexpectedSchemas": unexpected_schemas,
            "expectedRelations": list(EXPECTED_RELATIONS),
            "missingRelations": missing_relations,
            "unexpectedRelations": unexpected_relations,
        },
        "schemas": schemas,
        "totals": {
            "managedRelationCount": len(managed_relations),
            "managedTableBytes": sum(
                relation.table_bytes for relation in managed_relations
            ),
            "managedIndexBytes": sum(
                relation.index_bytes for relation in managed_relations
            ),
            "managedTotalBytes": sum(
                relation.total_bytes for relation in managed_relations
            ),
        },
    }


def classify_migration(
    *,
    revisions: tuple[str, ...],
    graph: MigrationGraph,
) -> dict[str, Any]:
    current_revision = revisions[0] if len(revisions) == 1 else None
    if not revisions:
        state = "unversioned"
    elif len(revisions) > 1:
        state = "multipleRevisions"
    elif current_revision == graph.target_revision:
        state = "current"
    elif current_revision in graph.target_lineage:
        state = "behind"
    else:
        state = "unknownRevision"

    if not revisions:
        expectation_state = "notApplied"
    elif len(revisions) > 1 or graph.applied_lineage is None:
        expectation_state = "unknown"
    elif EXPECTATION_REVISION in graph.applied_lineage:
        expectation_state = "applied"
    else:
        expectation_state = "notApplied"

    return {
        "state": state,
        "currentRevision": current_revision,
        "reportedRevisions": list(revisions),
        "targetRevision": graph.target_revision,
        "expectationRevision": EXPECTATION_REVISION,
        "expectationRevisionState": expectation_state,
    }


def _contract_state(*, missing: bool, unexpected: bool) -> str:
    if missing and unexpected:
        return "missingAndUnexpectedObjects"
    if missing:
        return "missingObjects"
    if unexpected:
        return "unexpectedObjects"
    return "ready"

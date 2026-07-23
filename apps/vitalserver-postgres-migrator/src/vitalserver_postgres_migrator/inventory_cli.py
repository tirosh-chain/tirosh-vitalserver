from __future__ import annotations

import argparse
import json
import os
import sys
from collections.abc import Mapping, Sequence
from pathlib import Path
from typing import Any

from alembic.config import Config
from alembic.script import ScriptDirectory
from alembic.script.revision import ResolutionError

from .cli import CONFIG_ENV, DATABASE_URL_ENV, DEFAULT_CONFIG, command_target
from .inventory_contract import (
    DatabaseInventorySnapshot,
    MigrationGraph,
    build_inventory_document,
)
from .postgres_inventory import (
    PostgresInventoryReadError,
    collect_database_inventory,
)


class InventoryCommandError(RuntimeError):
    def __init__(self, *, stage: str, code: str, detail: str) -> None:
        super().__init__(detail)
        self.stage = stage
        self.code = code
        self.detail = detail


def main() -> None:
    raise SystemExit(run(sys.argv[1:], environment=os.environ))


def run(
    argv: Sequence[str],
    *,
    environment: Mapping[str, str],
) -> int:
    parser = argparse.ArgumentParser(
        prog="vitalserver-postgres-inventory",
        description=(
            "Read VitalServer PostgreSQL migration and capacity state without "
            "changing the database."
        ),
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Write the JSON proof to an existing directory instead of stdout.",
    )
    parser.add_argument(
        "--config",
        type=Path,
        default=Path(environment.get(CONFIG_ENV, DEFAULT_CONFIG)),
        help="Alembic configuration used to resolve the release migration head.",
    )
    args = parser.parse_args(list(argv))

    try:
        database_url = _required_database_url(environment)
        graph = _migration_graph(args.config, database_url)
        snapshot = _collect_snapshot(database_url)
        graph = _with_applied_lineage(
            graph,
            config_path=args.config,
            revisions=snapshot.revisions,
        )
        document = build_inventory_document(snapshot, graph)
        _publish(document, args.output)
        return 0
    except InventoryCommandError as error:
        failure = {
            "schemaVersion": 1,
            "state": "failed",
            "failure": {
                "stage": error.stage,
                "code": error.code,
                "detail": error.detail,
            },
        }
        print(json.dumps(failure, sort_keys=True), file=sys.stderr, flush=True)
        return 1


def _required_database_url(environment: Mapping[str, str]) -> str:
    value = environment.get(DATABASE_URL_ENV)
    if not isinstance(value, str) or not value.strip():
        raise InventoryCommandError(
            stage="postgres-inventory-configuration",
            code="databaseUrlMissing",
            detail=f"missing {DATABASE_URL_ENV}",
        )
    return value.strip()


def _migration_graph(config_path: Path, database_url: str) -> MigrationGraph:
    if not config_path.is_file():
        raise InventoryCommandError(
            stage="postgres-inventory-migration-graph",
            code="migrationConfigMissing",
            detail=f"Alembic config does not exist: {config_path}",
        )
    config = Config(str(config_path))
    from .cli import sqlalchemy_url

    config.set_main_option("sqlalchemy.url", sqlalchemy_url(database_url))
    try:
        target_revision = command_target(config)
        scripts = ScriptDirectory.from_config(config)
        target_lineage = _lineage(scripts, target_revision)
    except (OSError, ResolutionError, SystemExit) as error:
        raise InventoryCommandError(
            stage="postgres-inventory-migration-graph",
            code="migrationGraphInvalid",
            detail=str(error),
        ) from error
    return MigrationGraph(
        target_revision=target_revision,
        target_lineage=frozenset(target_lineage),
        applied_lineage=None,
    )


def _collect_snapshot(database_url: str) -> DatabaseInventorySnapshot:
    try:
        snapshot = collect_database_inventory(database_url)
    except PostgresInventoryReadError as error:
        raise InventoryCommandError(
            stage="postgres-inventory-database-read",
            code="databaseReadFailed",
            detail=error.detail,
        ) from error
    return snapshot


def _with_applied_lineage(
    graph: MigrationGraph,
    *,
    config_path: Path,
    revisions: tuple[str, ...],
) -> MigrationGraph:
    if len(revisions) != 1:
        return graph
    try:
        scripts = ScriptDirectory.from_config(Config(str(config_path)))
        applied = _lineage(scripts, revisions[0])
    except (OSError, ResolutionError):
        return MigrationGraph(
            target_revision=graph.target_revision,
            target_lineage=graph.target_lineage,
            applied_lineage=None,
        )
    return MigrationGraph(
        target_revision=graph.target_revision,
        target_lineage=graph.target_lineage,
        applied_lineage=frozenset(applied),
    )


def _lineage(scripts: ScriptDirectory, upper_revision: str) -> set[str]:
    return {
        revision.revision
        for revision in scripts.iterate_revisions(upper_revision, "base")
    }


def _publish(document: dict[str, Any], output: Path | None) -> None:
    payload = json.dumps(document, indent=2, sort_keys=True) + "\n"
    if output is None:
        print(payload, end="", flush=True)
        return
    parent = output.parent
    if not parent.is_dir():
        raise InventoryCommandError(
            stage="postgres-inventory-output",
            code="outputDirectoryMissing",
            detail=f"output directory does not exist: {parent}",
        )
    temporary = output.with_name(f".{output.name}.tmp")
    try:
        temporary.write_text(payload, encoding="utf-8")
        os.replace(temporary, output)
    except OSError as error:
        raise InventoryCommandError(
            stage="postgres-inventory-output",
            code="outputWriteFailed",
            detail=str(error),
        ) from error

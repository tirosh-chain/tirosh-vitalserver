"""Explicit PostgreSQL compose-client primitives for remaining read models."""

from __future__ import annotations

import json
import subprocess
from typing import Any

from tirosh_guest_tools.application import compose as compose_app
from tirosh_guest_tools.contracts import ComposeService

POSTGRES_SCHEMA_ADVISORY_LOCK = "66060002000"


class PostgresCommandError(RuntimeError):
    """A PostgreSQL adapter command failed before an owning adapter could map it."""

    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


def run_psql(sql: str, *, stage: str) -> subprocess.CompletedProcess[str]:
    return run_psql_commands([sql], stage=stage)


def run_schema_migration(
    sql: str,
    *,
    stage: str,
) -> subprocess.CompletedProcess[str]:
    return run_psql_commands(
        [
            f"SELECT pg_advisory_lock({POSTGRES_SCHEMA_ADVISORY_LOCK});",
            sql,
            f"SELECT pg_advisory_unlock({POSTGRES_SCHEMA_ADVISORY_LOCK});",
        ],
        stage=stage,
    )


def run_psql_commands(
    commands: list[str],
    *,
    stage: str,
) -> subprocess.CompletedProcess[str]:
    psql_arguments: list[str] = [
        "exec",
        "-T",
        ComposeService.POSTGRES.value,
        "psql",
        "-U",
        "vitalserver",
        "-d",
        "vitalserver",
        "-v",
        "ON_ERROR_STOP=1",
        "-qAt",
    ]
    for command in commands:
        psql_arguments.extend(["-c", command])

    try:
        return compose_app.compose(psql_arguments, capture_output=True)
    except subprocess.CalledProcessError as error:
        message = f"postgres command failed during {stage}: exitCode={error.returncode}"
        output = compact_process_output(error)
        if output:
            message += "\n" + output
        raise PostgresCommandError(
            message,
            kind="postgresCommandFailed",
        ) from error


def compact_process_output(error: subprocess.CalledProcessError) -> str:
    sections: list[str] = []
    if error.stdout:
        sections.append(f"stdout:\n{error.stdout}")
    if error.stderr:
        sections.append(f"stderr:\n{error.stderr}")
    return "\n".join(sections)


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def jsonb_literal(document: dict[str, Any]) -> str:
    return sql_literal(json.dumps(document, sort_keys=True)) + "::jsonb"

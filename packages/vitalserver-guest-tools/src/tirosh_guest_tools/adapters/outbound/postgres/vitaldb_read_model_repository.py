from __future__ import annotations

import json
from datetime import datetime
from typing import Any

from tirosh_guest_tools.adapters.outbound.postgres.operation_repository import (
    jsonb_literal,
    run_psql,
    run_schema_migration,
    sql_literal,
)
from tirosh_guest_tools.domain.guest_control.models import (
    GuestControlDependencyError,
    VitalDBReadModelDependencyError,
)

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS vitaldb_observation_snapshots (
    snapshot_id bigserial PRIMARY KEY,
    document jsonb NOT NULL,
    observed_at timestamptz NOT NULL,
    inserted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS vitaldb_observation_snapshots_observed_at_idx
    ON vitaldb_observation_snapshots (observed_at DESC, snapshot_id DESC);

CREATE TABLE IF NOT EXISTS vitaldb_relationship_history_snapshots (
    snapshot_id bigserial PRIMARY KEY,
    document jsonb NOT NULL,
    observed_at timestamptz NOT NULL,
    inserted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS vitaldb_relationship_history_snapshots_observed_at_idx
    ON vitaldb_relationship_history_snapshots (observed_at DESC, snapshot_id DESC);

CREATE TABLE IF NOT EXISTS vitaldb_entity_visibility (
    entity_kind text NOT NULL,
    entity_id text NOT NULL,
    visibility text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (entity_kind, entity_id),
    CONSTRAINT vitaldb_entity_visibility_kind_check
        CHECK (entity_kind IN ('recorder', 'bed')),
    CONSTRAINT vitaldb_entity_visibility_value_check
        CHECK (visibility IN ('visible', 'hidden', 'deleted'))
);
"""

RELATIONSHIP_HISTORY_STATES = {"loaded", "partiallyLoaded", "readFailed"}
VISIBLE = "visible"
HIDDEN = "hidden"
DELETED = "deleted"


class PostgresVitalDBReadModelRepository:
    def ensure_schema(self) -> None:
        try:
            run_schema_migration(
                SCHEMA_SQL,
                stage="vitaldb read model schema migration",
            )
        except GuestControlDependencyError as error:
            raise VitalDBReadModelDependencyError(
                error.message,
                kind=error.kind,
            ) from error

    def check_ready(self) -> None:
        _run_vitaldb_psql("SELECT 1;", stage="vitaldb read model readiness")

    def latest_observation(self) -> dict[str, Any]:
        observation = self._latest_observation_document()
        return {
            "state": "loaded",
            "observation": observation,
            "readError": None,
        }

    def recorders(self) -> dict[str, Any]:
        return self._collection_document(
            collection="recorders",
            entity_kind="recorder",
            identity_field="vrcode",
            invalid_message="VitalDB recorder read model field is invalid.",
        )

    def hide_recorders(self, request: dict[str, Any]) -> dict[str, Any]:
        ids = _required_string_list(request, "vrcodes")
        self._set_visibility(entity_kind="recorder", entity_ids=ids, visibility=HIDDEN)
        return self.recorders()

    def unhide_recorders(self, request: dict[str, Any]) -> dict[str, Any]:
        ids = _required_string_list(request, "vrcodes")
        self._set_visibility(entity_kind="recorder", entity_ids=ids, visibility=VISIBLE)
        return self.recorders()

    def delete_recorders(self, request: dict[str, Any]) -> dict[str, Any]:
        ids = _required_string_list(request, "vrcodes")
        self._mark_deleted_if_hidden(entity_kind="recorder", entity_ids=ids)
        return self.recorders()

    def recorder_activity(self, vrcode: str) -> dict[str, Any]:
        observation = self._latest_observation_document()
        activity_buckets = observation.get("activityBuckets", [])
        if not isinstance(activity_buckets, list):
            raise VitalDBReadModelDependencyError(
                "VitalDB recorder activity read model field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        buckets: list[dict[str, Any]] = []
        for bucket in activity_buckets:
            if not isinstance(bucket, dict):
                raise VitalDBReadModelDependencyError(
                    "VitalDB recorder activity bucket item is invalid.",
                    kind="vitaldb-read-model-invalid",
                )
            bucket_vrcode = bucket.get("vrcode")
            if not isinstance(bucket_vrcode, str):
                raise VitalDBReadModelDependencyError(
                    "VitalDB recorder activity bucket vrcode field is invalid.",
                    kind="vitaldb-read-model-invalid",
                )
            if bucket_vrcode == vrcode:
                buckets.append(_validated_activity_bucket(bucket, vrcode=vrcode))
        return {
            "state": "loaded",
            "vrcode": vrcode,
            "buckets": buckets,
            "readError": None,
        }

    def beds(self) -> dict[str, Any]:
        return self._collection_document(
            collection="beds",
            entity_kind="bed",
            identity_field="bedID",
            invalid_message="VitalDB bed read model field is invalid.",
        )

    def hide_beds(self, request: dict[str, Any]) -> dict[str, Any]:
        ids = _required_string_list(request, "bedIDs")
        self._set_visibility(entity_kind="bed", entity_ids=ids, visibility=HIDDEN)
        return self.beds()

    def unhide_beds(self, request: dict[str, Any]) -> dict[str, Any]:
        ids = _required_string_list(request, "bedIDs")
        self._set_visibility(entity_kind="bed", entity_ids=ids, visibility=VISIBLE)
        return self.beds()

    def delete_beds(self, request: dict[str, Any]) -> dict[str, Any]:
        ids = _required_string_list(request, "bedIDs")
        self._mark_deleted_if_hidden(entity_kind="bed", entity_ids=ids)
        return self.beds()

    def relationships(self) -> dict[str, Any]:
        relationship_history = self._latest_relationship_history_document()
        return self._relationship_history_response(relationship_history)

    def previous_relationship_history(self) -> dict[str, Any] | None:
        try:
            return self.relationships()
        except VitalDBReadModelDependencyError as error:
            if (
                error.kind == "vitaldb-read-model-unavailable"
                and error.message == "VitalDB relationship read model is empty."
            ):
                return None
            raise

    def _relationship_history_response(
        self,
        relationship_history: dict[str, Any],
    ) -> dict[str, Any]:
        state = relationship_history.get("state")
        assignments = relationship_history.get("assignments")
        events = relationship_history.get("events")
        read_error = relationship_history.get("readError")

        if state not in RELATIONSHIP_HISTORY_STATES:
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model state field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        if not isinstance(assignments, list):
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model assignments field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        if not isinstance(events, list):
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model events field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        if read_error is not None and not isinstance(read_error, str):
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model readError field is invalid.",
                kind="vitaldb-read-model-invalid",
            )

        return {
            "state": state,
            "assignments": assignments,
            "events": events,
            "readError": read_error,
        }

    def _latest_observation_document(self) -> dict[str, Any]:
        sql = (
            "SELECT document::text FROM vitaldb_observation_snapshots "
            "ORDER BY observed_at DESC, snapshot_id DESC LIMIT 1;"
        )
        completed = _run_vitaldb_psql(sql, stage="vitaldb latest observation read")
        text = (completed.stdout or "").strip()
        if not text:
            raise VitalDBReadModelDependencyError(
                "VitalDB observation read model is empty.",
                kind="vitaldb-read-model-unavailable",
            )

        try:
            observation = json.loads(text)
        except json.JSONDecodeError as error:
            raise VitalDBReadModelDependencyError(
                "VitalDB observation read model document is invalid JSON.",
                kind="vitaldb-read-model-invalid",
            ) from error

        if not isinstance(observation, dict):
            raise VitalDBReadModelDependencyError(
                "VitalDB observation read model document is not an object.",
                kind="vitaldb-read-model-invalid",
            )

        return observation

    def _latest_relationship_history_document(self) -> dict[str, Any]:
        sql = (
            "SELECT document::text FROM vitaldb_relationship_history_snapshots "
            "ORDER BY observed_at DESC, snapshot_id DESC LIMIT 1;"
        )
        completed = _run_vitaldb_psql(sql, stage="vitaldb relationship history read")
        text = (completed.stdout or "").strip()
        if not text:
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model is empty.",
                kind="vitaldb-read-model-unavailable",
            )

        try:
            relationship_history = json.loads(text)
        except json.JSONDecodeError as error:
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model document is invalid JSON.",
                kind="vitaldb-read-model-invalid",
            ) from error

        if not isinstance(relationship_history, dict):
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model document is not an object.",
                kind="vitaldb-read-model-invalid",
            )

        return relationship_history

    def _collection_document(
        self,
        *,
        collection: str,
        entity_kind: str,
        identity_field: str,
        invalid_message: str,
    ) -> dict[str, Any]:
        observation = self._latest_observation_document()
        observed_at = observation.get("observedAt")
        ready = observation.get("ready")
        recorder_online_threshold_seconds = observation.get(
            "recorderOnlineThresholdSeconds"
        )
        values = observation.get(collection)
        if not isinstance(observed_at, str):
            raise VitalDBReadModelDependencyError(
                "VitalDB observation read model observedAt field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        if not isinstance(ready, bool):
            raise VitalDBReadModelDependencyError(
                "VitalDB observation read model ready field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        if not isinstance(recorder_online_threshold_seconds, int):
            raise VitalDBReadModelDependencyError(
                "VitalDB observation read model "
                "recorderOnlineThresholdSeconds field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        if not isinstance(values, list):
            raise VitalDBReadModelDependencyError(
                invalid_message,
                kind="vitaldb-read-model-invalid",
            )
        visibility_by_id = self._visibility_by_id(entity_kind)
        visible_values = _apply_visibility(
            values,
            identity_field=identity_field,
            visibility_by_id=visibility_by_id,
            invalid_message=invalid_message,
        )
        return {
            "state": "loaded",
            collection: visible_values,
            "observedAt": observed_at,
            "ready": ready,
            "recorderOnlineThresholdSeconds": recorder_online_threshold_seconds,
            "readError": None,
        }

    def _visibility_by_id(self, entity_kind: str) -> dict[str, str]:
        sql = (
            "SELECT COALESCE(jsonb_object_agg(entity_id, visibility), '{}'::jsonb)::text "
            "FROM vitaldb_entity_visibility "
            f"WHERE entity_kind = {sql_literal(entity_kind)};"
        )
        completed = _run_vitaldb_psql(sql, stage="vitaldb entity visibility read")
        text = (completed.stdout or "").strip()
        if not text:
            raise VitalDBReadModelDependencyError(
                "VitalDB entity visibility read returned no document.",
                kind="vitaldb-read-model-unavailable",
            )
        try:
            document = json.loads(text)
        except json.JSONDecodeError as error:
            raise VitalDBReadModelDependencyError(
                "VitalDB entity visibility document is invalid JSON.",
                kind="vitaldb-read-model-invalid",
            ) from error
        if not isinstance(document, dict):
            raise VitalDBReadModelDependencyError(
                "VitalDB entity visibility document is not an object.",
                kind="vitaldb-read-model-invalid",
            )
        visibility_by_id: dict[str, str] = {}
        for entity_id, visibility in document.items():
            if not isinstance(entity_id, str) or visibility not in {
                VISIBLE,
                HIDDEN,
                DELETED,
            }:
                raise VitalDBReadModelDependencyError(
                    "VitalDB entity visibility document contains an invalid item.",
                    kind="vitaldb-read-model-invalid",
                )
            visibility_by_id[entity_id] = str(visibility)
        return visibility_by_id

    def _set_visibility(
        self,
        *,
        entity_kind: str,
        entity_ids: list[str],
        visibility: str,
    ) -> None:
        if visibility not in {VISIBLE, HIDDEN, DELETED}:
            raise VitalDBReadModelDependencyError(
                "VitalDB entity visibility command is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        values = ", ".join(
            "("
            f"{sql_literal(entity_kind)}, "
            f"{sql_literal(entity_id)}, "
            f"{sql_literal(visibility)}, "
            "now()"
            ")"
            for entity_id in entity_ids
        )
        sql = (
            "INSERT INTO vitaldb_entity_visibility "
            "(entity_kind, entity_id, visibility, updated_at) VALUES "
            f"{values} "
            "ON CONFLICT (entity_kind, entity_id) DO UPDATE SET "
            "visibility = EXCLUDED.visibility, updated_at = EXCLUDED.updated_at;"
        )
        _run_vitaldb_psql(sql, stage="vitaldb entity visibility write")

    def _mark_deleted_if_hidden(
        self,
        *,
        entity_kind: str,
        entity_ids: list[str],
    ) -> None:
        visibility_by_id = self._visibility_by_id(entity_kind)
        not_hidden = [
            entity_id
            for entity_id in entity_ids
            if visibility_by_id.get(entity_id, VISIBLE) != HIDDEN
        ]
        if not_hidden:
            raise VitalDBReadModelDependencyError(
                "VitalDB entity must be hidden before delete: "
                + ", ".join(not_hidden),
                kind="vitaldb-read-model-delete-not-hidden",
            )
        self._set_visibility(
            entity_kind=entity_kind,
            entity_ids=entity_ids,
            visibility=DELETED,
        )

    def save_latest_observation(
        self,
        observation: dict[str, Any],
        *,
        observed_at: datetime,
    ) -> None:
        sql = (
            "INSERT INTO vitaldb_observation_snapshots "
            "(document, observed_at) VALUES ("
            f"{jsonb_literal(observation)}, "
            f"{sql_literal(observed_at.isoformat())}::timestamptz"
            ");"
        )
        _run_vitaldb_psql(sql, stage="vitaldb latest observation save")

    def save_relationship_history(
        self,
        relationship_history: dict[str, Any],
        *,
        observed_at: datetime,
    ) -> None:
        sql = (
            "INSERT INTO vitaldb_relationship_history_snapshots "
            "(document, observed_at) VALUES ("
            f"{jsonb_literal(relationship_history)}, "
            f"{sql_literal(observed_at.isoformat())}::timestamptz"
            ");"
        )
        _run_vitaldb_psql(sql, stage="vitaldb relationship history save")


def _run_vitaldb_psql(sql: str, *, stage: str):
    try:
        return run_psql(sql, stage=stage)
    except GuestControlDependencyError as error:
        raise VitalDBReadModelDependencyError(
            error.message,
            kind="vitaldb-read-model-unavailable",
        ) from error


def _validated_activity_bucket(
    bucket: dict[str, Any],
    *,
    vrcode: str,
) -> dict[str, Any]:
    required_int_fields = [
        "bucketSeconds",
        "messageCount",
        "byteCount",
        "roomCount",
    ]
    required_string_fields = [
        "bucketStartedAt",
        "firstObservedAt",
        "lastObservedAt",
    ]
    if bucket.get("vrcode") != vrcode:
        raise VitalDBReadModelDependencyError(
            "VitalDB recorder activity bucket vrcode field is invalid.",
            kind="vitaldb-read-model-invalid",
        )
    for field in required_string_fields:
        if not isinstance(bucket.get(field), str):
            raise VitalDBReadModelDependencyError(
                f"VitalDB recorder activity bucket {field} field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
    for field in required_int_fields:
        if not isinstance(bucket.get(field), int):
            raise VitalDBReadModelDependencyError(
                f"VitalDB recorder activity bucket {field} field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
    return {
        "vrcode": vrcode,
        "bucketStartedAt": bucket["bucketStartedAt"],
        "bucketSeconds": bucket["bucketSeconds"],
        "messageCount": bucket["messageCount"],
        "byteCount": bucket["byteCount"],
        "roomCount": bucket["roomCount"],
        "firstObservedAt": bucket["firstObservedAt"],
        "lastObservedAt": bucket["lastObservedAt"],
    }


def _required_string_list(request: dict[str, Any], field: str) -> list[str]:
    values = request.get(field)
    if not isinstance(values, list) or not values:
        raise VitalDBReadModelDependencyError(
            f"VitalDB visibility request requires non-empty {field}.",
            kind="vitaldb-read-model-invalid-request",
        )
    result: list[str] = []
    for value in values:
        if not isinstance(value, str) or not value.strip():
            raise VitalDBReadModelDependencyError(
                f"VitalDB visibility request {field} contains an invalid value.",
                kind="vitaldb-read-model-invalid-request",
            )
        result.append(value.strip())
    return result


def _apply_visibility(
    values: list[Any],
    *,
    identity_field: str,
    visibility_by_id: dict[str, str],
    invalid_message: str,
) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for value in values:
        if not isinstance(value, dict):
            raise VitalDBReadModelDependencyError(
                invalid_message,
                kind="vitaldb-read-model-invalid",
            )
        entity_id = value.get(identity_field)
        if not isinstance(entity_id, str) or not entity_id:
            raise VitalDBReadModelDependencyError(
                f"VitalDB read model {identity_field} field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        visibility = visibility_by_id.get(entity_id, VISIBLE)
        if visibility == DELETED:
            continue
        visible_value = dict(value)
        visible_value["visibility"] = visibility
        result.append(visible_value)
    return result

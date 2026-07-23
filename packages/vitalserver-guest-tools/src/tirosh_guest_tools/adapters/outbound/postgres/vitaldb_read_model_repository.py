from __future__ import annotations

import os
from datetime import UTC, datetime
from typing import Any

from sqlalchemy import create_engine, select
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from tirosh_guest_tools.adapters.outbound.postgres.mappings import domain_document
from tirosh_guest_tools.adapters.outbound.postgres.records import (
    VitalDBObservationRecord,
    VitalDBRecorderActivityBucketRecord,
    VitalDBRelationshipRecord,
    VitalDBVisibilityRecord,
)
from tirosh_guest_tools.domain.guest_control.models import (
    VitalDBReadModelDependencyError,
)
from tirosh_guest_tools.domain.vitaldb_history import (
    VitalDBHistoryProjectionError,
    bed_history_from_recorder_history,
    project_vitaldb_history,
)

RELATIONSHIP_HISTORY_STATES = {"loaded", "partiallyLoaded", "readFailed"}
VISIBLE = "visible"
HIDDEN = "hidden"
DELETED = "deleted"


class PostgresVitalDBReadModelRepository:
    def __init__(
        self,
        database_url: str | None = None,
        *,
        schema_translate_map: dict[str, str | None] | None = None,
    ) -> None:
        raw_url = database_url or os.environ.get(
            "VITALSERVER_DATABASE_URL",
            "postgresql://vitalserver:vitalserver@127.0.0.1:15432/vitalserver",
        )
        url = (
            "postgresql+psycopg://" + raw_url.removeprefix("postgresql://")
            if raw_url.startswith("postgresql://")
            else raw_url
        )
        engine = create_engine(url, pool_pre_ping=True)
        self._engine = (
            engine.execution_options(schema_translate_map=schema_translate_map)
            if schema_translate_map is not None
            else engine
        )

    def verify_schema(self) -> None:
        try:
            with self._engine.connect() as connection:
                for record_type in (
                    VitalDBObservationRecord,
                    VitalDBRecorderActivityBucketRecord,
                    VitalDBRelationshipRecord,
                    VitalDBVisibilityRecord,
                ):
                    connection.execute(select(record_type).limit(0))
        except SQLAlchemyError as error:
            raise _database_error(error, stage="schema verification") from error

    def latest_observation(self) -> dict[str, Any]:
        observation = self._latest_observation_document()
        return {
            "state": "loaded",
            "observation": observation,
            "readError": None,
        }

    def recorders(self) -> dict[str, Any]:
        return self._history_document()

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
        if self._visibility_by_id("recorder").get(vrcode) == DELETED:
            return {
                "state": "loaded",
                "vrcode": vrcode,
                "buckets": [],
                "readError": None,
            }
        try:
            with Session(self._engine) as session:
                records = list(
                    session.scalars(
                        select(VitalDBRecorderActivityBucketRecord)
                        .where(VitalDBRecorderActivityBucketRecord.vrcode == vrcode)
                        .order_by(
                            VitalDBRecorderActivityBucketRecord.bucket_started_at,
                            VitalDBRecorderActivityBucketRecord.bucket_seconds,
                        )
                    )
                )
        except SQLAlchemyError as error:
            raise _database_error(error, stage="recorder activity read") from error
        buckets = [_activity_bucket_document(record) for record in records]
        return {
            "state": "loaded",
            "vrcode": vrcode,
            "buckets": buckets,
            "readError": None,
        }

    def beds(self) -> dict[str, Any]:
        return bed_history_from_recorder_history(self._history_document())

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

    def relationships(self, *, event_limit: int) -> dict[str, Any]:
        relationship_history = self._latest_relationship_history_document()
        document = self._visible_relationship_history(
            relationship_history,
            include_projection_state=False,
        )
        event_total_count = len(document["events"])
        document["events"] = list(reversed(document["events"][-event_limit:]))
        document["eventTotalCount"] = event_total_count
        document["eventLimit"] = event_limit
        return document

    def _visible_relationship_history(
        self,
        relationship_history: dict[str, Any],
        *,
        include_projection_state: bool,
    ) -> dict[str, Any]:
        document = self._relationship_history_response(relationship_history)
        deleted_vrcodes = {
            identity
            for identity, visibility in self._visibility_by_id("recorder").items()
            if visibility == DELETED
        }
        deleted_bed_ids = {
            identity
            for identity, visibility in self._visibility_by_id("bed").items()
            if visibility == DELETED
        }
        if any(not isinstance(item, dict) for item in document["assignments"]):
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model assignment item is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        if any(not isinstance(item, dict) for item in document["events"]):
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model event item is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        document["assignments"] = [
            assignment
            for assignment in document["assignments"]
            if assignment.get("vrcode") not in deleted_vrcodes
            and assignment.get("bedID") not in deleted_bed_ids
        ]
        document["events"] = [
            event
            for event in document["events"]
            if event.get("vrcode") not in deleted_vrcodes
            and event.get("previousVrcode") not in deleted_vrcodes
            and event.get("bedID") not in deleted_bed_ids
            and event.get("previousBedID") not in deleted_bed_ids
        ]
        if include_projection_state:
            if "projectionVersion" in relationship_history:
                document["projectionVersion"] = relationship_history[
                    "projectionVersion"
                ]
            if "activeIssueIDs" in relationship_history:
                document["activeIssueIDs"] = relationship_history["activeIssueIDs"]
        return document

    def previous_relationship_history(self) -> dict[str, Any] | None:
        try:
            return self._visible_relationship_history(
                self._latest_relationship_history_document(),
                include_projection_state=True,
            )
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
        try:
            with Session(self._engine) as session:
                record = session.scalar(
                    select(VitalDBObservationRecord)
                    .order_by(
                        VitalDBObservationRecord.observed_at.desc(),
                        VitalDBObservationRecord.snapshot_id.desc(),
                    )
                    .limit(1)
                )
        except SQLAlchemyError as error:
            raise _database_error(error, stage="latest observation read") from error
        if record is None:
            raise VitalDBReadModelDependencyError(
                "VitalDB observation read model is empty.",
                kind="vitaldb-read-model-unavailable",
            )
        return domain_document(record.document, label="observation read model")

    def _observation_documents(self, *, limit: int = 1000) -> list[dict[str, Any]]:
        try:
            with Session(self._engine) as session:
                records = list(
                    session.scalars(
                        select(VitalDBObservationRecord)
                        .order_by(
                            VitalDBObservationRecord.observed_at.desc(),
                            VitalDBObservationRecord.snapshot_id.desc(),
                        )
                        .limit(limit)
                    )
                )
        except SQLAlchemyError as error:
            raise _database_error(error, stage="observation history read") from error
        if not records:
            raise VitalDBReadModelDependencyError(
                "VitalDB observation read model is empty.",
                kind="vitaldb-read-model-unavailable",
            )
        return [
            domain_document(record.document, label="observation history")
            for record in reversed(records)
        ]

    def _history_document(self) -> dict[str, Any]:
        try:
            return project_vitaldb_history(
                self._observation_documents(),
                recorder_visibility=self._visibility_by_id("recorder"),
                bed_visibility=self._visibility_by_id("bed"),
            )
        except VitalDBHistoryProjectionError as error:
            raise VitalDBReadModelDependencyError(
                str(error),
                kind="vitaldb-read-model-invalid",
            ) from error

    def _latest_relationship_history_document(self) -> dict[str, Any]:
        try:
            with Session(self._engine) as session:
                record = session.scalar(
                    select(VitalDBRelationshipRecord)
                    .order_by(
                        VitalDBRelationshipRecord.observed_at.desc(),
                        VitalDBRelationshipRecord.snapshot_id.desc(),
                    )
                    .limit(1)
                )
        except SQLAlchemyError as error:
            raise _database_error(error, stage="relationship history read") from error
        if record is None:
            raise VitalDBReadModelDependencyError(
                "VitalDB relationship read model is empty.",
                kind="vitaldb-read-model-unavailable",
            )
        return domain_document(record.document, label="relationship read model")

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
        try:
            with Session(self._engine) as session:
                records = list(
                    session.scalars(
                        select(VitalDBVisibilityRecord).where(
                            VitalDBVisibilityRecord.entity_kind == entity_kind
                        )
                    )
                )
        except SQLAlchemyError as error:
            raise _database_error(error, stage="entity visibility read") from error
        return {record.entity_id: record.visibility for record in records}

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
        try:
            with Session(self._engine) as session, session.begin():
                for entity_id in entity_ids:
                    record = session.get(
                        VitalDBVisibilityRecord,
                        {"entity_kind": entity_kind, "entity_id": entity_id},
                    )
                    if record is None:
                        session.add(
                            VitalDBVisibilityRecord(
                                entity_kind=entity_kind,
                                entity_id=entity_id,
                                visibility=visibility,
                                updated_at=datetime.now(UTC),
                            )
                        )
                    else:
                        record.visibility = visibility
                        record.updated_at = datetime.now(UTC)
        except SQLAlchemyError as error:
            raise _database_error(error, stage="entity visibility write") from error

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
                "VitalDB entity must be hidden before delete: " + ", ".join(not_hidden),
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
        activity_buckets = _validated_activity_buckets(observation)
        try:
            with Session(self._engine) as session, session.begin():
                session.add(
                    VitalDBObservationRecord(
                        document=observation, observed_at=observed_at
                    )
                )
                self._project_activity_buckets(session, activity_buckets)
        except SQLAlchemyError as error:
            raise _database_error(error, stage="latest observation save") from error

    def _project_activity_buckets(
        self,
        session: Session,
        buckets: list[dict[str, Any]],
    ) -> None:
        for bucket in buckets:
            identity = {
                "vrcode": bucket["vrcode"],
                "bucket_started_at": bucket["bucketStartedAt"],
                "bucket_seconds": bucket["bucketSeconds"],
            }
            record = session.get(VitalDBRecorderActivityBucketRecord, identity)
            if record is None:
                session.add(
                    VitalDBRecorderActivityBucketRecord(
                        **identity,
                        message_count=bucket["messageCount"],
                        byte_count=bucket["byteCount"],
                        room_count=bucket["roomCount"],
                        first_observed_at=bucket["firstObservedAt"],
                        last_observed_at=bucket["lastObservedAt"],
                    )
                )
                continue
            record.message_count = max(record.message_count, bucket["messageCount"])
            record.byte_count = max(record.byte_count, bucket["byteCount"])
            record.room_count = max(record.room_count, bucket["roomCount"])
            record.first_observed_at = min(
                record.first_observed_at,
                bucket["firstObservedAt"],
            )
            record.last_observed_at = max(
                record.last_observed_at,
                bucket["lastObservedAt"],
            )

    def save_relationship_history(
        self,
        relationship_history: dict[str, Any],
        *,
        observed_at: datetime,
    ) -> None:
        try:
            with Session(self._engine) as session, session.begin():
                session.add(
                    VitalDBRelationshipRecord(
                        document=relationship_history, observed_at=observed_at
                    )
                )
        except SQLAlchemyError as error:
            raise _database_error(error, stage="relationship history save") from error


def _database_error(
    error: SQLAlchemyError, *, stage: str
) -> VitalDBReadModelDependencyError:
    return VitalDBReadModelDependencyError(
        f"VitalDB database {stage} failed: {error}",
        kind="vitaldb-read-model-unavailable",
    )


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


def _validated_activity_buckets(
    observation: dict[str, Any],
) -> list[dict[str, Any]]:
    activity_buckets = observation.get("activityBuckets")
    if not isinstance(activity_buckets, list):
        raise VitalDBReadModelDependencyError(
            "VitalDB recorder activity read model field is invalid.",
            kind="vitaldb-read-model-invalid",
        )
    validated: list[dict[str, Any]] = []
    for bucket in activity_buckets:
        if not isinstance(bucket, dict):
            raise VitalDBReadModelDependencyError(
                "VitalDB recorder activity bucket item is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        vrcode = bucket.get("vrcode")
        if not isinstance(vrcode, str):
            raise VitalDBReadModelDependencyError(
                "VitalDB recorder activity bucket vrcode field is invalid.",
                kind="vitaldb-read-model-invalid",
            )
        validated.append(_validated_activity_bucket(bucket, vrcode=vrcode))
    return validated


def _activity_bucket_document(
    record: VitalDBRecorderActivityBucketRecord,
) -> dict[str, Any]:
    return {
        "vrcode": record.vrcode,
        "bucketStartedAt": record.bucket_started_at,
        "bucketSeconds": record.bucket_seconds,
        "messageCount": record.message_count,
        "byteCount": record.byte_count,
        "roomCount": record.room_count,
        "firstObservedAt": record.first_observed_at,
        "lastObservedAt": record.last_observed_at,
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

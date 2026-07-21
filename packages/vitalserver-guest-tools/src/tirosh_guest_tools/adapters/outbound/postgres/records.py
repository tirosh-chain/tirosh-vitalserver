from __future__ import annotations

from datetime import datetime
from typing import Any

from sqlalchemy import JSON, DateTime, Integer, String, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class VitalDBRecordBase(DeclarativeBase):
    pass


class VitalDBObservationRecord(VitalDBRecordBase):
    __tablename__ = "vitaldb_observation_snapshots"
    snapshot_id: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True
    )
    document: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )


class VitalDBRecorderActivityBucketRecord(VitalDBRecordBase):
    __tablename__ = "vitaldb_recorder_activity_buckets"
    vrcode: Mapped[str] = mapped_column(String, primary_key=True)
    bucket_started_at: Mapped[str] = mapped_column(String, primary_key=True)
    bucket_seconds: Mapped[int] = mapped_column(Integer, primary_key=True)
    message_count: Mapped[int] = mapped_column(Integer, nullable=False)
    byte_count: Mapped[int] = mapped_column(Integer, nullable=False)
    room_count: Mapped[int] = mapped_column(Integer, nullable=False)
    first_observed_at: Mapped[str] = mapped_column(String, nullable=False)
    last_observed_at: Mapped[str] = mapped_column(String, nullable=False)


class VitalDBSchemaMigrationRecord(VitalDBRecordBase):
    __tablename__ = "vitaldb_schema_migrations"
    migration_id: Mapped[str] = mapped_column(String, primary_key=True)
    applied_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class VitalDBRelationshipRecord(VitalDBRecordBase):
    __tablename__ = "vitaldb_relationship_history_snapshots"
    snapshot_id: Mapped[int] = mapped_column(
        Integer, primary_key=True, autoincrement=True
    )
    document: Mapped[dict[str, Any]] = mapped_column(JSON, nullable=False)
    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )


class VitalDBVisibilityRecord(VitalDBRecordBase):
    __tablename__ = "vitaldb_entity_visibility"
    __table_args__ = (UniqueConstraint("entity_kind", "entity_id"),)
    entity_kind: Mapped[str] = mapped_column(String, primary_key=True)
    entity_id: Mapped[str] = mapped_column(String, primary_key=True)
    visibility: Mapped[str] = mapped_column(String, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

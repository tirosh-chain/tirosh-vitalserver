from __future__ import annotations

from datetime import datetime
from typing import Any, ClassVar

from sqlalchemy import JSON, BigInteger, DateTime, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

VITALDB_READ_MODEL_SCHEMA = "vitaldb_read_model"
DOCUMENT_TYPE = JSON().with_variant(JSONB(), "postgresql")
IDENTITY_TYPE = BigInteger().with_variant(Integer(), "sqlite")


class VitalDBRecordBase(DeclarativeBase):
    pass


class VitalDBObservationRecord(VitalDBRecordBase):
    __tablename__ = "observation_snapshots"
    __table_args__: ClassVar[dict[str, str]] = {"schema": VITALDB_READ_MODEL_SCHEMA}
    snapshot_id: Mapped[int] = mapped_column(
        IDENTITY_TYPE, primary_key=True, autoincrement=True
    )
    document: Mapped[dict[str, Any]] = mapped_column(DOCUMENT_TYPE, nullable=False)
    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )


class VitalDBRecorderActivityBucketRecord(VitalDBRecordBase):
    __tablename__ = "recorder_activity_buckets"
    __table_args__: ClassVar[dict[str, str]] = {"schema": VITALDB_READ_MODEL_SCHEMA}
    vrcode: Mapped[str] = mapped_column(String, primary_key=True)
    bucket_started_at: Mapped[str] = mapped_column(String, primary_key=True)
    bucket_seconds: Mapped[int] = mapped_column(Integer, primary_key=True)
    message_count: Mapped[int] = mapped_column(BigInteger, nullable=False)
    byte_count: Mapped[int] = mapped_column(BigInteger, nullable=False)
    room_count: Mapped[int] = mapped_column(Integer, nullable=False)
    first_observed_at: Mapped[str] = mapped_column(String, nullable=False)
    last_observed_at: Mapped[str] = mapped_column(String, nullable=False)


class VitalDBRelationshipRecord(VitalDBRecordBase):
    __tablename__ = "relationship_history_snapshots"
    __table_args__: ClassVar[dict[str, str]] = {"schema": VITALDB_READ_MODEL_SCHEMA}
    snapshot_id: Mapped[int] = mapped_column(
        IDENTITY_TYPE, primary_key=True, autoincrement=True
    )
    document: Mapped[dict[str, Any]] = mapped_column(DOCUMENT_TYPE, nullable=False)
    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )


class VitalDBVisibilityRecord(VitalDBRecordBase):
    __tablename__ = "entity_visibility"
    __table_args__: ClassVar[dict[str, str]] = {"schema": VITALDB_READ_MODEL_SCHEMA}
    entity_kind: Mapped[str] = mapped_column(String, primary_key=True)
    entity_id: Mapped[str] = mapped_column(String, primary_key=True)
    visibility: Mapped[str] = mapped_column(String, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

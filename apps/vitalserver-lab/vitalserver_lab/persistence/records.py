from __future__ import annotations

from datetime import datetime
from typing import ClassVar

from sqlalchemy import JSON, DateTime, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

PRODUCT_LAB_SCHEMA = "product_lab"
DOCUMENT_TYPE = JSON().with_variant(JSONB(), "postgresql")


class LabRecordBase(DeclarativeBase):
    pass


class LabSessionRecord(LabRecordBase):
    __tablename__ = "sessions"
    __table_args__: ClassVar[dict[str, str]] = {"schema": PRODUCT_LAB_SCHEMA}
    session_id: Mapped[str] = mapped_column(String, primary_key=True)
    document: Mapped[dict[str, object]] = mapped_column(DOCUMENT_TYPE, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class LabBedRecord(LabRecordBase):
    __tablename__ = "beds"
    __table_args__: ClassVar[dict[str, str]] = {"schema": PRODUCT_LAB_SCHEMA}
    bed_id: Mapped[str] = mapped_column(String, primary_key=True)
    document: Mapped[dict[str, object]] = mapped_column(DOCUMENT_TYPE, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class LabRecorderRecord(LabRecordBase):
    __tablename__ = "recorders"
    __table_args__: ClassVar[dict[str, str]] = {"schema": PRODUCT_LAB_SCHEMA}
    recorder_id: Mapped[str] = mapped_column(String, primary_key=True)
    document: Mapped[dict[str, object]] = mapped_column(DOCUMENT_TYPE, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

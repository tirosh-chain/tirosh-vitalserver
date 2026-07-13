from __future__ import annotations

from datetime import datetime

from sqlalchemy import JSON, DateTime, String
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class LabRecordBase(DeclarativeBase):
    pass


class LabSessionRecord(LabRecordBase):
    __tablename__ = "lab_sessions"
    session_id: Mapped[str] = mapped_column(String, primary_key=True)
    document: Mapped[dict[str, object]] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class LabBedRecord(LabRecordBase):
    __tablename__ = "lab_beds"
    bed_id: Mapped[str] = mapped_column(String, primary_key=True)
    document: Mapped[dict[str, object]] = mapped_column(JSON, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class LabRecorderRecord(LabRecordBase):
    __tablename__ = "lab_recorders"
    recorder_id: Mapped[str] = mapped_column(String, primary_key=True)
    document: Mapped[dict[str, object]] = mapped_column(JSON, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

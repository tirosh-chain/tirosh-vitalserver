from __future__ import annotations

from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class ControlRecordBase(DeclarativeBase):
    pass


class ServiceOperationRecord(ControlRecordBase):
    __tablename__ = "service_operations"

    operation_id: Mapped[str] = mapped_column(String, primary_key=True)
    service: Mapped[str] = mapped_column(String, nullable=False)
    command: Mapped[str] = mapped_column(String, nullable=False)
    state: Mapped[str] = mapped_column(String, nullable=False)
    document: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class OperationEventRecord(ControlRecordBase):
    __tablename__ = "service_operation_events"

    event_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    operation_id: Mapped[str] = mapped_column(
        ForeignKey("service_operations.operation_id"),
        nullable=False,
    )
    state: Mapped[str] = mapped_column(String, nullable=False)
    document: Mapped[str] = mapped_column(Text, nullable=False)
    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class ActiveOperationLeaseRecord(ControlRecordBase):
    __tablename__ = "active_operation_leases"

    resource_key: Mapped[str] = mapped_column(String, primary_key=True)
    operation_id: Mapped[str] = mapped_column(
        ForeignKey("service_operations.operation_id"),
        unique=True,
        nullable=False,
    )
    acquired_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class ServiceStatusSnapshotRecord(ControlRecordBase):
    __tablename__ = "service_status_snapshots"

    service: Mapped[str] = mapped_column(String, primary_key=True)
    document: Mapped[str] = mapped_column(Text, nullable=False)
    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class GuestServiceResourceRecord(ControlRecordBase):
    __tablename__ = "guest_service_resources"

    service: Mapped[str] = mapped_column(String, primary_key=True)
    document: Mapped[str] = mapped_column(Text, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class RedisRelayStatusRecord(ControlRecordBase):
    __tablename__ = "redis_relay_status_snapshots"

    snapshot_id: Mapped[str] = mapped_column(String, primary_key=True)
    document: Mapped[str] = mapped_column(Text, nullable=False)
    observed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class ContainerImageSetRecord(ControlRecordBase):
    __tablename__ = "container_image_sets"

    identity: Mapped[str] = mapped_column(String, primary_key=True)
    digest: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class CurrentContainerImageSetRecord(ControlRecordBase):
    __tablename__ = "current_container_image_set"

    owner_key: Mapped[str] = mapped_column(String, primary_key=True)
    identity: Mapped[str] = mapped_column(
        ForeignKey("container_image_sets.identity"),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class ContainerImageSetOperationRecord(ControlRecordBase):
    __tablename__ = "container_image_set_operations"

    operation_id: Mapped[str] = mapped_column(String, primary_key=True)
    command: Mapped[str] = mapped_column(String, nullable=False)
    expected_current_identity: Mapped[str] = mapped_column(String, nullable=False)
    target_identity: Mapped[str] = mapped_column(
        ForeignKey("container_image_sets.identity"),
        nullable=False,
    )
    state: Mapped[str] = mapped_column(String, nullable=False)
    document: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class GuestRuntimeReleaseRecord(ControlRecordBase):
    __tablename__ = "guest_runtime_releases"

    identity: Mapped[str] = mapped_column(String, primary_key=True)
    archive: Mapped[str] = mapped_column(String, nullable=False, unique=True)
    digest: Mapped[str] = mapped_column(String, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class ActiveGuestRuntimeReleaseRecord(ControlRecordBase):
    __tablename__ = "active_guest_runtime_release"

    owner_key: Mapped[str] = mapped_column(String, primary_key=True)
    identity: Mapped[str] = mapped_column(
        ForeignKey("guest_runtime_releases.identity"),
        nullable=False,
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class GuestRuntimeReleaseOperationRecord(ControlRecordBase):
    __tablename__ = "guest_runtime_release_operations"

    operation_id: Mapped[str] = mapped_column(String, primary_key=True)
    command: Mapped[str] = mapped_column(String, nullable=False)
    expected_active_identity: Mapped[str] = mapped_column(String, nullable=False)
    target_identity: Mapped[str] = mapped_column(
        ForeignKey("guest_runtime_releases.identity"),
        nullable=False,
    )
    state: Mapped[str] = mapped_column(String, nullable=False)
    document: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )


class InitialUpdateOwnerProvisioningRecord(ControlRecordBase):
    __tablename__ = "initial_update_owner_provisioning"

    owner_key: Mapped[str] = mapped_column(String, primary_key=True)
    contract_digest: Mapped[str] = mapped_column(String, nullable=False)
    container_identity: Mapped[str] = mapped_column(String, nullable=False)
    container_digest: Mapped[str] = mapped_column(String, nullable=False)
    container_archive: Mapped[str] = mapped_column(String, nullable=False)
    guest_runtime_identity: Mapped[str] = mapped_column(String, nullable=False)
    guest_runtime_digest: Mapped[str] = mapped_column(String, nullable=False)
    guest_runtime_archive: Mapped[str] = mapped_column(String, nullable=False)
    completed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

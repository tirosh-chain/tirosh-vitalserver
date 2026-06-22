"""Persistence boundary for bed identities."""

from __future__ import annotations

from typing import Any, Protocol

from tirosh_vitalserver.testkit.domain.bed import Bed

BED_REGISTRY_STORE_SCHEMA_VERSION = 1


class BedRegistryStorePort(Protocol):
    """Persistent registry for created bed identities."""

    def load_beds(self) -> tuple[Bed, ...]: ...

    def save_beds(self, beds: tuple[Bed, ...]) -> None: ...

    def delete_beds(self) -> None: ...


def bed_to_record(bed: Bed) -> dict[str, str]:
    """Convert a Bed into a persistent JSON record."""

    return {
        "room_name": bed.room_name,
        "bed_id": bed.bed_id,
    }


def bed_from_record(data: dict[str, Any]) -> Bed:
    """Convert a persistent JSON record into a Bed."""

    return Bed(
        room_name=str(data["room_name"]),
        bed_id=str(data["bed_id"]),
    )

"""Registry for explicit bed identities."""

from __future__ import annotations

from threading import RLock

from tirosh_vitalserver.testkit.application.bed_registry.store import (
    BedRegistryStorePort,
)
from tirosh_vitalserver.testkit.domain.bed import (
    Bed,
    beds_for_room_names,
    create_beds,
    normalize_bed_room_names,
)
from tirosh_vitalserver.testkit.errors import BedNotRegisteredError


class BedRegistry:
    """Keep bed identities created through the TestKit API."""

    __test__ = False

    def __init__(self, store: BedRegistryStorePort | None = None) -> None:
        self._store = store
        self._lock = RLock()
        self._beds_by_room_name: dict[str, Bed] = {
            bed.room_name: bed for bed in load_stored_beds(store)
        }

    def list_beds(self) -> tuple[Bed, ...]:
        """Return registered bed identities in insertion order."""

        with self._lock:
            return tuple(self._beds_by_room_name.values())

    def require_registered_room_names(
        self,
        room_names: tuple[str, ...],
    ) -> tuple[str, ...]:
        """Return normalized room names only when every bed is registered."""

        resolved_room_names = normalize_bed_room_names(room_names)
        with self._lock:
            missing = tuple(
                room_name
                for room_name in resolved_room_names
                if room_name not in self._beds_by_room_name
            )
        if missing:
            raise BedNotRegisteredError(missing)

        return resolved_room_names

    def create_beds(
        self,
        *,
        count: int | None = None,
        room_names: tuple[str, ...] = (),
        prefix: str = "testbed",
        admin_user_id: str = "admin",
    ) -> tuple[Bed, ...]:
        """Create or register explicit bed identities."""

        beds = (
            beds_for_room_names(room_names, admin_user_id=admin_user_id)
            if room_names
            else self._create_generated_beds(
                count=count or 0,
                prefix=prefix,
                admin_user_id=admin_user_id,
            )
        )

        with self._lock:
            registered_by_room_name = dict(self._beds_by_room_name)
            for bed in beds:
                registered_by_room_name[bed.room_name] = bed
            registered_beds = tuple(registered_by_room_name.values())
            self._save(registered_beds)
            self._beds_by_room_name = registered_by_room_name
            return beds

    def _create_generated_beds(
        self,
        *,
        count: int,
        prefix: str,
        admin_user_id: str,
    ) -> tuple[Bed, ...]:
        with self._lock:
            reserved_room_names = tuple(self._beds_by_room_name)

        return create_beds(
            count=count,
            prefix=prefix,
            admin_user_id=admin_user_id,
            reserved_room_names=reserved_room_names,
        )

    def reset_beds(self) -> tuple[Bed, ...]:
        """Delete all registered bed identities."""

        with self._lock:
            beds = tuple(self._beds_by_room_name.values())
            self._delete_all()
            self._beds_by_room_name.clear()
            return beds

    def delete_beds(self, room_names: tuple[str, ...]) -> tuple[Bed, ...]:
        """Delete selected registered bed identities."""

        resolved_room_names = normalize_bed_room_names(room_names)

        with self._lock:
            missing = tuple(
                room_name
                for room_name in resolved_room_names
                if room_name not in self._beds_by_room_name
            )
            if missing:
                raise BedNotRegisteredError(missing)
            remaining_by_room_name = dict(self._beds_by_room_name)
            deleted = tuple(
                remaining_by_room_name.pop(room_name)
                for room_name in resolved_room_names
            )
            self._save(tuple(remaining_by_room_name.values()))
            self._beds_by_room_name = remaining_by_room_name
            return deleted

    def _save(self, beds: tuple[Bed, ...]) -> None:
        if self._store is not None:
            self._store.save_beds(beds)

    def _delete_all(self) -> None:
        if self._store is not None:
            self._store.delete_beds()


def load_stored_beds(
    store: BedRegistryStorePort | None,
) -> tuple[Bed, ...]:
    """Load persisted bed identities."""

    if store is None:
        return ()

    return store.load_beds()

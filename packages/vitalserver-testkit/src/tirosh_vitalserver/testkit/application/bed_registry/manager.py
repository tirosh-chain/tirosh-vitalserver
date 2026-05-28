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
)


class BedRegistry:
    """Keep bed identities created through the TestKit API."""

    __test__ = False

    def __init__(self, store: BedRegistryStorePort | None = None) -> None:
        self._store = store
        self._lock = RLock()
        self._beds_by_room_name: dict[str, Bed] = {
            bed.room_name: bed
            for bed in load_stored_beds(store)
        }

    def list_beds(self) -> tuple[Bed, ...]:
        """Return registered bed identities in insertion order."""

        with self._lock:
            return tuple(self._beds_by_room_name.values())

    def create_beds(
        self,
        *,
        count: int | None = None,
        room_names: tuple[str, ...] = (),
        prefix: str = "testkit-bed",
        admin_user_id: str = "admin",
    ) -> tuple[Bed, ...]:
        """Create or register explicit bed identities."""

        beds = (
            beds_for_room_names(room_names, admin_user_id=admin_user_id)
            if room_names
            else create_beds(
                count=count or 0,
                prefix=prefix,
                admin_user_id=admin_user_id,
            )
        )

        with self._lock:
            for bed in beds:
                self._beds_by_room_name[bed.room_name] = bed
            registered_beds = tuple(self._beds_by_room_name.values())
            self._save(registered_beds)
            return registered_beds

    def reset_beds(self) -> tuple[Bed, ...]:
        """Delete all registered bed identities."""

        with self._lock:
            beds = tuple(self._beds_by_room_name.values())
            self._beds_by_room_name.clear()
            self._delete_all()
            return beds

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

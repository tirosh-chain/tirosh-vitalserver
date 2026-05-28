"""Application service for bed identities."""

from tirosh_vitalserver.testkit.application.bed_registry.manager import (
    BedRegistry,
)
from tirosh_vitalserver.testkit.application.bed_registry.store import (
    BedRegistryStorePort,
)

__all__ = ["BedRegistry", "BedRegistryStorePort"]

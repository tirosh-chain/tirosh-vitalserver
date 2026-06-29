"""FastAPI adapter for recorder recovery."""

from tirosh_vitalserver.recorder_recovery.adapters.inbound.api.app import (
    create_recorder_recovery_app,
)

__all__ = ["create_recorder_recovery_app"]

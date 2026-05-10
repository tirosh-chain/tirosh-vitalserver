"""Base models for external data schemas."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class ExternalSchema(BaseModel):
    """Base Pydantic model for data crossing external system boundaries."""

    model_config = ConfigDict(frozen=True, strict=True)

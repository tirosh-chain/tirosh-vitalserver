"""External payload schemas.

The testkit keeps external validation here and converts validated data into
plain internal objects before handing it to use cases.
"""

import json
from copy import deepcopy
from pathlib import Path
from typing import Self, cast

from pydantic import Field, field_validator, model_validator

from tirosh_vitalserver.testkit.schemas.base import ExternalSchema
from tirosh_vitalserver.testkit.types.json import JsonObject


class RecorderPayloadDocument(ExternalSchema):
    """Vital Recorder payload accepted from files or command-line inputs."""

    payload: dict[str, object]

    @classmethod
    def from_external(cls, payload: object) -> Self:
        return cls.model_validate({"payload": payload})

    @classmethod
    def from_json_file(cls, path: str | Path) -> Self:
        return cls.from_external(json.loads(Path(path).read_text()))

    @field_validator("payload", mode="before")
    @classmethod
    def validate_payload(cls, value: object) -> dict[str, object]:
        if not isinstance(value, dict):
            raise ValueError("recorder payload must be a JSON object")

        return value

    @model_validator(mode="after")
    def require_room_map(self) -> Self:
        rooms = self.payload.get("rooms", self.payload)

        if not isinstance(rooms, dict) or not rooms:
            raise ValueError("recorder payload must contain at least one room")

        return self

    def to_internal(self) -> JsonObject:
        return cast(JsonObject, deepcopy(self.payload))


def load_recorder_payload(path: str | Path) -> JsonObject:
    """Load and validate a Vital Recorder-style JSON payload from disk."""

    return RecorderPayloadDocument.from_json_file(path).to_internal()


class RealtimeMessageDocument(ExternalSchema):
    """Normalized Socket.IO `send_data` message entering the testkit."""

    vrcode: str = Field(min_length=1)
    ver: str = Field(min_length=1)
    rooms: dict[str, object] = Field(min_length=1)

    @classmethod
    def from_json_bytes(cls, data: bytes) -> Self:
        return cls.model_validate_json(data)

    @field_validator("rooms", mode="before")
    @classmethod
    def validate_rooms(cls, value: object) -> dict[str, object]:
        if not isinstance(value, dict):
            raise ValueError("rooms must be a JSON object")

        return value

    def to_internal(self) -> JsonObject:
        return cast(
            JsonObject,
            {
                "vrcode": self.vrcode,
                "ver": self.ver,
                "rooms": deepcopy(self.rooms),
            },
        )

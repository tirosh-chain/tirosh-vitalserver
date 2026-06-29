"""JSON value types used inside recorder recovery helpers."""

from __future__ import annotations

type JsonScalar = str | int | float | bool | None
type JsonValue = JsonScalar | JsonObject | JsonArray
type JsonObject = dict[str, JsonValue]
type JsonArray = list[JsonValue]

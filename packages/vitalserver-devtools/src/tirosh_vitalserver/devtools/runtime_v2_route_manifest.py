from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any, Mapping


_REPOSITORY_ROOT = Path(__file__).resolve().parents[5]
DEFAULT_RUNTIME_V2_ROUTE_MANIFEST_PATH = (
    _REPOSITORY_ROOT / "docs" / "runtime" / "runtime-v2-route-manifest.json"
)
DEFAULT_RUNTIME_V2_OPENAPI_PATH = (
    _REPOSITORY_ROOT / "docs" / "runtime" / "runtime-control.openapi.json"
)

_OWNERS = frozenset({"platform-agent", "runtime-controller"})
_DELIVERIES = frozenset({"handled", "forwarded"})
_METHODS = frozenset({"GET", "POST", "PUT", "DELETE", "PATCH"})
_CONFORMANCE_LEVELS = frozenset({"required-read"})


class RuntimeV2RouteManifestError(ValueError):
    """The checked-in Runtime v2 route contract is missing or invalid."""


@dataclass(frozen=True)
class RuntimeV2Route:
    id: str
    operation_id: str
    owner: str
    delivery: str
    method: str
    path: str
    conformance: str

    @property
    def key(self) -> tuple[str, str]:
        return self.method, self.path


def load_runtime_v2_route_manifest(
    path: Path = DEFAULT_RUNTIME_V2_ROUTE_MANIFEST_PATH,
) -> tuple[RuntimeV2Route, ...]:
    """Load the checked-in route contract without inventing missing state."""

    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 route manifest is unavailable: {path}: {error}"
        ) from error
    try:
        document = json.loads(raw)
    except json.JSONDecodeError as error:
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 route manifest is invalid JSON: {path}: {error}"
        ) from error
    if not isinstance(document, dict):
        raise RuntimeV2RouteManifestError(
            "Runtime v2 route manifest must be a JSON object."
        )
    if document.get("schemaVersion") != 1:
        raise RuntimeV2RouteManifestError(
            "Runtime v2 route manifest schemaVersion must be 1."
        )
    raw_routes = document.get("routes")
    if not isinstance(raw_routes, list) or not raw_routes:
        raise RuntimeV2RouteManifestError(
            "Runtime v2 route manifest routes must be a non-empty array."
        )

    routes: list[RuntimeV2Route] = []
    ids: set[str] = set()
    keys: set[tuple[str, str]] = set()
    for index, raw_route in enumerate(raw_routes):
        route = _parse_route(index, raw_route)
        if route.id in ids:
            raise RuntimeV2RouteManifestError(
                f"Runtime v2 route manifest has duplicate id: {route.id}."
            )
        if route.key in keys:
            raise RuntimeV2RouteManifestError(
                "Runtime v2 route manifest has duplicate method/path: "
                f"{route.method} {route.path}."
            )
        ids.add(route.id)
        keys.add(route.key)
        routes.append(route)
    return tuple(routes)


def validate_runtime_v2_route_manifest_openapi(
    routes: tuple[RuntimeV2Route, ...] | None = None,
    *,
    openapi_path: Path = DEFAULT_RUNTIME_V2_OPENAPI_PATH,
) -> tuple[str, ...]:
    """Return explicit route-contract differences from the neutral OpenAPI."""

    checked_routes = routes if routes is not None else load_runtime_v2_route_manifest()
    try:
        raw = openapi_path.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 OpenAPI contract is unavailable: {openapi_path}: {error}"
        ) from error
    try:
        document = json.loads(raw)
    except json.JSONDecodeError as error:
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 OpenAPI contract is invalid JSON: {openapi_path}: {error}"
        ) from error
    if not isinstance(document, Mapping):
        raise RuntimeV2RouteManifestError(
            "Runtime v2 OpenAPI contract must be a JSON object."
        )
    paths = document.get("paths")
    if not isinstance(paths, Mapping):
        raise RuntimeV2RouteManifestError(
            "Runtime v2 OpenAPI contract paths must be an object."
        )

    issues: list[str] = []
    for route in checked_routes:
        path_item = paths.get(route.path)
        if not isinstance(path_item, Mapping):
            issues.append(f"missing OpenAPI path: {route.path}")
            continue
        operation = path_item.get(route.method.lower())
        if not isinstance(operation, Mapping):
            issues.append(f"missing OpenAPI operation: {route.method} {route.path}")
            continue
        actual_operation_id = operation.get("operationId")
        if actual_operation_id != route.operation_id:
            issues.append(
                "OpenAPI operationId mismatch for "
                f"{route.method} {route.path}: expected {route.operation_id!r}, "
                f"got {actual_operation_id!r}"
            )
    return tuple(issues)


def _parse_route(index: int, raw_route: Any) -> RuntimeV2Route:
    if not isinstance(raw_route, Mapping):
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 route manifest routes[{index}] must be an object."
        )

    values: dict[str, str] = {}
    for field in (
        "id",
        "operationId",
        "owner",
        "delivery",
        "method",
        "path",
        "conformance",
    ):
        value = raw_route.get(field)
        if not isinstance(value, str) or not value:
            raise RuntimeV2RouteManifestError(
                f"Runtime v2 route manifest routes[{index}].{field} must be a non-empty string."
            )
        values[field] = value

    owner = values["owner"]
    delivery = values["delivery"]
    method = values["method"]
    path = values["path"]
    conformance = values["conformance"]
    if owner not in _OWNERS:
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 route manifest routes[{index}].owner is unknown: {owner}."
        )
    if delivery not in _DELIVERIES:
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 route manifest routes[{index}].delivery is unknown: {delivery}."
        )
    if method not in _METHODS:
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 route manifest routes[{index}].method is unknown: {method}."
        )
    if conformance not in _CONFORMANCE_LEVELS:
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 route manifest routes[{index}].conformance is unknown: {conformance}."
        )
    if not path.startswith("/") or path.endswith("/"):
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 route manifest routes[{index}].path must be an absolute non-trailing-slash path."
        )
    if owner == "platform-agent":
        if not path.startswith("/platform") or delivery != "handled":
            raise RuntimeV2RouteManifestError(
                f"Runtime v2 route manifest routes[{index}] must keep Platform Agent routes handled under /platform."
            )
    if owner == "runtime-controller":
        if not path.startswith("/runtime/") or delivery != "forwarded":
            raise RuntimeV2RouteManifestError(
                f"Runtime v2 route manifest routes[{index}] must keep Runtime Controller routes forwarded under /runtime/."
            )
    if conformance == "required-read" and method != "GET":
        raise RuntimeV2RouteManifestError(
            f"Runtime v2 route manifest routes[{index}] required-read route must use GET."
        )
    return RuntimeV2Route(
        id=values["id"],
        operation_id=values["operationId"],
        owner=values["owner"],
        delivery=values["delivery"],
        method=values["method"],
        path=values["path"],
        conformance=values["conformance"],
    )

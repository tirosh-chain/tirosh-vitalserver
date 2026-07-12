from __future__ import annotations

import json
from pathlib import Path

import pytest

from tirosh_vitalserver.devtools.runtime_v2_conformance import RuntimeV2ConformanceSuite
from tirosh_vitalserver.devtools.runtime_v2_route_manifest import (
    RuntimeV2Route,
    RuntimeV2RouteManifestError,
    load_runtime_v2_route_manifest,
    validate_runtime_v2_route_manifest_openapi,
)


def test_checked_in_manifest_declares_the_owner_neutral_read_core() -> None:
    routes = load_runtime_v2_route_manifest()

    assert [
        (
            route.id,
            route.operation_id,
            route.owner,
            route.delivery,
            route.method,
            route.path,
        )
        for route in routes
    ] == [
        (
            "platform-state",
            "getPlatformState",
            "platform-agent",
            "handled",
            "GET",
            "/platform",
        ),
        (
            "platform-capabilities",
            "getPlatformCapabilities",
            "platform-agent",
            "handled",
            "GET",
            "/platform/capabilities",
        ),
        (
            "platform-operations",
            "getPlatformOperationState",
            "platform-agent",
            "handled",
            "GET",
            "/platform/operations",
        ),
        (
            "platform-runtime-endpoint",
            "getHostRuntimeGuestAddress",
            "platform-agent",
            "handled",
            "GET",
            "/platform/runtime-endpoint",
        ),
        (
            "platform-runtime-provider",
            "getHostRuntimeVMLifecycle",
            "platform-agent",
            "handled",
            "GET",
            "/platform/runtime-provider",
        ),
        (
            "runtime-capabilities",
            "getRuntimeCapabilities",
            "runtime-controller",
            "forwarded",
            "GET",
            "/runtime/capabilities",
        ),
        (
            "runtime-services",
            "listRuntimeGuestServices",
            "runtime-controller",
            "forwarded",
            "GET",
            "/runtime/services",
        ),
        (
            "runtime-stack",
            "getRuntimeGuestStackStatus",
            "runtime-controller",
            "forwarded",
            "GET",
            "/runtime/stack",
        ),
    ]


def test_manifest_read_core_matches_the_neutral_openapi() -> None:
    assert validate_runtime_v2_route_manifest_openapi() == ()


def test_manifest_reports_openapi_operation_id_drift() -> None:
    route = RuntimeV2Route(
        id="platform-state",
        operation_id="unexpectedOperation",
        owner="platform-agent",
        delivery="handled",
        method="GET",
        path="/platform",
        conformance="required-read",
    )

    assert validate_runtime_v2_route_manifest_openapi((route,)) == (
        "OpenAPI operationId mismatch for GET /platform: expected "
        "'unexpectedOperation', got 'getPlatformState'",
    )


def test_manifest_does_not_fallback_when_a_required_field_is_missing(
    tmp_path: Path,
) -> None:
    path = tmp_path / "routes.json"
    path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "routes": [
                    {
                        "id": "runtime-capabilities",
                        "operationId": "getRuntimeCapabilities",
                        "owner": "runtime-controller",
                        "delivery": "forwarded",
                        "method": "GET",
                        "path": "/runtime/capabilities",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(RuntimeV2RouteManifestError, match="conformance"):
        load_runtime_v2_route_manifest(path)


def test_manifest_rejects_duplicate_route_keys(tmp_path: Path) -> None:
    path = tmp_path / "routes.json"
    route = {
        "id": "runtime-capabilities",
        "operationId": "getRuntimeCapabilities",
        "owner": "runtime-controller",
        "delivery": "forwarded",
        "method": "GET",
        "path": "/runtime/capabilities",
        "conformance": "required-read",
    }
    path.write_text(
        json.dumps({"schemaVersion": 1, "routes": [route, {**route, "id": "copy"}]}),
        encoding="utf-8",
    )

    with pytest.raises(RuntimeV2RouteManifestError, match="duplicate method/path"):
        load_runtime_v2_route_manifest(path)


def test_suite_rejects_required_route_without_a_validator() -> None:
    route = RuntimeV2Route(
        id="unmapped",
        operation_id="getUnmapped",
        owner="runtime-controller",
        delivery="forwarded",
        method="GET",
        path="/runtime/unmapped",
        conformance="required-read",
    )

    with pytest.raises(RuntimeError, match="no conformance validator"):
        RuntimeV2ConformanceSuite(lambda _: {}, routes=(route,)).run(
            platform=False, runtime=True
        )

from __future__ import annotations

import pytest
from fastapi import HTTPException

from tests.support import fake_socketio_connector
from tirosh_vitalserver.testkit.adapters.inbound.api import create_testkit_app
from tirosh_vitalserver.testkit.application.bed_registry import BedRegistry
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
)
from tirosh_vitalserver.testkit.schemas import (
    CreateBedsRequest,
    RestartVirtualRecorderSessionRequest,
    StartVirtualRecordersRequest,
)


def test_sessions_endpoint_uses_manager_dependency_not_query_parameter() -> None:
    app = create_testkit_app()

    route = next(
        route
        for route in app.routes
        if getattr(route, "path", None) == "/sessions"
        and "GET" in getattr(route, "methods", set())
    )

    assert [field.name for field in route.dependant.query_params] == []
    assert [dependency.name for dependency in route.dependant.dependencies] == [
        "manager"
    ]


def test_bed_registry_endpoint_creates_explicit_bed_identities() -> None:
    route = route_for("/beds", "POST")
    registry = BedRegistry()

    response = route.endpoint(
        CreateBedsRequest(roomNames=("OR-A", "OR-B")),
        registry,
    )

    beds = response["beds"]
    assert len(beds) == 2
    assert beds[0]["roomName"] == "OR-A"
    assert len(beds[0]["bedId"]) == 40


def test_bed_registry_endpoints_list_and_reset_registered_beds() -> None:
    registry = BedRegistry()
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    create_route = route_for("/beds", "POST")
    list_route = route_for("/beds", "GET")
    reset_route = route_for("/beds", "DELETE")

    create_route.endpoint(CreateBedsRequest(roomNames=("OR-A",)), registry)

    listed = list_route.endpoint(registry)
    assert [bed["roomName"] for bed in listed["beds"]] == ["OR-A"]

    deleted = reset_route.endpoint(registry, manager)
    assert [bed["roomName"] for bed in deleted["beds"]] == ["OR-A"]
    assert list_route.endpoint(registry) == {"beds": []}


def test_bed_registry_endpoint_merges_by_room_name() -> None:
    route = route_for("/beds", "POST")
    registry = BedRegistry()

    first = route.endpoint(CreateBedsRequest(roomNames=("OR-A",)), registry)
    second = route.endpoint(CreateBedsRequest(roomNames=(" OR-A ",)), registry)

    assert first == second
    assert len(second["beds"]) == 1


def test_sessions_endpoint_rejects_missing_bed_room_names() -> None:
    route = route_for("/sessions", "POST")
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    registry = BedRegistry()

    with pytest.raises(HTTPException) as exc_info:
        route.endpoint(
            StartVirtualRecordersRequest(
                targetUrl="http://example.test",
                recorders=1,
                bedRoomNames=(),
                maxMessages=1,
            ),
            manager,
            registry,
        )

    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "bed_room_names is required"


def test_sessions_endpoint_requires_registered_bed_room_names() -> None:
    route = route_for("/sessions", "POST")
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    registry = BedRegistry()

    with pytest.raises(HTTPException) as exc_info:
        route.endpoint(
            StartVirtualRecordersRequest(
                targetUrl="http://example.test",
                recorders=1,
                bedRoomNames=("OR-A",),
                maxMessages=1,
            ),
            manager,
            registry,
        )

    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "bed room names are not registered: OR-A"


def test_sessions_endpoint_rejects_active_bed_reuse() -> None:
    route = route_for("/sessions", "POST")
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    registry = BedRegistry()
    registry.create_beds(room_names=("OR-A", "OR-B"))

    first = route.endpoint(
        StartVirtualRecordersRequest(
            targetUrl="http://example.test",
            recorders=1,
            bedRoomNames=("OR-A",),
            intervalSeconds=1,
        ),
        manager,
        registry,
    )
    try:
        with pytest.raises(HTTPException) as exc_info:
            route.endpoint(
                StartVirtualRecordersRequest(
                    targetUrl="http://example.test",
                    recorders=1,
                    bedRoomNames=("OR-A",),
                    intervalSeconds=1,
                ),
                manager,
                registry,
            )

        assert exc_info.value.status_code == 409
        assert exc_info.value.detail == "bed room names are already assigned: OR-A"
    finally:
        manager.delete_session(first["id"])


def test_bed_registry_reset_rejects_active_assignments() -> None:
    start_route = route_for("/sessions", "POST")
    reset_route = route_for("/beds", "DELETE")
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    registry = BedRegistry()
    registry.create_beds(room_names=("OR-A",))

    first = start_route.endpoint(
        StartVirtualRecordersRequest(
            targetUrl="http://example.test",
            recorders=1,
            bedRoomNames=("OR-A",),
            intervalSeconds=1,
        ),
        manager,
        registry,
    )
    try:
        with pytest.raises(HTTPException) as exc_info:
            reset_route.endpoint(registry, manager)

        assert exc_info.value.status_code == 409
        assert (
            exc_info.value.detail
            == "active bed assignments must be stopped before reset: OR-A"
        )
    finally:
        manager.delete_session(first["id"])


def test_session_endpoint_restarts_stopped_session_on_selected_bed() -> None:
    start_route = route_for("/sessions", "POST")
    restart_route = route_for("/sessions/{session_id}/restart", "POST")
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    registry = BedRegistry()
    registry.create_beds(room_names=("OR-A", "OR-B"))

    first = start_route.endpoint(
        StartVirtualRecordersRequest(
            targetUrl="http://example.test",
            vrcode="VR_REUSE",
            recorders=1,
            bedRoomNames=("OR-A",),
            maxMessages=1,
        ),
        manager,
        registry,
    )
    assert manager.wait_session(first["id"], timeout=5)

    restarted = restart_route.endpoint(
        first["id"],
        RestartVirtualRecorderSessionRequest(bedRoomNames=("OR-B",)),
        manager,
        registry,
    )

    assert restarted["id"] != first["id"]
    assert restarted["vrcode"] == "VR_REUSE"
    assert restarted["bedRoomNames"] == ("OR-B",)


def route_for(path: str, method: str):
    app = create_testkit_app()
    return next(
        route
        for route in app.routes
        if getattr(route, "path", None) == path
        and method in getattr(route, "methods", set())
    )

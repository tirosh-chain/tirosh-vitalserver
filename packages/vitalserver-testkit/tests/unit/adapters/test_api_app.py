from __future__ import annotations

import pytest
from fastapi import HTTPException
from fastapi.routing import APIRoute

from tests.support import fake_socketio_connector
from tirosh_vitalserver.testkit.adapters.inbound.api import create_testkit_app
from tirosh_vitalserver.testkit.application.bed_registry import BedRegistry
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
)
from tirosh_vitalserver.testkit.schemas import (
    CreateBedsRequest,
    DeleteBedsRequest,
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
    assert isinstance(route, APIRoute)

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


def test_bed_registry_endpoint_can_create_exact_prefix_without_random_suffix() -> None:
    route = route_for("/beds", "POST")
    registry = BedRegistry()

    response = route.endpoint(
        CreateBedsRequest(
            count=1,
            prefix="MORC03",
            appendRandomSuffix=False,
        ),
        registry,
    )

    assert [bed["roomName"] for bed in response["beds"]] == ["MORC03"]


def test_bed_registry_endpoint_rejects_multiple_exact_prefix_beds() -> None:
    with pytest.raises(ValueError) as exc_info:
        CreateBedsRequest(count=2, prefix="MORC03", appendRandomSuffix=False)

    assert "appendRandomSuffix=false requires count to be 1" in str(exc_info.value)


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


def test_bed_registry_endpoint_deletes_selected_beds() -> None:
    registry = BedRegistry()
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    create_route = route_for("/beds", "POST")
    list_route = route_for("/beds", "GET")
    delete_route = route_for("/beds/delete", "POST")

    create_route.endpoint(CreateBedsRequest(roomNames=("OR-A", "OR-B")), registry)

    deleted = delete_route.endpoint(
        DeleteBedsRequest(roomNames=("OR-A",)),
        registry,
        manager,
    )

    assert [bed["roomName"] for bed in deleted["beds"]] == ["OR-A"]
    listed = list_route.endpoint(registry)
    assert [bed["roomName"] for bed in listed["beds"]] == ["OR-B"]


def test_bed_registry_endpoint_merges_by_room_name() -> None:
    route = route_for("/beds", "POST")
    registry = BedRegistry()

    first = route.endpoint(CreateBedsRequest(roomNames=("OR-A",)), registry)
    second = route.endpoint(CreateBedsRequest(roomNames=(" OR-A ",)), registry)

    assert first == second
    assert len(second["beds"]) == 1


def test_bed_registry_create_endpoint_returns_only_created_beds() -> None:
    route = route_for("/beds", "POST")
    list_route = route_for("/beds", "GET")
    registry = BedRegistry()

    route.endpoint(CreateBedsRequest(roomNames=("OR-A",)), registry)

    created = route.endpoint(CreateBedsRequest(roomNames=("OR-B",)), registry)
    listed = list_route.endpoint(registry)

    assert [bed["roomName"] for bed in created["beds"]] == ["OR-B"]
    assert [bed["roomName"] for bed in listed["beds"]] == ["OR-A", "OR-B"]


def test_sessions_endpoint_rejects_missing_bed_room_names() -> None:
    with pytest.raises(ValueError) as exc_info:
        StartVirtualRecordersRequest(
            targetUrl="http://example.test",
            recorderCount=1,
            bedroomName=" ",
            maxMessages=1,
        ).to_session_request()

    assert "bedroom_name must not be empty" in str(exc_info.value)


def test_sessions_endpoint_requires_registered_bed_room_names() -> None:
    route = route_for("/sessions", "POST")
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    registry = BedRegistry()

    with pytest.raises(HTTPException) as exc_info:
        route.endpoint(
            StartVirtualRecordersRequest(
                targetUrl="http://example.test",
                recorderCount=1,
                bedroomName="OR-A",
                maxMessages=1,
            ),
            manager,
            registry,
        )

    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "bed room names are not registered: OR-A"


def test_sessions_endpoint_accepts_purpose_scenario() -> None:
    route = route_for("/sessions", "POST")
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    registry = BedRegistry()
    registry.create_beds(room_names=("OR-A",))

    response = route.endpoint(
        StartVirtualRecordersRequest(
            targetUrl="http://example.test",
            recorderCount=1,
            bedroomName="OR-A",
            maxMessages=1,
            scenario="hct_decreasing",
        ),
        manager,
        registry,
    )
    try:
        assert response["scenario"] == "hct_decreasing"
        assert response["bedroomName"] == "OR-A"
        assert manager.wait_session(response["id"], timeout=5)
    finally:
        manager.delete_session(response["id"])


def test_scenarios_endpoint_describes_purpose_centered_scenarios() -> None:
    route = route_for("/scenarios", "GET")

    response = route.endpoint()

    scenarios = {
        scenario["scenario"]: scenario
        for scenario in response["scenarios"]
    }
    assert "bloodbag_transfusion" in scenarios
    assert scenarios["bloodbag_transfusion"]["title"] == "Bloodbag transfusion"
    assert scenarios["bloodbag_transfusion"]["situation"]
    assert scenarios["bloodbag_transfusion"]["purpose"]


def test_sessions_endpoint_rejects_active_bed_reuse() -> None:
    route = route_for("/sessions", "POST")
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    registry = BedRegistry()
    registry.create_beds(room_names=("OR-A", "OR-B"))

    first = route.endpoint(
            StartVirtualRecordersRequest(
                targetUrl="http://example.test",
                recorderCount=1,
                bedroomName="OR-A",
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
                    recorderCount=1,
                    bedroomName="OR-A",
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
            recorderCount=1,
            bedroomName="OR-A",
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


def test_bed_registry_delete_rejects_active_assignments() -> None:
    start_route = route_for("/sessions", "POST")
    delete_route = route_for("/beds/delete", "POST")
    manager = VirtualRecorderSessionManager(connector=fake_socketio_connector)
    registry = BedRegistry()
    registry.create_beds(room_names=("OR-A",))

    first = start_route.endpoint(
        StartVirtualRecordersRequest(
            targetUrl="http://example.test",
            recorderCount=1,
            bedroomName="OR-A",
            intervalSeconds=1,
        ),
        manager,
        registry,
    )
    try:
        with pytest.raises(HTTPException) as exc_info:
            delete_route.endpoint(
                DeleteBedsRequest(roomNames=("OR-A",)),
                registry,
                manager,
            )

        assert exc_info.value.status_code == 409
        assert (
            exc_info.value.detail
            == "active bed assignments must be stopped before delete: OR-A"
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
            recorderCount=1,
            bedroomName="OR-A",
            maxMessages=1,
        ),
        manager,
        registry,
    )
    assert manager.wait_session(first["id"], timeout=5)

    restarted = restart_route.endpoint(
        first["id"],
        RestartVirtualRecorderSessionRequest(bedroomName="OR-B"),
        manager,
        registry,
    )

    assert restarted["id"] != first["id"]
    assert restarted["vrcode"] == "VR_REUSE"
    assert restarted["bedroomName"] == "OR-B"


def route_for(path: str, method: str) -> APIRoute:
    app = create_testkit_app()
    route = next(
        route
        for route in app.routes
        if getattr(route, "path", None) == path
        and method in getattr(route, "methods", set())
    )
    assert isinstance(route, APIRoute)
    return route

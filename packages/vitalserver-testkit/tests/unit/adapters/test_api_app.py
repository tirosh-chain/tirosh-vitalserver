from __future__ import annotations

from tirosh_vitalserver.testkit.adapters.inbound.api import create_testkit_app


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

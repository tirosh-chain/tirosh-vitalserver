from __future__ import annotations

from tirosh_vitalserver.recorder_recovery.adapters.inbound.api.app import (
    create_recorder_recovery_app,
)
from tirosh_vitalserver.recorder_recovery.adapters.inbound.cli import build_parser


def test_cli_registers_product_recovery_commands() -> None:
    parser = build_parser()

    parsed = parser.parse_args(["serve", "--host", "127.0.0.1", "--port", "18082"])

    assert parsed.command_name == "serve"
    assert parsed.host == "127.0.0.1"
    assert parsed.port == 18082


def test_api_exposes_health_and_recovery_endpoint() -> None:
    app = create_recorder_recovery_app()
    routes = {(route.path, tuple(sorted(route.methods))) for route in app.routes}

    assert ("/health", ("GET",)) in routes
    assert ("/raw-archive/recover-vital", ("POST",)) in routes

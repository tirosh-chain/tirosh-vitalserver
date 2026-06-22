"""VitalServer lifecycle CLI commands."""

from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_vitalserver.testkit.adapters.inbound.cli.common import (
    add_common_server_args,
)
from tirosh_vitalserver.testkit.adapters.outbound.bed_registry_store import (
    JsonFileBedRegistryStore,
)
from tirosh_vitalserver.testkit.adapters.outbound.session_store import (
    JsonFileVirtualRecorderSessionStore,
)
from tirosh_vitalserver.testkit.adapters.outbound.vital_artifact import (
    VitalDbSessionVitalFileExporter,
    VitalServerSessionVitalFileUploader,
)
from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.usecases import wait_for_server
from tirosh_vitalserver.testkit.configuration.bed_registry_config import (
    load_bed_registry_state_path,
)
from tirosh_vitalserver.testkit.configuration.logging_config import (
    configure_testkit_logging,
)
from tirosh_vitalserver.testkit.configuration.session_config import (
    load_session_artifact_dir,
    load_session_state_path,
)
from tirosh_vitalserver.testkit.observability import (
    emit_testkit_event,
)


def add_server_parsers(
    subparsers: argparse._SubParsersAction[argparse.ArgumentParser],
) -> None:
    """Register VitalServer lifecycle and readiness commands."""

    parser = subparsers.add_parser(
        "health",
        help="Wait for VitalServer health endpoint",
    )

    add_common_server_args(parser)

    parser.add_argument("--path", default="/check", help="Health endpoint path")
    parser.add_argument("--wait", type=float, default=60.0, help="Max seconds to wait")
    parser.add_argument(
        "--interval",
        type=float,
        default=1.0,
        help="Polling interval seconds",
    )

    parser.set_defaults(command=run_health)

    serve_parser = subparsers.add_parser(
        "serve",
        help="Run the TestKit API server",
        description="Run the loopback TestKit API server for virtual VRecorders.",
    )
    serve_parser.add_argument(
        "--config",
        type=Path,
        default=Path("config/testkit.toml"),
        help="TestKit TOML config path. Reads the [logging] dictConfig table.",
    )
    serve_parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Host/interface for the TestKit API server",
    )
    serve_parser.add_argument(
        "--port",
        type=int,
        default=18322,
        help="Port for the TestKit API server",
    )
    serve_parser.add_argument(
        "--log-level",
        default="info",
        choices=["critical", "error", "warning", "info", "debug", "trace"],
        help="Uvicorn log level",
    )
    serve_parser.set_defaults(command=run_serve)


def run_health(args: argparse.Namespace) -> int:
    """Wait until the configured VitalServer health endpoint responds."""

    client = VitalServerClient(args.vitalserver_url, timeout=args.timeout)

    wait_for_server(
        client,
        path=args.path,
        timeout_seconds=args.wait,
        interval_seconds=args.interval,
    )

    print(f"VitalServer is ready: {args.vitalserver_url}{args.path}")

    return 0


def run_serve(args: argparse.Namespace) -> int:
    """Run the FastAPI TestKit server."""

    configure_testkit_logging(config_path=args.config)
    emit_testkit_event(
        "server.starting",
        host=args.host,
        port=args.port,
        uvicorn_log_level=args.log_level,
    )

    try:
        import uvicorn
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "uvicorn is required to run the TestKit API server"
        ) from exc

    from tirosh_vitalserver.testkit.adapters.inbound.api import (
        create_testkit_app,
    )

    session_state_path = load_session_state_path(args.config)
    session_artifact_dir = load_session_artifact_dir(args.config)
    bed_registry_state_path = load_bed_registry_state_path(args.config)
    emit_testkit_event(
        "session_store.configured",
        state_path=str(session_state_path),
    )
    emit_testkit_event(
        "session_artifact_store.configured",
        artifact_dir=str(session_artifact_dir),
    )
    emit_testkit_event(
        "bed_registry_store.configured",
        state_path=str(bed_registry_state_path),
    )

    uvicorn.run(
        create_testkit_app(
            session_store=JsonFileVirtualRecorderSessionStore(session_state_path),
            bed_registry_store=JsonFileBedRegistryStore(bed_registry_state_path),
            vital_file_exporter=VitalDbSessionVitalFileExporter(
                session_artifact_dir,
            ),
            vital_file_uploader=VitalServerSessionVitalFileUploader(),
        ),
        host=args.host,
        port=args.port,
        log_level=args.log_level,
    )

    return 0

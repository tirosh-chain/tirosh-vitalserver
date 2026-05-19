"""HTTP status page for simulated Vital Recorder runtime state."""

from __future__ import annotations

import html
import json
import time
from dataclasses import asdict
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from typing import Any, ClassVar, cast

from tirosh_vitalserver.testkit.application.recorder_runtime import (
    RecorderRuntimeRegistry,
    RecorderRuntimeSnapshot,
)


class RecorderStatusServer:
    """Small HTTP server exposing runtime state for Network Settings checks."""

    def __init__(
        self,
        *,
        host: str,
        port: int,
        registry: RecorderRuntimeRegistry,
    ) -> None:
        self._server = build_status_http_server(host=host, port=port, registry=registry)
        self._thread = Thread(target=self._server.serve_forever, daemon=True)

    @property
    def url(self) -> str:
        """Return the bound status page URL."""

        host, port = cast(tuple[str, int], self._server.server_address[:2])
        display_host = "127.0.0.1" if host in ("", "0.0.0.0") else host

        return f"http://{display_host}:{port}"

    def start(self) -> None:
        """Start serving status requests."""

        self._thread.start()

    def stop(self) -> None:
        """Stop serving status requests."""

        self._server.shutdown()
        self._thread.join(timeout=5)
        self._server.server_close()


def build_status_http_server(
    *,
    host: str,
    port: int,
    registry: RecorderRuntimeRegistry,
) -> ThreadingHTTPServer:
    """Build a status HTTP server bound to one registry."""

    class StatusHandler(RecorderStatusHandler):
        runtime_registry = registry

    return ThreadingHTTPServer((host, port), StatusHandler)


class RecorderStatusHandler(BaseHTTPRequestHandler):
    """Render recorder runtime state as HTML or JSON."""

    runtime_registry: ClassVar[RecorderRuntimeRegistry]

    def do_GET(self) -> None:
        """Handle status page requests."""

        if self.path == "/status.json":
            self.write_json()
            return

        self.write_html()

    def write_json(self) -> None:
        """Write runtime state as JSON."""

        payload = {
            "generated_at": time.time(),
            "recorders": [
                snapshot_to_json(snapshot)
                for snapshot in self.runtime_registry.snapshots()
            ],
        }
        body = json.dumps(payload, indent=2, sort_keys=True, default=str).encode()

        self.send_response(200)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def write_html(self) -> None:
        """Write runtime state as a compact human-readable HTML page."""

        snapshots = self.runtime_registry.snapshots()
        body = render_status_html(snapshots).encode()

        self.send_response(200)
        self.send_header("content-type", "text/html; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        """Silence request logging; CLI prints the status URL explicitly."""

        return


def snapshot_to_json(snapshot: RecorderRuntimeSnapshot) -> dict[str, Any]:
    """Convert one snapshot to a JSON-friendly dict."""

    data = asdict(snapshot)
    data["management_events"] = [
        {
            "name": event.name,
            "received_at": event.received_at,
            "payload": event.payload,
        }
        for event in snapshot.management_events
    ]

    return data


def render_status_html(snapshots: tuple[RecorderRuntimeSnapshot, ...]) -> str:
    """Render a basic status page."""

    rows = "\n".join(render_recorder_section(snapshot) for snapshot in snapshots)
    if not rows:
        rows = "<p>No recorder has connected yet.</p>"

    return f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>VRecorder Testkit Status</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 24px; }}
    h1 {{ font-size: 24px; }}
    h2 {{ font-size: 18px; margin-top: 24px; }}
    table {{ border-collapse: collapse; margin: 12px 0; min-width: 520px; }}
    th, td {{ border: 1px solid #ddd; padding: 6px 8px; text-align: left; }}
    th {{ background: #f5f5f5; }}
    code {{ background: #f5f5f5; padding: 2px 4px; }}
  </style>
</head>
<body>
  <h1>VRecorder Testkit Status</h1>
  <p>JSON: <a href="/status.json">/status.json</a></p>
  {rows}
</body>
</html>
"""


def render_recorder_section(snapshot: RecorderRuntimeSnapshot) -> str:
    """Render one recorder snapshot."""

    fields = {
        "vrcode": snapshot.vrcode,
        "base_url": snapshot.base_url,
        "local_ip": snapshot.local_ip,
        "connected": snapshot.connected,
        "join_sent": snapshot.join_sent,
        "joined_at": format_timestamp(snapshot.joined_at),
        "server_dt": snapshot.server_dt,
        "server_dt_received_at": format_timestamp(snapshot.server_dt_received_at),
        "last_reconnect_at": format_timestamp(snapshot.last_reconnect_at),
        "last_send_data_at": format_timestamp(snapshot.last_send_data_at),
        "messages_sent": snapshot.messages_sent,
        "bytes_sent": snapshot.bytes_sent,
    }
    field_rows = "\n".join(
        f"<tr><th>{escape(key)}</th><td>{escape(value)}</td></tr>"
        for key, value in fields.items()
    )
    event_rows = "\n".join(
        "<tr>"
        f"<td>{escape(event.name)}</td>"
        f"<td>{escape(format_timestamp(event.received_at))}</td>"
        f"<td><code>{escape(event.payload)}</code></td>"
        "</tr>"
        for event in snapshot.management_events
    )
    if not event_rows:
        event_rows = "<tr><td colspan=\"3\">No management event received.</td></tr>"

    return f"""<section>
  <h2>{escape(snapshot.vrcode)}</h2>
  <table>{field_rows}</table>
  <h3>Management Events</h3>
  <table>
    <tr><th>event</th><th>received_at</th><th>payload</th></tr>
    {event_rows}
  </table>
</section>"""


def format_timestamp(value: float | None) -> str:
    """Format a Unix timestamp for display."""

    if value is None:
        return "N/A"

    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(value))


def escape(value: object) -> str:
    """HTML-escape one display value."""

    return html.escape(str(value))

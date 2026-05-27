from __future__ import annotations

import json
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

from .collector import VitalDBCollector
from .config import ObserverSettings, load_settings
from .diagnostics import write_diagnostic_event
from .redis_client import RedisClient, RedisEndpoint
from .time import utc_now_iso


class ObserverServer(ThreadingHTTPServer):
    def __init__(
        self, server_address: tuple[str, int], settings: ObserverSettings
    ) -> None:
        super().__init__(server_address, ObserverRequestHandler)
        self.settings = settings
        self.collector = VitalDBCollector(
            redis_client=RedisClient(
                RedisEndpoint(
                    host=settings.redis_host,
                    port=settings.redis_port,
                    timeout_seconds=settings.redis_timeout_seconds,
                )
            ),
            settings=settings,
        )


class ObserverRequestHandler(BaseHTTPRequestHandler):
    server: ObserverServer

    def do_GET(self) -> None:
        if self.path == "/health":
            self._json({"status": "ok", "observedAt": utc_now_iso()})
            return
        if self.path == "/ready":
            self._ready()
            return
        if self.path == "/api/v1/observations":
            self._observations()
            return
        self._json({"error": "not_found"}, status=HTTPStatus.NOT_FOUND)

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _ready(self) -> None:
        try:
            ready = self.server.collector.ready()
        except Exception as error:
            write_diagnostic_event(
                "readiness_failed",
                status=HTTPStatus.SERVICE_UNAVAILABLE.value,
                error=str(error),
            )
            self._json(
                {"ready": False, "observedAt": utc_now_iso(), "error": str(error)},
                status=HTTPStatus.SERVICE_UNAVAILABLE,
            )
            return
        status = HTTPStatus.OK if ready else HTTPStatus.SERVICE_UNAVAILABLE
        self._json({"ready": ready, "observedAt": utc_now_iso()}, status=status)

    def _observations(self) -> None:
        started_at = time.monotonic()
        try:
            document = self.server.collector.collect().as_json()
        except Exception as error:
            threshold = self.server.settings.recorder_online_threshold_seconds
            duration_ms = int((time.monotonic() - started_at) * 1000)
            write_diagnostic_event(
                "observation_failed",
                status=HTTPStatus.SERVICE_UNAVAILABLE.value,
                durationMs=duration_ms,
                error=str(error),
            )
            self._json(
                {
                    "schemaVersion": 1,
                    "source": "vitaldb-observer",
                    "observedAt": utc_now_iso(),
                    "ready": False,
                    "recorderOnlineThresholdSeconds": threshold,
                    "recorders": [],
                    "beds": [],
                    "devices": [],
                    "filters": [],
                    "proxyConnections": [],
                    "anomalies": [
                        {
                            "id": "observer-unhealthy",
                            "kind": "observer-unhealthy",
                            "severity": "critical",
                            "observedAt": utc_now_iso(),
                            "subject": "vitaldb-observer",
                            "message": str(error),
                        }
                    ],
                },
                status=HTTPStatus.SERVICE_UNAVAILABLE,
            )
            return
        duration_ms = int((time.monotonic() - started_at) * 1000)
        recorder_counts = _recorder_counts(document)
        write_diagnostic_event(
            "observation_collected",
            status=HTTPStatus.OK.value,
            durationMs=duration_ms,
            ready=document["ready"],
            recorderCount=len(document["recorders"]),
            onlineRecorderCount=recorder_counts["online"],
            staleRecorderCount=recorder_counts["stale"],
            bedCount=len(document["beds"]),
            proxyConnectionCount=len(document["proxyConnections"]),
            anomalyCount=len(document["anomalies"]),
        )
        self._json(document)

    def _json(
        self, payload: dict[str, Any], status: HTTPStatus = HTTPStatus.OK
    ) -> None:
        body = json.dumps(payload, sort_keys=True).encode()
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _recorder_counts(document: dict[str, Any]) -> dict[str, int]:
    counts = {"online": 0, "stale": 0}
    recorders = document.get("recorders")
    if not isinstance(recorders, list):
        return counts
    for recorder in recorders:
        if not isinstance(recorder, dict):
            continue
        if recorder.get("online") is True:
            counts["online"] += 1
        if recorder.get("stale") is True:
            counts["stale"] += 1
    return counts


def main() -> None:
    settings = load_settings()
    server = ObserverServer((settings.host, settings.port), settings)
    write_diagnostic_event(
        "server_started",
        host=settings.host,
        port=settings.port,
        redisHost=settings.redis_host,
        redisPort=settings.redis_port,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()

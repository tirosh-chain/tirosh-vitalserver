from __future__ import annotations

from collections.abc import Callable, Iterator
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from threading import Thread
from typing import Any, ClassVar, cast

from tirosh_vitalserver.testkit.application.ports import SocketIoClientPort


class FakeSocketIoClient:
    connected = True
    emitted: list[tuple[str, Any]]
    handlers: dict[str, Callable[..., None]]

    def __init__(self) -> None:
        self.emitted = []
        self.handlers = {}

    def emit(self, event: str, data: Any = None) -> None:
        self.emitted.append((event, data))
        return

    def on(self, event: str, handler: Callable[..., None]) -> None:
        self.handlers[event] = handler
        return

    def sleep(self, seconds: float) -> None:
        return

    def disconnect(self) -> None:
        self.connected = False


def fake_socketio_connector(
    base_url: str,
    *,
    timeout: float = 30.0,
) -> SocketIoClientPort:
    return FakeSocketIoClient()


class RecordingHttpHandler(BaseHTTPRequestHandler):
    requests: ClassVar[list[tuple[str, str, int, bytes]]] = []

    def do_POST(self) -> None:
        content_length = int(self.headers["Content-Length"])
        body = self.rfile.read(content_length)
        RecordingHttpHandler.requests.append(
            (
                self.path,
                self.headers["Content-Type"],
                content_length,
                body,
            )
        )

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Success")

    def log_message(self, format: str, *args: object) -> None:
        return


@contextmanager
def recording_http_server() -> Iterator[ThreadingHTTPServer]:
    RecordingHttpHandler.requests = []
    server = ThreadingHTTPServer(("127.0.0.1", 0), RecordingHttpHandler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        yield server
    finally:
        server.shutdown()
        thread.join(timeout=5)


def server_url(server: ThreadingHTTPServer) -> str:
    host, port = cast(tuple[str, int], server.server_address)

    return f"http://{host}:{port}"

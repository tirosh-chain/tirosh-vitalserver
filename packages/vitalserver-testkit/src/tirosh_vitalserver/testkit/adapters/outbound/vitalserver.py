"""HTTP client helpers for VitalServer transfer tests."""

from __future__ import annotations

import http.client
import json
import mimetypes
import time
from collections.abc import Mapping
from pathlib import Path
from urllib.parse import urlencode, urljoin, urlparse
from uuid import uuid4

from tirosh_vitalserver.testkit.schemas.http import HttpResponse
from tirosh_vitalserver.testkit.types.json import JsonValue


class VitalServerClient:
    """Minimal VitalServer API client.

    The client intentionally uses the Python standard library so load tests do
    not depend on a third-party HTTP stack. It supports the documented
    VitalDB/VitalServer form APIs and streaming multipart uploads for `.vital`
    files.
    """

    def __init__(
        self,
        base_url: str = "http://localhost:8080",
        timeout: float = 30.0,
    ) -> None:
        self.base_url = base_url.rstrip("/") + "/"
        self.timeout = timeout

    def health(self, path: str = "/check") -> HttpResponse:
        return self.get(path)

    def login(self, user_id: str, password: str) -> HttpResponse:
        return self.post_form("/api/login", {"id": user_id, "pw": password})

    def filelist(self, access_token: str, **filters: str | int) -> HttpResponse:
        params = {"access_token": access_token, **filters}
        return self.get("/api/filelist", params=params)

    def tracklist(self, access_token: str, **filters: str | int) -> HttpResponse:
        params = {"access_token": access_token, **filters}
        return self.get("/api/tracklist", params=params)

    def download(self, access_token: str, filename: str) -> HttpResponse:
        return self.get(
            "/api/download", params={"access_token": access_token, "filename": filename}
        )

    def device_metadata(self, bed_id: str) -> HttpResponse:
        return self.post_json("/vr_devs", {"bedid": bed_id})

    def filter_metadata(self, bed_id: str) -> HttpResponse:
        return self.post_json("/vr_filts", {"bedid": bed_id})

    def upload_vital_file(
        self,
        path: str | Path,
        *,
        vrcode: str | None = None,
        endpoint: str = "/upload",
        form_fields: Mapping[str, str] | None = None,
    ) -> HttpResponse:
        fields = dict(form_fields or {})

        if vrcode is not None:
            fields["vrcode"] = vrcode

        return self.post_multipart_file(
            endpoint,
            file_path=path,
            file_field="vitalfile",
            form_fields=fields,
        )

    def send_recorder_payload(
        self,
        payload: Mapping[str, JsonValue],
        *,
        endpoint: str = "/api/send",
    ) -> HttpResponse:
        return self.post_json(endpoint, payload)

    def get(
        self, path: str, params: Mapping[str, str | int] | None = None
    ) -> HttpResponse:
        request_path = self._request_path(path, params)
        return self._request("GET", request_path)

    def post_form(self, path: str, fields: Mapping[str, str]) -> HttpResponse:
        body = urlencode(fields).encode("utf-8")

        headers = {
            "Content-Type": "application/x-www-form-urlencoded",
            "Content-Length": str(len(body)),
        }

        return self._request(
            "POST", self._request_path(path), body=body, headers=headers
        )

    def post_json(self, path: str, payload: Mapping[str, JsonValue]) -> HttpResponse:
        body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode(
            "utf-8"
        )

        headers = {
            "Content-Type": "application/json",
            "Content-Length": str(len(body)),
        }

        return self._request(
            "POST", self._request_path(path), body=body, headers=headers
        )

    def post_multipart_file(
        self,
        path: str,
        *,
        file_path: str | Path,
        file_field: str,
        form_fields: Mapping[str, str],
    ) -> HttpResponse:
        file_path = Path(file_path)
        boundary = f"----tirosh-vitalserver-{uuid4().hex}"

        file_header, file_footer = self._multipart_file_boundaries(
            boundary=boundary,
            file_field=file_field,
            file_path=file_path,
            form_fields=form_fields,
        )

        content_length = len(file_header) + file_path.stat().st_size + len(file_footer)
        headers = {
            "Content-Type": f"multipart/form-data; boundary={boundary}",
            "Content-Length": str(content_length),
        }

        return self._request_streaming_file(
            "POST",
            self._request_path(path),
            headers=headers,
            file_header=file_header,
            file_path=file_path,
            file_footer=file_footer,
        )

    def _request_path(
        self,
        path: str,
        params: Mapping[str, str | int] | None = None,
    ) -> str:
        parsed = urlparse(urljoin(self.base_url, path.lstrip("/")))
        request_path = parsed.path or "/"
        query = parsed.query

        if params:
            encoded = urlencode(params)
            query = f"{query}&{encoded}" if query else encoded

        return f"{request_path}?{query}" if query else request_path

    def _connect(self) -> http.client.HTTPConnection:
        parsed = urlparse(self.base_url)

        if parsed.hostname is None:
            raise ValueError(f"missing hostname in URL: {self.base_url}")

        if parsed.scheme == "https":
            return http.client.HTTPSConnection(
                parsed.hostname, parsed.port, timeout=self.timeout
            )

        if parsed.scheme == "http":
            return http.client.HTTPConnection(
                parsed.hostname, parsed.port, timeout=self.timeout
            )

        raise ValueError(f"unsupported URL scheme: {parsed.scheme}")

    def _request(
        self,
        method: str,
        path: str,
        *,
        body: bytes | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> HttpResponse:
        started = time.perf_counter()
        conn = self._connect()

        try:
            conn.request(method, path, body=body, headers=dict(headers or {}))
            response = conn.getresponse()
            response_body = response.read()
            elapsed = time.perf_counter() - started

            return HttpResponse(
                status_code=response.status,
                headers=dict(response.getheaders()),
                body=response_body,
                elapsed_seconds=elapsed,
            )
        finally:
            conn.close()

    def _request_streaming_file(
        self,
        method: str,
        path: str,
        *,
        headers: Mapping[str, str],
        file_header: bytes,
        file_path: Path,
        file_footer: bytes,
        chunk_size: int = 1024 * 1024,
    ) -> HttpResponse:
        started = time.perf_counter()
        conn = self._connect()

        try:
            conn.putrequest(method, path)

            for key, value in headers.items():
                conn.putheader(key, value)

            conn.endheaders()
            conn.send(file_header)

            with file_path.open("rb") as file_obj:
                while chunk := file_obj.read(chunk_size):
                    conn.send(chunk)

            conn.send(file_footer)
            response = conn.getresponse()
            response_body = response.read()
            elapsed = time.perf_counter() - started

            return HttpResponse(
                status_code=response.status,
                headers=dict(response.getheaders()),
                body=response_body,
                elapsed_seconds=elapsed,
            )
        finally:
            conn.close()

    def _multipart_file_boundaries(
        self,
        *,
        boundary: str,
        file_field: str,
        file_path: Path,
        form_fields: Mapping[str, str],
    ) -> tuple[bytes, bytes]:
        chunks: list[bytes] = []

        for name, value in form_fields.items():
            chunks.append(f"--{boundary}\r\n".encode("ascii"))
            chunks.append(
                (f'Content-Disposition: form-data; name="{name}"\r\n\r\n').encode()
            )
            chunks.append(str(value).encode("utf-8"))
            chunks.append(b"\r\n")

        content_type = (
            mimetypes.guess_type(file_path.name)[0] or "application/octet-stream"
        )

        chunks.append(f"--{boundary}\r\n".encode("ascii"))
        chunks.append(
            (
                f'Content-Disposition: form-data; name="{file_field}"; '
                f'filename="{file_path.name}"\r\n'
            ).encode()
        )
        chunks.append(f"Content-Type: {content_type}\r\n\r\n".encode("ascii"))

        footer = f"\r\n--{boundary}--\r\n".encode("ascii")

        return b"".join(chunks), footer

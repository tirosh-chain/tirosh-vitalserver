from __future__ import annotations

import hashlib
import json
from datetime import datetime
from pathlib import Path
from typing import Any, Protocol

from .config import ObserverSettings
from .model import (
    AnomalyObservation,
    BedObservation,
    ObservationDocument,
    ProxyConnectionObservation,
    RawBedScopedObservation,
    RecorderObservation,
)
from .time import redis_unix_time_to_iso, utc_now_iso


class RedisReader(Protocol):
    def ping(self) -> bool: ...
    def get(self, key: str) -> str | None: ...
    def smembers(self, key: str) -> list[str]: ...
    def keys(self, pattern: str) -> list[str]: ...


class VitalDBCollector:
    def __init__(self, redis_client: RedisReader, settings: ObserverSettings) -> None:
        self._redis = redis_client
        self._settings = settings

    def ready(self) -> bool:
        return self._redis.ping()

    def collect(self) -> ObservationDocument:
        observed_at = utc_now_iso()
        recorders = self._recorders(observed_at)
        beds = self._beds(observed_at)
        devices = self._raw_bed_scoped(
            prefix="devs_", bed_ids=[bed.bed_id for bed in beds]
        )
        filters = self._raw_bed_scoped(
            prefix="filts_", bed_ids=[bed.bed_id for bed in beds]
        )
        proxy_connections = self._proxy_connections()
        anomalies = self._anomalies(observed_at, recorders, proxy_connections)
        return ObservationDocument(
            observed_at=observed_at,
            ready=True,
            recorder_online_threshold_seconds=self._settings.recorder_online_threshold_seconds,
            recorders=recorders,
            beds=beds,
            devices=devices,
            filters=filters,
            proxy_connections=proxy_connections,
            anomalies=anomalies,
        )

    def _recorders(self, observed_at: str) -> list[RecorderObservation]:
        vrcodes = {
            key.removeprefix("ip_")
            for key in self._redis.keys("ip_*")
            if key.removeprefix("ip_")
        }
        vrcodes.update(
            key.removeprefix("utime_")
            for key in self._redis.keys("utime_*")
            if key.removeprefix("utime_")
        )
        recorders = [
            self._recorder(vrcode, observed_at)
            for vrcode in sorted(vrcodes)
            if not vrcode.startswith("bed")
        ]
        return [
            recorder for recorder in recorders if recorder.ip or recorder.last_seen_at
        ]

    def _recorder(self, vrcode: str, observed_at: str) -> RecorderObservation:
        last_seen_raw = self._redis.get(f"utime_{vrcode}")
        online = _is_recent(
            last_seen_raw,
            observed_at,
            self._settings.recorder_online_threshold_seconds,
        )
        return RecorderObservation(
            vrcode=vrcode,
            ip=self._empty_to_none(self._redis.get(f"ip_{vrcode}")),
            last_seen_at=redis_unix_time_to_iso(last_seen_raw),
            version=self._empty_to_none(self._redis.get(f"vrver_{vrcode}")),
            info=self._empty_to_none(self._redis.get(f"info_{vrcode}")),
            config=self._empty_to_none(self._redis.get(f"vrconf_{vrcode}")),
            online=online,
            stale=not online,
        )

    def _beds(self, observed_at: str) -> list[BedObservation]:
        bed_ids = set(self._redis.smembers("beds"))
        bed_ids.update(
            key.removeprefix("beds:")
            for key in self._redis.keys("beds:*")
            if key.removeprefix("beds:")
        )
        return [self._bed(bed_id, observed_at) for bed_id in sorted(bed_ids)]

    def _bed(self, bed_id: str, observed_at: str) -> BedObservation:
        raw_bed = self._empty_to_none(self._redis.get(f"beds:{bed_id}"))
        raw_ptcon = self._empty_to_none(self._redis.get(f"ptcon_{bed_id}"))
        last_seen_raw = self._redis.get(f"utime_{bed_id}")
        return BedObservation(
            bed_id=bed_id,
            name=_bed_name(raw_bed),
            vrcode=_bed_vrcode(raw_bed),
            last_seen_at=redis_unix_time_to_iso(last_seen_raw),
            patient_connected=_bool_string(raw_ptcon),
            online=_is_recent(
                last_seen_raw,
                observed_at,
                self._settings.recorder_online_threshold_seconds,
            ),
        )

    def _raw_bed_scoped(
        self, prefix: str, bed_ids: list[str]
    ) -> list[RawBedScopedObservation]:
        observations: list[RawBedScopedObservation] = []
        keys = {f"{prefix}{bed_id}" for bed_id in bed_ids}
        keys.update(self._redis.keys(f"{prefix}*"))
        for key in sorted(keys):
            raw_value = self._empty_to_none(self._redis.get(key))
            if raw_value is None:
                continue
            observations.append(
                RawBedScopedObservation(
                    bed_id=key.removeprefix(prefix), raw_value=raw_value
                )
            )
        return observations

    def _proxy_connections(self) -> list[ProxyConnectionObservation]:
        path = self._settings.access_log_path
        if not path:
            return []
        log_path = Path(path)
        if not log_path.exists():
            return []
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        return [
            _proxy_connection_from_json(line)
            for line in lines[-self._settings.access_log_limit :]
            if line.strip()
        ]

    def _anomalies(
        self,
        observed_at: str,
        recorders: list[RecorderObservation],
        proxy_connections: list[ProxyConnectionObservation],
    ) -> list[AnomalyObservation]:
        anomalies: list[AnomalyObservation] = []
        for recorder in recorders:
            if not recorder.online:
                anomalies.append(
                    _anomaly("stale-recorder", "warning", observed_at, recorder.vrcode)
                )

        by_ip: dict[str, list[str]] = {}
        for recorder in recorders:
            if recorder.ip:
                by_ip.setdefault(recorder.ip, []).append(recorder.vrcode)
        for ip, vrcodes in sorted(by_ip.items()):
            if len(vrcodes) > 1:
                anomalies.append(
                    _anomaly(
                        "duplicate-ip",
                        "critical",
                        observed_at,
                        ip,
                        ", ".join(sorted(vrcodes)),
                    )
                )

        for connection in proxy_connections:
            if connection.upstream_status in {"502", "504"} or connection.status in {
                "502",
                "504",
            }:
                subject = connection.request_uri or "proxy"
                anomalies.append(
                    _anomaly("backend-unavailable", "critical", observed_at, subject)
                )
        return anomalies

    def _empty_to_none(self, value: str | None) -> str | None:
        return value if value else None


def _proxy_connection_from_json(line: str) -> ProxyConnectionObservation:
    try:
        data: dict[str, Any] = json.loads(line)
    except json.JSONDecodeError:
        data = {}
    request_uri = _string_value(data, "request_uri") or _string_value(
        data, "requestURI"
    )
    upgrade = (
        _string_value(data, "http_upgrade") or _string_value(data, "upgrade") or ""
    ).lower()
    return ProxyConnectionObservation(
        observed_at=_string_value(data, "time")
        or _string_value(data, "observedAt")
        or utc_now_iso(),
        remote_address=_string_value(data, "remote_addr")
        or _string_value(data, "remoteAddress"),
        remote_port=_string_value(data, "remote_port")
        or _string_value(data, "remotePort"),
        request_uri=request_uri,
        status=_string_value(data, "status"),
        upstream_status=_string_value(data, "upstream_status")
        or _string_value(data, "upstreamStatus"),
        upstream_response_time=_string_value(data, "upstream_response_time")
        or _string_value(data, "upstreamResponseTime"),
        websocket_handshake=upgrade == "websocket"
        or (request_uri or "").startswith("/socket.io"),
    )


def _is_recent(
    raw_timestamp: str | None, observed_at: str, threshold_seconds: int
) -> bool:
    if raw_timestamp is None or raw_timestamp == "":
        return False
    try:
        timestamp = float(raw_timestamp)
        observed = datetime.fromisoformat(
            observed_at.replace("Z", "+00:00")
        ).timestamp()
    except ValueError:
        return False
    return observed - timestamp <= threshold_seconds


def _bed_name(raw_value: str | None) -> str | None:
    data = _json_object(raw_value)
    if data:
        return _string_value(data, "name") or _string_value(data, "bedname")
    return raw_value


def _bed_vrcode(raw_value: str | None) -> str | None:
    data = _json_object(raw_value)
    if data:
        return _string_value(data, "vrcode") or _string_value(data, "vr")
    return None


def _bool_string(raw_value: str | None) -> bool | None:
    if raw_value is None:
        return None
    normalized = raw_value.strip().lower()
    if normalized in {"1", "true", "yes", "y", "connected"}:
        return True
    if normalized in {"0", "false", "no", "n", "disconnected"}:
        return False
    return None


def _json_object(raw_value: str | None) -> dict[str, Any] | None:
    if not raw_value:
        return None
    try:
        value = json.loads(raw_value)
    except json.JSONDecodeError:
        return None
    return value if isinstance(value, dict) else None


def _string_value(data: dict[str, Any], key: str) -> str | None:
    value = data.get(key)
    if value is None:
        return None
    return str(value)


def _anomaly(
    kind: str,
    severity: str,
    observed_at: str,
    subject: str,
    detail: str | None = None,
) -> AnomalyObservation:
    message = (
        f"{kind}: {subject}" if detail is None else f"{kind}: {subject} ({detail})"
    )
    digest = hashlib.sha256(
        f"{kind}:{observed_at}:{subject}:{detail or ''}".encode()
    ).hexdigest()[:16]
    return AnomalyObservation(
        id=f"{kind}-{digest}",
        kind=kind,
        severity=severity,
        observed_at=observed_at,
        subject=subject,
        message=message,
    )

from __future__ import annotations

import hashlib
import json
import string
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Protocol

from .config import ObserverSettings
from .model import (
    AnomalyObservation,
    BedObservation,
    ObservationDocument,
    ProxyConnectionObservation,
    RawBedScopedObservation,
    RecorderActivityObservation,
    RecorderObservation,
)
from .time import redis_unix_time_to_iso, utc_now_iso

_ACCESS_LOG_TAIL_BYTES = 256 * 1024


class RedisReader(Protocol):
    def ping(self) -> bool: ...
    def get(self, key: str) -> str | None: ...
    def smembers(self, key: str) -> list[str]: ...
    def lrange(self, key: str, start: int, stop: int) -> list[str]: ...
    def scan(self, pattern: str) -> list[str]: ...


class VitalDBCollector:
    def __init__(self, redis_client: RedisReader, settings: ObserverSettings) -> None:
        self._redis = redis_client
        self._settings = settings

    def ready(self) -> bool:
        return self._redis.ping()

    def collect(self) -> ObservationDocument:
        observed_at = utc_now_iso()
        activity_by_vrcode = self._recorder_activity(observed_at)
        beds = self._beds(observed_at)
        registered_vrcodes = self._registered_vrcodes()
        recorders = self._recorders(
            observed_at,
            activity_by_vrcode,
            bed_ids={bed.bed_id for bed in beds},
            registered_vrcodes=registered_vrcodes,
        )
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

    def _recorders(
        self,
        observed_at: str,
        activity_by_vrcode: dict[str, RecorderActivityObservation],
        *,
        bed_ids: set[str],
        registered_vrcodes: set[str],
    ) -> list[RecorderObservation]:
        vrcodes = set(registered_vrcodes)
        recorders = [
            self._recorder(vrcode, observed_at, activity_by_vrcode.get(vrcode))
            for vrcode in sorted(vrcodes)
            if _is_recorder_identity(vrcode, bed_ids=bed_ids)
        ]
        return [
            recorder
            for recorder in recorders
            if recorder.ip or recorder.last_seen_at or recorder.activity
        ]

    def _registered_vrcodes(self) -> set[str]:
        vrcodes = set(self._redis.smembers("vrs"))
        vrcodes.update(
            key.removeprefix("vrs:")
            for key in self._redis.scan("vrs:*")
            if key.removeprefix("vrs:")
        )
        return vrcodes

    def _recorder(
        self,
        vrcode: str,
        observed_at: str,
        activity: RecorderActivityObservation | None,
    ) -> RecorderObservation:
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
            activity=activity,
        )

    def _recorder_activity(
        self,
        observed_at: str,
    ) -> dict[str, RecorderActivityObservation]:
        if not self._settings.audit_redis_list or self._settings.audit_event_limit <= 0:
            return {}
        events = self._redis.lrange(
            self._settings.audit_redis_list,
            -self._settings.audit_event_limit,
            -1,
        )
        window_seconds = max(self._settings.recorder_activity_window_seconds, 1)
        window_started_at = _parse_iso(observed_at) - timedelta(seconds=window_seconds)
        builders: dict[str, _ActivityBuilder] = {}
        for raw_event in events:
            parsed = _parse_audit_event(raw_event)
            if parsed is None or parsed["event_type"] != "send_data":
                continue
            try:
                event_time = _parse_iso(parsed["timestamp"])
            except ValueError:
                continue
            if event_time < window_started_at:
                continue
            vrcode = parsed["vrcode"]
            if not vrcode:
                continue
            builder = builders.setdefault(
                vrcode,
                _ActivityBuilder(window_seconds=window_seconds),
            )
            builder.observe(
                timestamp=parsed["timestamp"],
                byte_count=parsed["byte_count"],
                room_count=parsed["room_count"],
            )
        return {
            vrcode: builder.observation()
            for vrcode, builder in builders.items()
            if builder.message_count > 0
        }

    def _beds(self, observed_at: str) -> list[BedObservation]:
        bed_ids = set(self._redis.smembers("beds"))
        bed_ids.update(
            key.removeprefix("beds:")
            for key in self._redis.scan("beds:*")
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
        keys.update(self._redis.scan(f"{prefix}*"))
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
        lines = _tail_lines(log_path, _ACCESS_LOG_TAIL_BYTES)
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
                        "warning",
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
    age_seconds = observed - timestamp
    return 0 <= age_seconds <= threshold_seconds


def _tail_lines(path: Path, max_bytes: int) -> list[str]:
    size = path.stat().st_size
    with path.open("rb") as handle:
        if size > max_bytes:
            handle.seek(-max_bytes, 2)
        data = handle.read()
    return data.decode("utf-8", errors="replace").splitlines()


def _parse_audit_event(raw_value: str) -> dict[str, Any] | None:
    try:
        event = json.loads(raw_value)
    except json.JSONDecodeError:
        return None
    if not isinstance(event, dict):
        return None

    payload_summary = event.get("payload_summary") or event.get("payloadSummary")
    if not isinstance(payload_summary, dict):
        payload_summary = {}

    timestamp = (
        _string_value(event, "ts")
        or _string_value(event, "observedAt")
        or _string_value(event, "timestamp")
    )
    vrcode = _string_value(payload_summary, "vrcode") or _string_value(event, "vrcode")
    if timestamp is None or vrcode is None:
        return None

    return {
        "event_type": _string_value(event, "event_type")
        or _string_value(event, "eventType")
        or "",
        "timestamp": timestamp,
        "vrcode": vrcode,
        "byte_count": _int_value(payload_summary, "bytes")
        or _int_value(payload_summary, "byteCount"),
        "room_count": _int_value(payload_summary, "rooms_count")
        or _int_value(payload_summary, "roomsCount"),
    }


def _parse_iso(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


@dataclass
class _ActivityBuilder:
    window_seconds: int
    message_count: int = 0
    byte_count: int = 0
    room_count: int = 0
    first_seen_at: str | None = None
    last_seen_at: str | None = None

    def observe(self, timestamp: str, byte_count: int, room_count: int) -> None:
        self.message_count += 1
        self.byte_count += byte_count
        self.room_count += room_count
        if self.first_seen_at is None or timestamp < self.first_seen_at:
            self.first_seen_at = timestamp
        if self.last_seen_at is None or timestamp > self.last_seen_at:
            self.last_seen_at = timestamp

    def observation(self) -> RecorderActivityObservation:
        return RecorderActivityObservation(
            window_seconds=self.window_seconds,
            message_count=self.message_count,
            byte_count=self.byte_count,
            room_count=self.room_count,
            first_seen_at=self.first_seen_at,
            last_seen_at=self.last_seen_at,
            messages_per_second=round(self.message_count / self.window_seconds, 3),
            bytes_per_second=round(self.byte_count / self.window_seconds, 1),
        )


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


def _int_value(data: dict[str, Any], key: str) -> int:
    value = data.get(key)
    if value in (None, ""):
        return 0
    try:
        return max(int(str(value)), 0)
    except (TypeError, ValueError):
        return 0


def _is_recorder_identity(value: str, *, bed_ids: set[str]) -> bool:
    normalized = value.strip()
    if not normalized:
        return False
    if normalized in bed_ids or normalized.startswith("bed"):
        return False
    return not _looks_like_sha1_bed_id(normalized)


def _looks_like_sha1_bed_id(value: str) -> bool:
    return len(value) == 40 and all(
        character in string.hexdigits for character in value
    )


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

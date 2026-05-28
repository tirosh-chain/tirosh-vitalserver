from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class RecorderActivityBucket:
    bucket_started_at: str
    bucket_seconds: int
    message_count: int
    byte_count: int
    room_count: int

    def as_json(self) -> dict[str, Any]:
        return {
            "bucketStartedAt": self.bucket_started_at,
            "bucketSeconds": self.bucket_seconds,
            "messageCount": self.message_count,
            "byteCount": self.byte_count,
            "roomCount": self.room_count,
        }


@dataclass(frozen=True)
class RecorderActivityObservation:
    window_seconds: int
    message_count: int
    byte_count: int
    room_count: int
    first_seen_at: str | None
    last_seen_at: str | None
    messages_per_second: float
    bytes_per_second: float
    buckets: list[RecorderActivityBucket] = field(default_factory=list)

    def as_json(self) -> dict[str, Any]:
        return {
            "windowSeconds": self.window_seconds,
            "messageCount": self.message_count,
            "byteCount": self.byte_count,
            "roomCount": self.room_count,
            "firstSeenAt": self.first_seen_at,
            "lastSeenAt": self.last_seen_at,
            "messagesPerSecond": self.messages_per_second,
            "bytesPerSecond": self.bytes_per_second,
            "buckets": [bucket.as_json() for bucket in self.buckets],
        }


@dataclass(frozen=True)
class RecorderObservation:
    vrcode: str
    ip: str | None
    last_seen_at: str | None
    version: str | None
    info: str | None
    config: str | None
    online: bool
    stale: bool
    activity: RecorderActivityObservation | None = None

    def as_json(self) -> dict[str, Any]:
        return {
            "vrcode": self.vrcode,
            "ip": self.ip,
            "lastSeenAt": self.last_seen_at,
            "version": self.version,
            "info": self.info,
            "config": self.config,
            "online": self.online,
            "stale": self.stale,
            "activity": self.activity.as_json() if self.activity else None,
        }


@dataclass(frozen=True)
class BedObservation:
    bed_id: str
    name: str | None
    vrcode: str | None
    last_seen_at: str | None
    patient_connected: bool | None
    online: bool

    def as_json(self) -> dict[str, Any]:
        return {
            "bedID": self.bed_id,
            "name": self.name,
            "vrcode": self.vrcode,
            "lastSeenAt": self.last_seen_at,
            "patientConnected": self.patient_connected,
            "online": self.online,
        }


@dataclass(frozen=True)
class RawBedScopedObservation:
    bed_id: str
    raw_value: str

    def as_json(self) -> dict[str, Any]:
        return {
            "bedID": self.bed_id,
            "rawValue": self.raw_value,
        }


@dataclass(frozen=True)
class ProxyConnectionObservation:
    observed_at: str
    remote_address: str | None
    remote_port: str | None
    request_uri: str | None
    status: str | None
    upstream_status: str | None
    upstream_response_time: str | None
    websocket_handshake: bool

    def as_json(self) -> dict[str, Any]:
        return {
            "observedAt": self.observed_at,
            "remoteAddress": self.remote_address,
            "remotePort": self.remote_port,
            "requestURI": self.request_uri,
            "status": self.status,
            "upstreamStatus": self.upstream_status,
            "upstreamResponseTime": self.upstream_response_time,
            "websocketHandshake": self.websocket_handshake,
        }


@dataclass(frozen=True)
class AnomalyObservation:
    id: str
    kind: str
    severity: str
    observed_at: str
    subject: str
    message: str

    def as_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "severity": self.severity,
            "observedAt": self.observed_at,
            "subject": self.subject,
            "message": self.message,
        }


@dataclass(frozen=True)
class ObservationDocument:
    observed_at: str
    ready: bool
    recorder_online_threshold_seconds: int
    recorders: list[RecorderObservation] = field(default_factory=list)
    beds: list[BedObservation] = field(default_factory=list)
    devices: list[RawBedScopedObservation] = field(default_factory=list)
    filters: list[RawBedScopedObservation] = field(default_factory=list)
    proxy_connections: list[ProxyConnectionObservation] = field(default_factory=list)
    anomalies: list[AnomalyObservation] = field(default_factory=list)

    def as_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": 1,
            "source": "vitaldb-observer",
            "observedAt": self.observed_at,
            "ready": self.ready,
            "recorderOnlineThresholdSeconds": self.recorder_online_threshold_seconds,
            "recorders": [item.as_json() for item in self.recorders],
            "beds": [item.as_json() for item in self.beds],
            "devices": [item.as_json() for item in self.devices],
            "filters": [item.as_json() for item in self.filters],
            "proxyConnections": [item.as_json() for item in self.proxy_connections],
            "anomalies": [item.as_json() for item in self.anomalies],
        }

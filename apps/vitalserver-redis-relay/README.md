# vitalserver-redis-relay

`vitalserver-redis-relay` copies allowlisted VitalServer Redis keys from the
internal Redis 3.2 source to an operator-configured target Redis 8.x endpoint.

The relay is for realtime and high-volume numeric/trend/waveform transfer. It
does not expose source Redis over HTTP and does not write to source Redis.

## Contract

- Source Redis is internal: `redis://redis:6379/0`.
- Target Redis is configured by VitalServer Helper Advanced settings.
- Source reads use `SCAN`, `TYPE`, `PTTL`, and `DUMP`.
- Target writes use the VitalServer Redis Relay Protocol v1:
  `RESTORE` the binary payload, update the target fingerprint, record publish
  dedupe state, and `XADD` a `key_published` event atomically.
- The relay is a publisher. Target-side consumers own consumer group pending
  recovery, dead-letter handling, decoding, and downstream idempotency.
- Credential/session/auth keys are always denied.
- UI selects a scope preset; regex rules are not user configurable.

## Target output

The target Redis receives restored source payload keys plus metadata streams.

| Target key | Purpose |
|---|---|
| `vitalserver:<source-key>` | Restored source Redis key snapshot |
| `vitalserver:relay:events` | Protocol v1 metadata stream |
| `vitalserver:relay:fingerprints` | Target key -> source payload fingerprint |
| `vitalserver:relay:published` | Publish dedupe key -> event id |

The event stream is metadata-only. Consumers must fetch `target_key` from target
Redis to decode or transform the payload.

Protocol v1 event fields:

| Field | Meaning |
|---|---|
| `schema_version` | Protocol schema version. Current value is `1`. |
| `event` | Event name. Current value is `key_published`. |
| `source_key` | Source Redis key. |
| `target_key` | Target Redis key containing the restored payload. |
| `key_type` | Source Redis key type. |
| `ttl_ms` | Source key PTTL represented for Redis `RESTORE`. |
| `source_fingerprint` | SHA-256 of the source DUMP payload. |
| `dedupe_key` | Stable key for duplicate publish detection. |
| `published_at` | UTC timestamp emitted by this publisher. |
| `publisher` | Publisher id. Default `vitalserver-helper-relay`. |

Consumers should use Redis Streams consumer groups, fetch `target_key`, decode
or transform the payload, perform idempotent downstream writes, and acknowledge
only successful work. Pending recovery, dead-letter handling, and downstream
idempotency belong to the consumer system.

## Config

```toml
[redis_relay]
enabled = true
scope = "vital_reconstruction"
include_recorder_network_context = true
interval_seconds = 1.0
scan_count = 1000

[source]
host = "redis"
port = 6379
database = 0

[target]
url = "redis://default@10.0.0.12:6379/0"
password_file = "/run/tirosh/secrets/redis-relay-target-password"

[publish]
target_key_prefix = "vitalserver:"
event_stream_key = "vitalserver:relay:events"
fingerprint_hash_key = "vitalserver:relay:fingerprints"
publish_dedupe_hash_key = "vitalserver:relay:published"
event_stream_maxlen = 100000
publisher_id = "vitalserver-helper-relay"
```

If the config file is missing or `enabled = false`, the container stays alive
and writes a disabled status document.

VitalServer Helper stores the target as separate UI inputs: Target URL, TLS,
Username, and Password. The runtime configure command combines Target URL, TLS,
and Username into the TOML `target.url`; Password remains outside the URL and is
provided through `password_file`.

Helper Target URL examples:

- `redis://192.168.64.1:16381/0`
- `redis://redis.example:6379/0`
- `redis://redis.example:6380/2`

Generated TOML URL examples:

- `redis://192.168.64.1:16381/0`
- `redis://default@redis.example:6379/0`
- `rediss://default@redis.example:6380/2`

Target URL is interpreted from the relay container/guest runtime, not from the
macOS Helper UI process. Use the guest-reachable host address for a Redis
endpoint published on the Mac host; in the shared NAT runtime that address is
usually `192.168.64.1`.

## Status

The relay writes JSON status to `/run/tirosh/status/redis-relay-status.json`.
The status never includes the target password.

- `enabled` and `state` describe the relay process contract.
- `settingsFingerprint` changes when the password-free connection/scope contract changes.
- `publishEventStreamKey`, `publishTargetKeyPrefix`, and `publishPublisherId`
  describe the active Protocol v1 publish contract.
- `batches`, `totals`, and `lastBatch` show scan/publish progress.
- `lastSuccessAt` is updated after a batch completes with zero publish errors.
- `lastErrorAt` and `lastError` are updated when config or copy work fails.
- `lastErrorSamples` shows bounded key/stage/message samples from the latest
  failed batch so operators can distinguish target connection, publish, and
  payload errors.

`lastErrorSamples[].code` is the machine-readable relay publish error contract:

| Code | Stage | Meaning |
|---|---|---|
| `source_dump_failed` | `source_dump` | Source Redis key metadata or `DUMP` failed. |
| `target_publish_failed` | `target_publish` | Atomic target `RESTORE`/fingerprint/dedupe/event publish failed. |

Docker health checks use this status file to report relay process liveness.
Target Redis authentication, network, or publish failures are reported in the
status payload instead of making the container disappear from service liveness.

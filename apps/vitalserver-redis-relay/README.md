# vitalserver-redis-relay

`vitalserver-redis-relay` copies allowlisted VitalServer Redis keys from the
internal Redis 3.2 source to an operator-configured target Redis 8.x endpoint.

The relay is for realtime and high-volume numeric/trend/waveform transfer. It
does not expose source Redis over HTTP and does not write to source Redis.

## Contract

- Source Redis is internal: `redis://redis:6379/0`.
- Target Redis is configured by VitalServer Helper Advanced settings.
- Source reads use `SCAN`, `TYPE`, `PTTL`, and `DUMP`.
- Target writes use `RESTORE`.
- Credential/session/auth keys are always denied.
- UI selects a scope preset; regex rules are not user configurable.

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
host = "10.0.0.12"
port = 6379
database = 0
username = "default"
password_file = "/run/tirosh/secrets/redis-relay-target-password"
tls = false
```

If the config file is missing or `enabled = false`, the container stays alive
and writes a disabled status document.

## Status

The relay writes JSON status to `/run/tirosh/status/redis-relay-status.json`.
The status never includes the target password.

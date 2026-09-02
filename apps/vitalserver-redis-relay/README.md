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
- Target Redis commands reconnect and retry with bounded exponential backoff
  when the socket is closed, times out, or fails before a Redis response is
  read. Retry exhaustion remains an explicit publish failure in relay status.
- If the target endpoint stays unreachable for longer than one command retry
  window, the relay process stays alive, records the failed batch, and retries
  again on the next relay loop. When the target becomes reachable again, the
  relay resumes publishing the current allowed source Redis snapshots.
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

Canonical credentials are file paths, not secret values. TOML, CLI, and
environment variables may contain those paths only.

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
password_file = "/run/tirosh/secrets/redis-relay-source-password"

[target]
url = "rediss://10.0.0.12:6380/2"
username_file = "/run/tirosh/secrets/redis-relay-target-username"
password_file = "/run/tirosh/secrets/redis-relay-target-password"

[publish]
target_key_prefix = "vitalserver:"
event_stream_key = "vitalserver:relay:events"
fingerprint_hash_key = "vitalserver:relay:fingerprints"
publish_dedupe_hash_key = "vitalserver:relay:published"
event_stream_maxlen = 100000
publisher_id = "vitalserver-helper-relay"
```

`redis_relay.enabled` is required. `enabled = false` is the only disabled
state. A missing config file, unreadable file, or invalid TOML is
`config_invalid`, not disabled. Disabled configs do not connect and do not
read credential files even if those keys are present.

When enabled, `[source]` and `source.host` are required. Source Redis 3.2 uses
optional `password_file` only; named usernames are not supported. Target
`target.url` is required and must be `redis://host:port/db` or
`rediss://host:port/db`. Username, password, and any other URL user-info are
configuration errors. Target credentials belong to Guest Control: TOML stores
only `username_file` and `password_file` paths. Relative credential paths are
resolved from the config file directory. A credential file may end with one
newline (`\n` or `\r\n`); that terminator is removed and the remaining bytes
are the secret. If a credential path key is present, it must be a non-empty
path; `""` or whitespace-only values are configuration errors, not no-auth.
Empty files, missing files, permission failures, and UTF-8 decode failures are
distinct errors. The relay does not force a POSIX mode on secret files; keep
them owner-readable only (for example `0600`) when the runtime can do so.
Docker/systemd secret mounts may use other modes.

A target username from `username_file` requires `password_file`. Password-only
AUTH and no-auth targets remain valid. Production target Redis should use ACL
credentials and TLS; no-auth is not a recommended deployment.

URL user-info is never accepted. Guest Control migrates a legacy on-disk URL
username onto `username_file` and a canonical URL before Compose starts the
relay. URL passwords are invalid and are not migrated. After that conversion,
this consumer rejects every URL username and password with a sanitized
`RelaySettingsError`.

Each relay loop reloads the config and credential files. There is no hidden
credential cache.

Helper Target URL examples (host/port/database only):

- `redis://192.168.64.1:16381/0`
- `redis://redis.example:6379/0`
- `rediss://redis.example:6380/2`

Target URL is interpreted from the relay process, not from the macOS Helper UI
process. Use the guest-reachable host address for a Redis endpoint published on
the Mac host; in the shared NAT runtime that address is usually
`192.168.64.1`.

## Status

The relay always writes JSON status to `--status-path` /
`REDIS_RELAY_STATUS_PATH` (default `/run/tirosh/status/redis-relay-status.json`)
through an atomic file replace so readers only see a complete JSON document.

Additional Guest Control owner transports are explicit CLI/environment inputs.
The relay does not detect OS or runtime mode.

| Runtime | Status outputs | How it is selected |
|---|---|---|
| Native Host | JSON file only | neither `--status-owner-url` nor `--status-owner-socket` |
| VM Guest | JSON file + HTTP `PUT /runtime/redis-relay/status` | `REDIS_RELAY_STATUS_OWNER_URL` |
| Linux container | JSON file + HTTP-over-Unix-socket `PUT /runtime/redis-relay/status` | `REDIS_RELAY_STATUS_OWNER_SOCKET` |

URL and socket together are a start-time configuration error. An HTTP owner URL
that is malformed, uses a scheme other than http/https, has no host, or has an
invalid port is also a start-time configuration error; known transport I/O
failures stay publish results after a valid URL is configured. Linux container
runtimes mount the root-owned socket directory read-only into the relay
container, so the container can publish only its status mutation without
opening the Runtime Controller's loopback API on a bridge or LAN address.

Product consumers of Helper/Runtime Control read the Guest/Postgres owner
snapshot through `GET /runtime/redis-relay/status`; they do not read the status
file as current product state. VM and Linux container runtimes still publish the
same document as a `PUT /runtime/redis-relay/status` owner mutation. Native
File-only operators read the status file directly. The status never includes
username or password values. `targetUrl` keeps the schema field and renders
`scheme://host:port/db` without userinfo. `targetUsernameConfigured` and
`targetPasswordConfigured` remain booleans.

If some configured status outputs succeed and others fail, the relay process
stays alive, continues the copy loop, and writes each failed adapter name and
error to stderr. Status output failure is not recorded as Redis relay
`state=running`. If every configured status output fails, the process exits
with an explicit status publish error so the supervisor can restart it.

- `enabled` and `state` describe the relay process contract.
- `settingsFingerprint` hashes host/port/database/TLS, username/password
  configured booleans, and the scope/publish contract. It does not include
  credential values, so password rotation does not change the fingerprint.
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

Docker health checks verify that the relay is configured with a status owner URL;
they do not read the diagnostics status file as product liveness. Target Redis
authentication, network, or publish failures are reported in the status owner
snapshot instead of making the container disappear from service liveness.
Transient target disconnects are retried inside the active batch with bounded
backoff; persistent failures remain visible as `target_publish_failed` samples.
Longer target outages do not stop the relay container. The next successful
batch republishes source keys that are still present in source Redis. The relay
is not a durable queue: source keys that expire or are deleted while the target
is unreachable cannot be recovered by the publisher alone.

## Native Host package

`apps/vitalserver-redis-relay` is the only runtime source. Install it as
`tirosh-vitalserver-redis-relay` version `0.2.0`, the same version as this
monorepo runtime line. The package uses the Python 3.12 standard library only.

Build a wheel from the repository root. This wheel is used for both local
development and system-wide supervisor installs:

```sh
uv build --package tirosh-vitalserver-redis-relay --wheel
```

Docker/VM still start the process with `python -m vitalserver_redis_relay`.
Native Host supervisors start the console command from a system-wide venv.
Those two layouts are different.

### Development venv (not for launchd/systemd)

Use a repository-local venv to inspect the command. This path is not the
supervisor executable.

```sh
uv venv .venv-redis-relay
uv pip install --python .venv-redis-relay/bin/python --no-deps dist/tirosh_vitalserver_redis_relay-0.2.0-py3-none-any.whl
.venv-redis-relay/bin/vitalserver-redis-relay --help
.venv-redis-relay/bin/python -m vitalserver_redis_relay --help
```

Do not point launchd or systemd at `.venv-redis-relay`.

### System-wide executable contract

Supervisor `Exec` paths are the console script created by installing the wheel
into these venvs. README, plist, and unit use the same strings.

| OS | system venv | supervisor executable |
|---|---|---|
| macOS | `/usr/local/libexec/vitalserver-redis-relay/venv` | `/usr/local/libexec/vitalserver-redis-relay/venv/bin/vitalserver-redis-relay` |
| Linux | `/opt/vitalserver/redis-relay/venv` | `/opt/vitalserver/redis-relay/venv/bin/vitalserver-redis-relay` |

Native Host is File-only: do not set `--status-owner-url` or
`--status-owner-socket`. Missing config is `config_invalid`. Unreadable or
invalid TOML is `config_invalid`. `enabled = false` is `state=disabled`. Those
three meanings stay distinct and are written to the status file. Disabled
configs do not connect to Redis.

Credential values never appear in plist, systemd unit, CLI flags, or
environment. TOML stores `username_file` and `password_file` paths only.

### macOS system install

Create dedicated user `_vitalserver-redis-relay` first. The operator owns user
creation. Then create every parent directory the plist references, install the
wheel into the system venv, and copy config/secrets.

| Path | Who creates it | Owner | Mode | Role |
|---|---|---|---|---|
| `/usr/local/libexec/vitalserver-redis-relay` | operator, before `uv venv` | root | `0755` | venv parent |
| `/usr/local/libexec/vitalserver-redis-relay/venv` | operator `uv venv` | root | venv default | system-wide venv |
| `/usr/local/libexec/vitalserver-redis-relay/venv/bin/vitalserver-redis-relay` | `uv pip install --no-deps` | root | venv script | launchd executable |
| `/usr/local/etc/vitalserver` | operator, before config copy | root | `0755` | config parent |
| `/usr/local/etc/vitalserver/redis-relay.toml` | operator copy of macOS example | `root:_vitalserver-redis-relay` | `0640` | config |
| `/Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist` | operator copy of launchd example | `root:wheel` | `0644` | launchd definition |
| `/usr/local/etc/vitalserver/secrets` | operator, before secret files | `_vitalserver-redis-relay` | `0750` | secret parent |
| `/usr/local/etc/vitalserver/secrets/redis-relay-target-username` | operator | `_vitalserver-redis-relay` | `0600` | target username |
| `/usr/local/etc/vitalserver/secrets/redis-relay-target-password` | operator | `_vitalserver-redis-relay` | `0600` | target password |
| `/usr/local/var/vitalserver` | operator, before first status write | `_vitalserver-redis-relay` | `0755` | status parent |
| `/usr/local/var/vitalserver/redis-relay-status.json` | relay process | `_vitalserver-redis-relay` | file created by relay | File status |
| `/usr/local/var/log/vitalserver` | operator, before launchd start | `_vitalserver-redis-relay` | `0755` | log parent |
| `/usr/local/var/log/vitalserver/redis-relay.out.log` | launchd | `_vitalserver-redis-relay` | created by launchd | stdout |
| `/usr/local/var/log/vitalserver/redis-relay.err.log` | launchd | `_vitalserver-redis-relay` | created by launchd | stderr |

```sh
sudo install -d -m 0755 /usr/local/libexec/vitalserver-redis-relay
sudo install -d -m 0755 /usr/local/etc/vitalserver
sudo install -d -o _vitalserver-redis-relay -g _vitalserver-redis-relay -m 0750 \
  /usr/local/etc/vitalserver/secrets
sudo install -d -o _vitalserver-redis-relay -g _vitalserver-redis-relay -m 0755 \
  /usr/local/var/vitalserver /usr/local/var/log/vitalserver
sudo uv venv /usr/local/libexec/vitalserver-redis-relay/venv
sudo uv pip install --python /usr/local/libexec/vitalserver-redis-relay/venv/bin/python --no-deps \
  dist/tirosh_vitalserver_redis_relay-0.2.0-py3-none-any.whl
sudo cp packaging/macos/native-redis-relay.example.toml \
  /usr/local/etc/vitalserver/redis-relay.toml
sudo chown root:_vitalserver-redis-relay /usr/local/etc/vitalserver/redis-relay.toml
sudo chmod 0640 /usr/local/etc/vitalserver/redis-relay.toml
# Write username/password into the secret files, then:
sudo chown _vitalserver-redis-relay:_vitalserver-redis-relay \
  /usr/local/etc/vitalserver/secrets/redis-relay-target-username \
  /usr/local/etc/vitalserver/secrets/redis-relay-target-password
sudo chmod 0600 \
  /usr/local/etc/vitalserver/secrets/redis-relay-target-username \
  /usr/local/etc/vitalserver/secrets/redis-relay-target-password
```

Foreground check, using the same executable launchd will start:

```sh
sudo -u _vitalserver-redis-relay \
  /usr/local/libexec/vitalserver-redis-relay/venv/bin/vitalserver-redis-relay \
  --config-path /usr/local/etc/vitalserver/redis-relay.toml \
  --status-path /usr/local/var/vitalserver/redis-relay-status.json
```

Example launchd load. The plist is an example and is not installed by macOS PKG
or GitHub Actions:

```sh
sudo cp packaging/macos/ai.tirosh.vitalserver.redis-relay.plist \
  /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
sudo chown root:wheel /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
sudo chmod 0644 /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
sudo launchctl bootstrap system /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
```

```sh
sudo launchctl bootout system/ai.tirosh.vitalserver.redis-relay
sudo launchctl bootstrap system /Library/LaunchDaemons/ai.tirosh.vitalserver.redis-relay.plist
python -c 'import json; print(json.load(open("/usr/local/var/vitalserver/redis-relay-status.json"))["state"])'
```

### Linux system install

Create dedicated user `vitalserver-redis-relay` first. Then create directories,
install the wheel into the system venv, and copy config/secrets.

| Path | Who creates it | Owner | Mode | Role |
|---|---|---|---|---|
| `/opt/vitalserver/redis-relay` | operator, before `uv venv` | root | `0755` | venv parent |
| `/opt/vitalserver/redis-relay/venv` | operator `uv venv` | root | venv default | system-wide venv |
| `/opt/vitalserver/redis-relay/venv/bin/vitalserver-redis-relay` | `uv pip install --no-deps` | root | venv script | systemd executable |
| `/etc/vitalserver` | operator, before config copy | root | `0755` | config parent |
| `/etc/vitalserver/redis-relay.toml` | operator copy of Linux example | `root:vitalserver-redis-relay` | `0640` | config |
| `/etc/systemd/system/vitalserver-redis-relay.service` | operator copy of systemd example | `root:root` | `0644` | systemd unit |
| `/etc/vitalserver/secrets` | operator, before secret files | `vitalserver-redis-relay` | `0750` | secret parent |
| `/etc/vitalserver/secrets/redis-relay-target-username` | operator | `vitalserver-redis-relay` | `0600` | target username |
| `/etc/vitalserver/secrets/redis-relay-target-password` | operator | `vitalserver-redis-relay` | `0600` | target password |
| `/var/lib/vitalserver/redis-relay` | operator, before first status write | `vitalserver-redis-relay` | `0755` | status parent |
| `/var/lib/vitalserver/redis-relay/status.json` | relay process | `vitalserver-redis-relay` | file created by relay | File status |

```sh
sudo install -d -m 0755 /opt/vitalserver/redis-relay /etc/vitalserver
sudo install -d -o vitalserver-redis-relay -g vitalserver-redis-relay -m 0750 \
  /etc/vitalserver/secrets
sudo install -d -o vitalserver-redis-relay -g vitalserver-redis-relay -m 0755 \
  /var/lib/vitalserver/redis-relay
sudo uv venv /opt/vitalserver/redis-relay/venv
sudo uv pip install --python /opt/vitalserver/redis-relay/venv/bin/python --no-deps \
  dist/tirosh_vitalserver_redis_relay-0.2.0-py3-none-any.whl
sudo cp packaging/linux/native-redis-relay.example.toml /etc/vitalserver/redis-relay.toml
sudo chown root:vitalserver-redis-relay /etc/vitalserver/redis-relay.toml
sudo chmod 0640 /etc/vitalserver/redis-relay.toml
# Write username/password into the secret files, then:
sudo chown vitalserver-redis-relay:vitalserver-redis-relay \
  /etc/vitalserver/secrets/redis-relay-target-username \
  /etc/vitalserver/secrets/redis-relay-target-password
sudo chmod 0600 \
  /etc/vitalserver/secrets/redis-relay-target-username \
  /etc/vitalserver/secrets/redis-relay-target-password
```

Foreground check, using the same executable systemd will start:

```sh
sudo -u vitalserver-redis-relay \
  /opt/vitalserver/redis-relay/venv/bin/vitalserver-redis-relay \
  --config-path /etc/vitalserver/redis-relay.toml \
  --status-path /var/lib/vitalserver/redis-relay/status.json
```

Example systemd enable. The unit is an example and is not installed by product
packaging or GitHub Actions:

```sh
sudo cp packaging/linux/vitalserver-redis-relay.service \
  /etc/systemd/system/vitalserver-redis-relay.service
sudo chown root:root /etc/systemd/system/vitalserver-redis-relay.service
sudo chmod 0644 /etc/systemd/system/vitalserver-redis-relay.service
sudo systemctl daemon-reload
sudo systemctl enable --now vitalserver-redis-relay.service
```

```sh
sudo systemctl stop vitalserver-redis-relay.service
sudo systemctl restart vitalserver-redis-relay.service
python -c 'import json; print(json.load(open("/var/lib/vitalserver/redis-relay/status.json"))["state"])'
```

launchd owns start and restart through `RunAtLoad` and `KeepAlive`. systemd
owns start and restart through `Type=simple` and `Restart=on-failure`. The
relay process stays in the foreground. It does not daemonize, write a pidfile,
or restart itself.

Windows native service is out of scope. Existing VM/Compose Windows guest files
are unchanged.

### Host data flow

On a native Host, VitalServer and its source Redis listen locally. The relay
process reads allowlisted keys from that source Redis (`127.0.0.1` in the
example), then publishes Protocol v1 snapshots to a remote target Redis. The
target never reaches back into source Redis. Credentials stay in files that
only the relay user can read.

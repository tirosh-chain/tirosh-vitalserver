# Redis Relay legacy URL username is not migrated or stays in the URL

> ID: TS-193
> Category: Guest containers / Runtime Control
> Owner: Guest Control Redis Relay settings
> Status: active

## Case Metadata

- `ID`: TS-193
- `Category`: Guest containers / Runtime Control
- `Owner`: Guest Control Redis Relay settings repository and Compose `UP`
- `Status`: active

## Symptoms

- Compose `UP` stops before Redis Relay starts with `redisRelaySettingsInvalid`.
- Relay process reports `config_invalid` / `target.url must not contain a username` or `target.url must not contain a password`.
- `GET /runtime/redis-relay/settings` returns `state=failed` instead of `loaded`.
- Helper/PWA Redis Relay settings show unavailable/failed, not a disabled or no-auth target.
- Target URL in TOML still contains `user@` or `user:password@`.
- Settings read, status, logs, or exceptions must not contain the actual username or password. If they do, that is a separate redaction failure, not a successful no-auth fallback.

Normal: canonical `target.url` is `redis://host:port/db` or `rediss://host:port/db`, and credentials live only in `redis-relay-target-username` / `redis-relay-target-password`. Read API reports `usernameConfigured` / `passwordConfigured`.

## Impact

- Redis Relay does not start. VitalServer traffic path is unchanged; only external target publish is down.
- Invalid legacy config is not auto-repaired into no-auth or password-only.
- URL password is never migrated. An operator must rewrite the URL and store the password in the password file.

## Cause

Guest Control owns Redis Relay TOML and target credential files. Relay only consumes those files.

3-A temporarily allowed a URL username as a consumer fallback. 3-B removes that fallback. The owner must convert `redis://username@host:port/db` plus `password_file` into a canonical URL plus `username_file` before Compose starts the relay.

That conversion runs in `run_compose_action(UP)` after bind-source preparation and before `start_ordered()`, and at the start of settings save/apply. GET/read does not rewrite files. A leftover URL username on GET is `redisRelaySettingsInvalid` with `target.url username requires migration`. Migration does not hide missing, invalid, permission, decode, empty, or write failure. The owner-side password file must be the exact Runtime contract path and must exist, be readable, be valid UTF-8, and be non-empty after stripping one trailing CRLF or LF before username/config are written.

These cases stay invalid and are not migrated:

- URL password (`redis://user:password@host`)
- URL username without `password_file`
- URL username together with `username_file`
- empty, unreadable, or non-UTF-8 credential files

## Checks

```sh
# Guest-owned TOML. URL must not contain user-info.
sudo grep -n '^url =' "/Library/Application Support/VitalServerHelper/vm/data/deploy/redis-relay-config/redis-relay.toml"

# Credential files exist only as files. Do not `cat` them into tickets or logs.
sudo ls -l "/Library/Application Support/VitalServerHelper/vm/data/deploy/redis-relay-secrets"

# Compose/Guest Control error should name the invalid field, not the secret.
sudo journalctl -u tirosh-vitalserver-compose --no-pager | tail -n 80
```

Linux container path examples: `/etc/vitalserver/secrets/redis-relay/` and the configured `redisRelayConfigFile`.

## Actions

1. If the URL contains a password, do not expect automatic migration. Rewrite `target.url` to host/port/database only and put the password in `redis-relay-target-password`.
2. If the URL contains only a username and the contract `password_file` is already valid, Compose `UP` or a settings apply converts it once. GET will stay failed until that command runs. Re-run Compose after fixing permission/disk/empty-file errors.
3. If username is required, `password_file` is also required. Password-only and no-auth remain valid; username-only is invalid.
4. Apply new credentials through Runtime Control PUT. Leave username/password blank to preserve existing files. Use `clearUsername` / `clearPassword` to delete them. Do not put credentials back into the URL.
5. Confirm GET returns `usernameConfigured`/`passwordConfigured` and does not return `username` or `password`.

## Prevention

- Guest Control is the only writer of target username/password files. TOML stores contract paths, not values. Writes are atomic replace with mode `0600`.
- Compose `UP` migrates legacy URL usernames before Relay starts. Relay rejects every URL user-info value with a sanitized `RelaySettingsError`.
- Read API, status fingerprint, logs, exceptions, TOML, and repr expose configured booleans, never secret values.
- Empty credential paths, missing files, permission failures, and UTF-8 decode failures stay distinct errors. They are not disabled/no-auth.

## Operational Notes

- Native File-only Relay still reads the same TOML and secret filenames. There is no Host-side URL username fallback.
- PUT `/runtime/redis-relay/status` and Protocol v1 replication are unchanged.
- Source Redis remains password-file only. This case is target credentials.

## Related Cases

- `TS-088` Redis Relay bind source/image missing at install
- `TS-143` PWA Runtime Control contract field mismatch

## Follow-up

- 2026-09-02: Stage 3-B made Guest Control the target username/password owner, migrated legacy URL usernames before Compose start, and removed the Relay URL username fallback.

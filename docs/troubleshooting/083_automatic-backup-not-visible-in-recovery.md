# TS-083: Automatic Backup Not Visible in Recovery Operations

| Field | Value |
|---|---|
| Category | Runtime health / Data store / macOS Helper UI |
| Owner | Mac Control Panel presentation |
| Status | implemented |

## Symptom

Automatic VitalServer Helper backups are created under
`/Library/Application Support/VitalServerHelper/backups/vitalserver-helper`, but
the Advanced tab's Recovery operations section keeps showing no VitalServer
backups while the Helper app remains open.

## Cause

Automatic backups are created by the Host launchd job outside the Helper UI
action path. Manual create/import/restore actions refresh backup lists after the
operation, and the initial app refresh loads the backup list, but selected-section
polling did not refresh backup lists for the Advanced or Danger Zone sections.

That left the UI with a stale in-memory backup list even though the filesystem
state had changed.

## Fix Direction

Treat backup lists as section-owned read state for sections that display or
delete backups. When Advanced or Danger Zone is selected, refresh update,
Redis-only, and VitalServer Helper backup lists during selected-section polling.

Keep backup discovery explicit: automatic VitalServer Helper backups must remain
direct children of `backups/vitalserver-helper`, and `YYYYMMDDTHHMMSSZ-automatic`
directories must be accepted by the VitalServer backup list reader.

## Prevention

- Background Host jobs that create product-visible state must have a matching UI
  refresh path.
- UI selection state must not be treated as proof that host-owned filesystem
  state is unchanged.
- Add tests for both the section polling policy and automatic backup directory
  naming so the UI does not regress to manual-only discovery.

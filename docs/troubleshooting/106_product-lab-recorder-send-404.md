# Product Lab recorder send 404

## Symptom

Product Lab creates a Lab bed and Lab recorder, but starting the session records:

```text
VitalServer recorder payload send failed: status=404
```

The Helper Beds or Recorders page may still show zero VitalDB beds/recorders.

## Cause

The local VitalServer runtime does not expose `POST /api/send`. Realtime recorder
traffic is a Socket.IO contract: a recorder connects, emits `join_vr`, then emits
compressed `send_data` payloads. Sending Product Lab JSON to `/api/send` reaches
a missing HTTP route and returns 404.

Product Lab read models and VitalDB observation read models are also different
state owners. Product Lab owns created Lab sessions, Lab beds, Lab recorders, and
their send state. VitalDB observation owns beds/recorders after recorder traffic
has been accepted and observed through the runtime.

## Fix Direction

Product Lab recorder send must use the VitalServer Socket.IO recorder contract:

1. connect to the configured target URL,
2. emit `join_vr` with the Lab recorder code,
3. zlib-compress the `{vrcode, ver, rooms}` payload,
4. emit `send_data`,
5. persist send success or failure in the Lab recorder read model.

Do not merge Lab-created beds/recorders into the VitalDB observation read model
unless VitalDB has explicitly observed them.

## Prevention

Do not add `/api/send` as a fallback or compatibility endpoint for Product Lab.
When Product Lab send fails, preserve the explicit transport failure on the Lab
recorder. When VitalDB tabs show zero items, treat that as "no VitalDB
observation yet", not as missing Lab state.

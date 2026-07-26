# VitalDB delete leaves the Product Lab session running

> ID: TS-129
> Category: Runtime Control PWA
> Owner: Guest Control / Product Lab
> Status: resolved

## Symptoms

- A Lab-created Vital Recorder or Bed is hidden and then deleted from the regular Recorder or Bed tab.
- The row disappears from the VitalDB list, but its Product Lab session remains and may continue sending packets.
- Recorder activity or relationship history can still expose information for a deleted entity.

## Impact

Permanent delete did not clean the owning Lab runtime aggregate. A virtual recorder connection could remain active, and stale Lab session/read-model rows made the UI report resources that the user had already deleted.

## Cause

VitalDB delete only wrote a `deleted` visibility tombstone in the Guest Postgres read model. It did not use the recorder's explicit `version == vitalserver-lab` ownership contract to command Product Lab. Product Lab also had no session-delete operation that stopped execution and removed the session, beds, and recorders together.

## Checks

Compare the regular VitalDB read models with the Lab-owned collection after delete:

```sh
curl -s http://127.0.0.1:18330/runtime/vitaldb/recorders
curl -s http://127.0.0.1:18330/runtime/vitaldb/beds
curl -s http://127.0.0.1:18330/runtime/lab/sessions
```

## Actions

Update to a build containing the aggregate cleanup workflow. Retrying delete on a hidden Lab-owned row resolves the owning Lab session when it is still present. A Product Lab dependency or contract failure is returned as a delete failure and is not converted to success.

## Prevention

- Guest Control resolves Lab ownership only from explicit recorder version and vrcode contracts.
- Product Lab session delete stops the execution engine before atomically deleting the session and its owned beds and recorders.
- Deleted recorder activity and deleted recorder/bed relationship entries are excluded from public read models.
- Tests cover running-session termination, persistent aggregate deletion, recorder and bed entry points, activity cleanup, relationship cleanup, and dependency failure preservation.

## Operational Notes

The VitalDB visibility tombstone remains intentionally. It prevents a still-connected physical producer from being inferred as newly visible after permanent deletion. Product Lab cleanup is separate and applies only when explicit Lab ownership is present.

## Related Cases

- TS-108
- TS-125
- TS-128

## Follow-up

- 2026-07-14: reproduced from Recorder/Bed hide-then-delete and fixed at the Guest Control/Product Lab boundary.

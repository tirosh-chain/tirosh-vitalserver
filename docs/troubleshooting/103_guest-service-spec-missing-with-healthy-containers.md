# Guest service spec missing while containers are healthy

## Metadata

- ID: TS-103
- Category: Runtime health / Guest containers / macOS Helper UI
- Owner: Guest Control service resource contract
- Status: active

## Symptom

The Helper advanced status shows Guest product services with a green health indicator, but the text includes:

```text
Healthy | desired missing | observed failed | SpecMissing: Guest service desired state is not configured.
```

The same guest can still serve VitalServer traffic, and `/runtime/stack` can report containers as `running` and `healthy`.

## Cause

Container health and Guest service control resources are separate contracts.

`/runtime/stack` reports observed container state. `/runtime/services/{service}/resource` reports the service-control resource, including the desired state that reconcile/start/stop decisions use.

When the guest service resource repository has no resource for a known product service, Guest Control used to return a synthetic `SpecMissing` resource. That preserved the missing-state signal, but it also left fresh installs with no explicit desired state for normal product services.

## Fix Direction

Known Guest product services must have an explicit default service resource owned by Guest Control:

- `spec.state=configured`
- `spec.desiredState=running`
- `status` populated from the explicit Guest Control service observation when available
- conditions computed from the same reconcile policy used by service commands

Guest Control must seed missing or legacy `spec.state=missing` resources idempotently. It must preserve existing configured desired states, such as an operator-set `desiredState=stopped`.

## Prevention

- Do not hide `SpecMissing` in the UI.
- Do not let Host infer desired state from container health.
- Seed missing product service specs inside Guest Control, the owner of the service resource contract.
- Keep tests that prove stack/status reads populate resources without overwriting existing configured specs.

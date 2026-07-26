# Guest Product Process Supervisor

`guest-product-process-supervisor` is the Guest-local process-lifetime owner
for the two required Runtime Platform product processes:

- `guest-runtime`, which owns Guest Runtime control state and its SQLite store;
- `recorder-gateway`, which owns recorder ingress, durable ingress state,
  cold-path capture, and VitalServer delivery replay.

It is neither a generic process manager nor a Host VM lifecycle service. It
does not create C37 deployment input, decide Host lifecycle transitions, read
Guest Runtime state, inspect Recorder Gateway delivery state, or infer service
health from child output. Its sole job is to apply the already-declared
required-process lifetime policy.

## Bounded-context map

| Location | Owns / does | Does not own |
| --- | --- | --- |
| `internal/guestproductprocesssupervisordomain/` | pure C37 validation, C44/C46 delivery resolution, and `GuestProductProcessInvocation` planning | filesystem, OS process, HTTP, SQLite, or upstream effects |
| `internal/guestproductprocesssupervisorapplication/` | resolves complete Gateway delivery input, then orders start, observed exit, sibling termination, and explicit shutdown through ports | deployment configuration parsing or process policy invention |
| `internal/adapters/guestproductdeploymentconfigurationfile/` | strict file decoding of C37 process deployment, C44 topology, and C46 external delivery configuration | current process state or fallback configuration |
| `internal/adapters/guestprocessoslauncher/` | starts, waits for, and terminates the explicit OS child process | ownership of the desired deployment policy |
| `cmd/guest-product-process-supervisor/` | command-line composition, signal-to-shutdown mapping, and diagnostics | domain policy or state persistence |

## Lifecycle contract

```text
C37 GuestProductProcessDeploymentConfiguration + C44 topology + optional C46 configuration (desired input)
  -> ValidateGuestProductProcessDeploymentConfiguration / ValidateGuestProductVitalServerTopologyDeployment / ValidateExternalVitalServerDeliveryConfiguration (pure rules)
  -> ResolveRecorderGatewayVitalServerDelivery (pure C37+C44+C46 equality decision)
  -> PlanGuestProductProcessInvocations (pure plan)
  -> RunGuestProductProcessDeployment (application orchestration)
  -> GuestProductProcessLauncher.StartGuestProductProcess (OS effect port)
  -> GuestProductProcessLifecycleHandle
       -> observed child exit: terminate the other required child
       -> explicit supervisor shutdown: terminate both required children
```

An observed child exit is a fact, not a new domain state invented by this
supervisor. If sibling termination fails, the application returns
`GuestProductProcessTerminationError`; it never reports a clean shutdown.
If startup fails after the first required child began, the supervisor stops the
already-started child before returning `GuestProductProcessStartError`.

## Naming rules in this module

Public names retain the owner, managed concept, and role:

- `GuestProductProcessDeploymentConfiguration` is desired C37 input, not live
  process state.
- `GuestProductProcessLifecycleHandle` is the result of an OS start effect;
  `WaitForGuestProductProcessExit` reads an observed child-exit fact.
- `GuestProductProviderCapabilityReference` selects a configured capability;
  it does not claim that a provider is reachable.
- `ExternalVitalServerDeliveryConfiguration` is C46 desired input owned by the
  external delivery deployment administrator; it is not a C16 availability
  observation or a Recorder delivery receipt.
- `ResolveRecorderGatewayVitalServerDelivery` describes a pure comparison of
  C37, C44, and C46. It does not open a connection or discover an endpoint.
- `GuestProductProcessDeploymentConfigurationSchemaVersion` belongs to C37;
  a bare `SchemaVersion` would hide that boundary.

These names are intentionally longer than generic `Config`, `Process`, or
`Get` names so imports, stack traces, tests, and operational errors preserve
the same domain meaning.

## Run

The command requires an explicit, absolute C37 path:

```sh
guest-product-process-supervisor \
  --deployment-configuration /etc/vitalserver/guest-product-process-deployment.json
```

Missing, unreadable, malformed, or semantically invalid C37/C44/C46 input is
reported as an error. C46 is required only when C44 selects external VitalServer
placement; C41/C35/C39/C40 install the deployment administrator's selected,
non-secret C46 document at its declared Guest path. The command does not create a
replacement document or launch children with inferred settings.

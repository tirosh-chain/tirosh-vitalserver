# Recorder Gateway

The Recorder Gateway owns the Recorder-facing data plane:

- the Socket.IO v2-compatible connection session created by `join_vr`;
- packet admission and Gateway-private durable ingress state;
- a temporary VitalServer delivery-replay payload for every admitted packet;
- an independently retained cold-path packet capture for archive formation;
- immutable C5 `RecorderIngressReceipt` after durable admission;
- one immutable C13 `VitalServerDeliveryReceipt` per VitalServer delivery attempt; and
- bounded replay/lease recovery.

It does **not** own VitalServer clinical state, VitalServer connection health,
archive/export policy, Lab resource lifecycle, or UI rendering. `req_cmd` is
recognized only to return an explicit `unsupported` acknowledgement; command
execution is not silently proxied.

## Runtime boundary

`src/recordergatewaydomain/` is pure contract and delivery-replay policy.
`src/recordergatewayapplication/` serializes a Recorder ingress, cold-path capture,
or VitalServer delivery-replay operation and depends only on explicit ports.
`src/adapters/recordergatewayingressdurablestatefile/` owns the Gateway’s durable
ingress-state files; `src/adapters/recordergatewayinbound/` owns Socket.IO and
the Recorder Gateway control HTTP surface; and
`src/adapters/vitalserverpacketdeliverysocketio/` owns the explicit VitalServer
packet-delivery acknowledgement transport. The composition root is
`src/recorder-gateway-runtime-composition.ts`.

The filename is part of the bounded-context language. A reader should not have to
open `service.ts`, `ports.ts`, `policy.ts`, `runtime.ts`, or `mutex.ts` to discover
which product responsibility it has. The durable source modules are deliberately
named as follows:

| Layer | Module | Responsibility |
| --- | --- | --- |
| Domain | `recorder-gateway-ingress-and-cold-path-contracts.ts` | C5/C13-shaped ingress, delivery replay, cold-path capture, and read-result facts |
| Domain | `recorder-gateway-vital-server-delivery-replay-policy.ts` | pure ingress admission, VitalServer delivery retry, delivery-replay settlement, and cold-path retention decisions |
| Application | `recorder-gateway-ingress-and-cold-path-application-ports.ts` | durable-state, clock, identifier, and VitalServer packet-delivery effect boundaries |
| Application | `recorder-gateway-ingress-and-cold-path-application-service.ts` | one Recorder Gateway ingress, cold-path capture, read, and delivery-replay workflow |
| Application | `recorder-gateway-ingress-durable-state-operation-mutex.ts` | in-process serialization for one Gateway durable-state writer; never durable state ownership |
| Composition | `recorder-gateway-runtime-composition.ts` | wires the selected file/socket/clock adapters; does not create policy |

The type names (`RecorderGatewayIngressDurableStateStore`, `RecorderGatewayClock`,
`VitalServerPacketDeliveryPort`) identify the specific owned state or external effect
inside the `RecorderGateway` context. Their implementations carry their external
mechanism in the adapter name, such as `FileRecorderGatewayIngressDurableStateStore`
and `SocketIoVitalServerPacketDeliveryPort`.

The file adapter writes one atomically replaced record containing a public receipt, a temporary delivery-replay payload, and an independently retained cold-path packet capture. A packet is acknowledged as `accepted` only after this write succeeds. Exhausted delivery-replay capacity yields `rejected/vitalserver-delivery-replay-capacity-reached` with no C5 receipt; an uncertain write yields `failed/ingress-admission-outcome-unknown`, never a guessed success.

`GuestProductProcessSupervisor` is the Guest-local process-lifetime owner. It
derives every Recorder Gateway command argument from C37
`GuestProductProcessDeploymentConfiguration`: listener, durable ingress-state directory,
delivery-replay admission limits, cold-path capture limits, delivery endpoint placement,
provider identity, acknowledgement timeout, and replay limits. The executable accepts
none of those as a product default. A direct standalone invocation must therefore
provide all of them explicitly.

## Local verification

Use Node `>=20.19.0 <21`. The package declaration and
`make -C runtime-platform recorder-gateway-check` require that range; the
selected `npm` must run with that same Node executable:

```sh
cd runtime-platform/services/recorder-gateway
npm ci
npm test
```

The integration test uses a small, test-only Engine.IO v3 / Socket.IO protocol-v4 wire fixture to prove the Socket.IO v2 Recorder handshake without shipping an obsolete v2 client library. It covers text and binary `send_data`, reconnect/session reset, explicit `req_cmd` rejection, public receipt reads, VitalServer acknowledgement, delivery-replay capacity backpressure, independent cold-path capture retention, and bounded retry receipts. `make -C runtime-platform recorder-gateway-acceptance` repeats the scenario through public HTTP/Socket.IO contracts and validates emitted C5/C13 documents against canonical schemas.

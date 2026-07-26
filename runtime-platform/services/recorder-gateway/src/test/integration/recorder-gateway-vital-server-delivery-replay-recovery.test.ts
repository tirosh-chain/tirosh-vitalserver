import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { FileRecorderGatewayIngressDurableStateStore } from "../../adapters/recordergatewayingressdurablestatefile/file-recorder-gateway-ingress-durable-state-store.js";
import {
  RecorderGatewayIngressAndColdPathApplicationService,
  type RecorderGatewayIngressAndColdPathServiceConfiguration,
} from "../../recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-service.js";
import type {
  RecorderGatewayClock,
  RecorderGatewayIdentifierGenerator,
  VitalServerPacketDeliveryInput,
  VitalServerPacketDeliveryPort,
} from "../../recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-ports.js";
import type {
  RecorderGatewayDeliveryReplayUsage,
  RecorderGatewayConnection,
  RecorderPacketIngressInput,
  VitalServerDeliveryAttemptOutcome,
} from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";

class ManualRecorderGatewayClock implements RecorderGatewayClock {
  public constructor(private value: Date) {}

  public now(): Date {
    return new Date(this.value);
  }

  public advance(milliseconds: number): void {
    this.value = new Date(this.value.getTime() + milliseconds);
  }
}

class SequentialRecorderGatewayIdentifierGenerator implements RecorderGatewayIdentifierGenerator {
  private sequence = 0;

  public newRecorderGatewayIdentifier(prefix: string): string {
    this.sequence += 1;
    return `${prefix}-${this.sequence}`;
  }
}

class SequencedVitalServerPacketDelivery implements VitalServerPacketDeliveryPort {
  public readonly inputs: VitalServerPacketDeliveryInput[] = [];

  public constructor(private readonly outcomes: VitalServerDeliveryAttemptOutcome[]) {}

  public async deliverRecorderPacketToVitalServer(input: VitalServerPacketDeliveryInput): Promise<VitalServerDeliveryAttemptOutcome> {
    this.inputs.push(input);
    const outcome = this.outcomes.shift();
    if (outcome === undefined) {
      throw new Error("test VitalServer delivery adapter received an unexpected delivery attempt");
    }
    return outcome;
  }
}

test("VitalServer delivery replay capacity, retry receipts, and cold-path capture remain separate durable facts", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "recorder-gateway-delivery-replay-recovery-"));
  context.after(async () => {
    await rm(directory, { recursive: true, force: true });
  });
  const clock = new ManualRecorderGatewayClock(new Date("2026-07-17T00:00:00.000Z"));
  const vitalServerDelivery = new SequencedVitalServerPacketDelivery([
    { state: "unavailable", issue: { code: "fixture-vitalserver-unavailable", message: "fixture VitalServer is unavailable", retryable: true } },
    { state: "succeeded" },
  ]);
  const store = new FileRecorderGatewayIngressDurableStateStore(directory);
  const service = new RecorderGatewayIngressAndColdPathApplicationService(
    store,
    vitalServerDelivery,
    clock,
    new SequentialRecorderGatewayIdentifierGenerator(),
    recorderGatewayIngressAndColdPathConfiguration({ maxPendingItems: 1, maxPendingBytes: 1024 }),
  );
  await service.initializeRecorderGatewayIngressDurableState();
  const connection: RecorderGatewayConnection = { sessionId: "socket-session-fixture", protocolVersion: "v2" };
  const coldPathCaptureId = await openRecorderColdPathCapture(service, "recorder-fixture", connection);
  const input: RecorderPacketIngressInput = {
    recorderId: "recorder-fixture",
    connection,
    coldPathCaptureId,
    payload: Buffer.from([7, 8, 9]),
    payloadEncoding: "binary",
    identity: { kind: "gateway-allocated" },
  };
  const admitted = await service.admitRecorderPacket(input);
  assert.equal(admitted.acknowledgement.state, "accepted");
  assert.ok(admitted.receipt);

  const capacityReached = await service.admitRecorderPacket(input);
  assert.equal(capacityReached.acknowledgement.state, "rejected");
  assert.equal(capacityReached.acknowledgement.issue?.code, "vitalserver-delivery-replay-capacity-reached");
  assert.equal(capacityReached.acknowledgement.receiptId, undefined);

  const unavailableAttempt = await service.replayOneDueVitalServerDelivery();
  assert.equal(unavailableAttempt.state, "completed");
  assert.equal(unavailableAttempt.deliveryReceipt?.outcome.state, "unavailable");
  assert.equal(unavailableAttempt.deliveryReceipt?.retry.state, "scheduled");
  assert.equal(unavailableAttempt.deliveryReceipt?.attempt, 1);

  clock.advance(1000);
  const succeededAttempt = await service.replayOneDueVitalServerDelivery();
  assert.equal(succeededAttempt.state, "completed");
  assert.equal(succeededAttempt.deliveryReceipt?.outcome.state, "succeeded");
  assert.equal(succeededAttempt.deliveryReceipt?.retry.state, "not-scheduled");
  assert.equal(succeededAttempt.deliveryReceipt?.attempt, 2);
  assert.equal(vitalServerDelivery.inputs.length, 2);

  const ingress = await service.readRecorderIngressReceipt(admitted.acknowledgement.receiptId ?? "");
  assert.equal(ingress.state, "available");
  assert.equal(ingress.value?.delivery.state, "requested");
  const firstDelivery = await store.findVitalServerDeliveryReceiptForAttempt(ingress.value?.delivery.requestId ?? "", 1);
  const secondDelivery = await store.findVitalServerDeliveryReceiptForAttempt(ingress.value?.delivery.requestId ?? "", 2);
  assert.equal(firstDelivery?.outcome.state, "unavailable");
  assert.equal(secondDelivery?.outcome.state, "succeeded");
  const latestDelivery = await service.readLatestVitalServerDeliveryForIngressReceipt(
    admitted.acknowledgement.receiptId ?? "",
  );
  assert.equal(latestDelivery.state, "available");
  assert.equal(latestDelivery.value?.attempt, 2);
  assert.equal(latestDelivery.value?.outcome.state, "succeeded");

  const retainedColdPathPackets = await store.readRecorderColdPathCapturedPackets(coldPathCaptureId);
  assert.equal(retainedColdPathPackets.length, 1);
  const retainedColdPathPacket = retainedColdPathPackets[0];
  assert.ok(retainedColdPathPacket);
  assert.deepEqual(Buffer.from(retainedColdPathPacket.payloadBase64, "base64"), Buffer.from([7, 8, 9]));
});

test("caller-supplied ingress identities make an acknowledged Lab replay packet idempotent", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "recorder-gateway-idempotent-ingress-"));
  context.after(async () => {
    await rm(directory, { recursive: true, force: true });
  });
  const service = new RecorderGatewayIngressAndColdPathApplicationService(
    new FileRecorderGatewayIngressDurableStateStore(directory),
    new SequencedVitalServerPacketDelivery([]),
    new ManualRecorderGatewayClock(new Date("2026-07-17T00:00:00.000Z")),
    new SequentialRecorderGatewayIdentifierGenerator(),
    recorderGatewayIngressAndColdPathConfiguration({ maxPendingItems: 1 }),
  );
  await service.initializeRecorderGatewayIngressDurableState();
  const connection: RecorderGatewayConnection = {
    sessionId: "socket-session-idempotent",
    protocolVersion: "v2",
  };
  const coldPathCaptureId = await openRecorderColdPathCapture(
    service,
    "recorder-idempotent",
    connection,
  );
  const input: RecorderPacketIngressInput = {
    recorderId: "recorder-idempotent",
    connection,
    coldPathCaptureId,
    payload: Buffer.from([1, 2, 3]),
    payloadEncoding: "binary",
    identity: {
      kind: "caller-supplied",
      receiptId: "lab-ingress-receipt-1",
      requestId: "lab-ingress-request-1",
      deliveryRequestId: "lab-delivery-request-1",
      packetId: "lab-packet-1",
      durableIngressStateReceiptId: "lab-durable-receipt-1",
    },
  };
  const first = await service.admitRecorderPacket(input);
  const retry = await service.admitRecorderPacket({
    ...input,
    connection: { sessionId: "socket-session-reconnected", protocolVersion: "v2" },
    coldPathCaptureId: "new-capture-is-not-read-for-an-existing-identity",
  });
  assert.equal(first.acknowledgement.state, "accepted");
  assert.equal(retry.acknowledgement.state, "accepted");
  assert.equal(retry.acknowledgement.receiptId, first.acknowledgement.receiptId);

  const conflict = await service.admitRecorderPacket({
    ...input,
    payload: Buffer.from([9]),
  });
  assert.equal(conflict.acknowledgement.state, "rejected");
  assert.equal(conflict.acknowledgement.issue?.code, "recorder-ingress-idempotency-conflict");
});

test("an expired VitalServer delivery replay lease records unknown delivery before any retry", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "recorder-gateway-expired-delivery-replay-lease-"));
  context.after(async () => {
    await rm(directory, { recursive: true, force: true });
  });
  const clock = new ManualRecorderGatewayClock(new Date("2026-07-17T00:00:00.000Z"));
  const store = new FileRecorderGatewayIngressDurableStateStore(directory);
  const vitalServerDelivery = new SequencedVitalServerPacketDelivery([]);
  const service = new RecorderGatewayIngressAndColdPathApplicationService(
    store,
    vitalServerDelivery,
    clock,
    new SequentialRecorderGatewayIdentifierGenerator(),
    recorderGatewayIngressAndColdPathConfiguration({ leaseDurationMs: 500 }),
  );
  await service.initializeRecorderGatewayIngressDurableState();
  const connection: RecorderGatewayConnection = { sessionId: "socket-session-expired-lease", protocolVersion: "v2" };
  const coldPathCaptureId = await openRecorderColdPathCapture(service, "recorder-expired-lease", connection);
  const admitted = await service.admitRecorderPacket({
    recorderId: "recorder-expired-lease",
    connection,
    coldPathCaptureId,
    payload: Buffer.from([5]),
    payloadEncoding: "binary",
    identity: { kind: "gateway-allocated" },
  });
  assert.equal(admitted.acknowledgement.state, "accepted");
  assert.ok(admitted.receipt);
  const claim = await store.claimNextDueRecorderGatewayDeliveryReplayRecord(clock.now(), new Date(clock.now().getTime() + 500));
  assert.equal(claim?.deliveryReplay.attempt, 1);
  clock.advance(501);

  const replay = await service.replayOneDueVitalServerDelivery();
  assert.equal(replay.state, "idle");
  const unknownReceipt = await store.findVitalServerDeliveryReceiptForAttempt(admitted.receipt.delivery.requestId, 1);
  assert.equal(unknownReceipt?.outcome.state, "unknown");
  assert.equal(unknownReceipt?.outcome.issue?.code, "delivery-attempt-lease-expired");
  assert.equal(unknownReceipt?.retry.state, "scheduled");
  assert.equal(vitalServerDelivery.inputs.length, 0);
});

test("delivery replay capacity read failure produces explicit failed admission without a receipt", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "recorder-gateway-delivery-replay-usage-unavailable-"));
  context.after(async () => {
    await rm(directory, { recursive: true, force: true });
  });
  const service = new RecorderGatewayIngressAndColdPathApplicationService(
    new DeliveryReplayUsageUnavailableDurableStateStore(directory),
    new SequencedVitalServerPacketDelivery([]),
    new ManualRecorderGatewayClock(new Date("2026-07-17T00:00:00.000Z")),
    new SequentialRecorderGatewayIdentifierGenerator(),
    recorderGatewayIngressAndColdPathConfiguration(),
  );
  await service.initializeRecorderGatewayIngressDurableState();
  const connection: RecorderGatewayConnection = { sessionId: "socket-session-unavailable-store", protocolVersion: "v2" };
  const coldPathCaptureId = await openRecorderColdPathCapture(service, "recorder-unavailable-store", connection);
  const admission = await service.admitRecorderPacket({
    recorderId: "recorder-unavailable-store",
    connection,
    coldPathCaptureId,
    payload: Buffer.from([1]),
    payloadEncoding: "binary",
    identity: { kind: "gateway-allocated" },
  });
  assert.equal(admission.acknowledgement.state, "failed");
  assert.equal(admission.acknowledgement.issue?.code, "recorder-gateway-ingress-durable-state-unavailable");
  assert.equal(admission.acknowledgement.receiptId, undefined);
  assert.equal(admission.receipt, undefined);
});

test("a legacy delivery-only record is explicitly migrated without inventing a cold-path capture", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "recorder-gateway-legacy-delivery-only-"));
  context.after(async () => {
    await rm(directory, { recursive: true, force: true });
  });
  const ingressRecordsDirectory = join(directory, "ingress-records");
  await mkdir(ingressRecordsDirectory, { recursive: true });
  await writeFile(
    join(ingressRecordsDirectory, "ingress-receipt-legacy-1.json"),
    `${JSON.stringify({
      schemaVersion: "v1",
      receipt: {
        schemaVersion: "v1",
        id: "ingress-receipt-legacy-1",
        requestId: "ingress-request-legacy-1",
        recorderId: "recorder-legacy-1",
        connection: { sessionId: "socket-session-legacy-1", protocolVersion: "v2" },
        packet: {
          packetId: "packet-legacy-1",
          byteCount: 3,
          payloadDigest: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          receivedAt: "2026-07-17T00:00:00.000Z",
          parseState: "accepted",
        },
        ingressState: "accepted",
        spoolHandoff: {
          state: "stored",
          spoolReceiptId: "spool-receipt-legacy-1",
          persistedAt: "2026-07-17T00:00:00.000Z",
        },
        delivery: { state: "requested", requestId: "delivery-request-legacy-1" },
        recordedAt: "2026-07-17T00:00:00.000Z",
      },
      payloadBase64: Buffer.from([7, 8, 9]).toString("base64"),
      payloadEncoding: "binary",
      attempt: 0,
      state: "pending",
    })}\n`,
    "utf8",
  );

  const store = new FileRecorderGatewayIngressDurableStateStore(directory);
  await store.initializeRecorderGatewayIngressDurableState();

  const migratedRecord = JSON.parse(await readFile(join(ingressRecordsDirectory, "ingress-receipt-legacy-1.json"), "utf8")) as {
    receipt: { durableIngressStateHandoff: { durableIngressStateReceiptId: string }; coldPathCapture?: unknown };
    deliveryReplay: { state: string; payloadBase64?: string };
    coldPathPacketCapture?: unknown;
  };
  assert.equal(migratedRecord.receipt.durableIngressStateHandoff.durableIngressStateReceiptId, "spool-receipt-legacy-1");
  assert.equal(migratedRecord.receipt.coldPathCapture, undefined);
  assert.equal(migratedRecord.deliveryReplay.state, "pending");
  assert.equal(migratedRecord.deliveryReplay.payloadBase64, Buffer.from([7, 8, 9]).toString("base64"));
  assert.equal(migratedRecord.coldPathPacketCapture, undefined);
  assert.deepEqual(await store.readRecorderColdPathCaptureUsage(), { retainedPacketCount: 0, retainedPayloadBytes: 0 });
});

class DeliveryReplayUsageUnavailableDurableStateStore extends FileRecorderGatewayIngressDurableStateStore {
  public override async readRecorderGatewayDeliveryReplayUsage(): Promise<RecorderGatewayDeliveryReplayUsage> {
    throw new Error("test durable state store cannot read delivery replay usage");
  }
}

async function openRecorderColdPathCapture(
  service: RecorderGatewayIngressAndColdPathApplicationService,
  recorderId: string,
  connection: RecorderGatewayConnection,
): Promise<string> {
  const opened = await service.openRecorderColdPathCapture({ recorderId, connection });
  assert.equal(opened.state, "opened");
  assert.ok(opened.capture);
  return opened.capture.id;
}

function recorderGatewayIngressAndColdPathConfiguration(
  overrides: Partial<RecorderGatewayIngressAndColdPathServiceConfiguration["ingressAdmission"] & RecorderGatewayIngressAndColdPathServiceConfiguration["replay"]> = {},
): RecorderGatewayIngressAndColdPathServiceConfiguration {
  return {
    ingressAdmission: {
      maxPendingItems: overrides.maxPendingItems ?? 2,
      maxPendingBytes: overrides.maxPendingBytes ?? 1024,
    },
    coldPathCapture: {
      maxRetainedPackets: 4,
      maxRetainedPayloadBytes: 1024,
    },
    replay: {
      maxAttempts: overrides.maxAttempts ?? 2,
      retryDelayMs: overrides.retryDelayMs ?? 1000,
      leaseDurationMs: overrides.leaseDurationMs ?? 5000,
    },
    provider: { kind: "vitalserver", id: "vitalserver-fixture", capabilityRevision: 1 },
  };
}

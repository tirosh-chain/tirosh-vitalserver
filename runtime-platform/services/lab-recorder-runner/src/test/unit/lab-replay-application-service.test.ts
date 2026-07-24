import assert from "node:assert/strict";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { FileLabReplaySessionStore } from "../../adapters/labreplaystatefile/file-lab-replay-session-store.js";
import { LabReplayApplicationService } from "../../labrecorderrunnerapplication/lab-replay-application-service.js";
import type {
  LabRecorderRunnerClock,
  LabRecorderRunnerIdentifierGenerator,
  LabReplayGatewayFrameAdmission,
  LabReplayGatewayPort,
} from "../../labrecorderrunnerapplication/lab-recorder-runner-ports.js";
import { labReplayBatchId } from "../../labrecorderrunnerdomain/lab-replay-contracts.js";

class FixedClock implements LabRecorderRunnerClock {
  public constructor(private readonly value: Date) {}

  public now(): Date {
    return new Date(this.value);
  }
}

class FixedIdentifiers implements LabRecorderRunnerIdentifierGenerator {
  public newLabRecorderRunnerIdentifier(prefix: string): string {
    return `${prefix}-1`;
  }
}

class ReplayGateway implements LabReplayGatewayPort {
  public deliveryState: "pending" | "succeeded" | "terminal-failed" = "pending";
  public admissions: LabReplayGatewayFrameAdmission[][] = [];

  public async admitFrames(
    _recorderGatewayRecorderCode: string,
    frames: LabReplayGatewayFrameAdmission[],
  ) {
    this.admissions.push(frames);
    return {
      state: "accepted" as const,
      ingressReceiptIds: frames.map((frame) => frame.identity.receiptId),
    };
  }

  public async readLatestDelivery(ingressReceiptId: string) {
    if (this.deliveryState === "pending") {
      return { state: "pending" as const };
    }
    if (this.deliveryState === "terminal-failed") {
      return {
        state: "available" as const,
        deliveryReceiptId: `delivery-${ingressReceiptId}`,
        attemptOutcome: "failed" as const,
        retryState: "exhausted" as const,
      };
    }
    return {
      state: "available" as const,
      deliveryReceiptId: `delivery-${ingressReceiptId}`,
      attemptOutcome: "succeeded" as const,
      retryState: "not-scheduled" as const,
    };
  }
}

test("Lab replay Runner persists preparation, idempotent batch cursor, and upstream delivery evidence", async (context) => {
  const root = await mkdtemp(join(tmpdir(), "lab-replay-runner-state-"));
  context.after(async () => {
    await rm(root, { recursive: true, force: true });
  });
  const store = new FileLabReplaySessionStore(root);
  const gateway = new ReplayGateway();
  const service = new LabReplayApplicationService(
    store,
    gateway,
    new FixedClock(new Date("2026-07-24T16:00:00Z")),
    new FixedIdentifiers(),
  );
  await service.initialize();
  const prepared = await service.prepare({
    schemaVersion: "v1",
    replayId: "replay-1",
    recorderGatewayRecorderCode: "LAB-01",
    spoolDatabaseSha256: "a".repeat(64),
    frameCount: 1,
  });
  assert.equal(prepared.state, "accepted");
  if (prepared.state !== "accepted") {
    return;
  }
  const frame = {
    offsetSeconds: 0,
    outputTime: prepared.receipt.outputStartedAt,
    tracks: [{
      outputTrackId: 1,
      sourceTrackId: 1,
      kind: 2 as const,
      name: "PLETH_HR",
      deviceName: "Solar8000",
      unit: "/min",
      monitorType: 9,
      numericValue: 72,
    }],
  };
  const command = {
    schemaVersion: "v1",
    replayId: "replay-1",
    runnerSessionId: prepared.receipt.runnerSessionId,
    batchId: labReplayBatchId("replay-1", 0, 1),
    startOffsetSecond: 0,
    frames: [frame],
    finalBatch: true,
  };
  const sent = await service.sendBatch(command);
  const retried = await service.sendBatch(command);
  assert.equal(sent.state, "accepted");
  assert.deepEqual(retried, sent);
  assert.equal(gateway.admissions.length, 1);

  const pending = await service.confirmUpstream({
    schemaVersion: "v1",
    replayId: "replay-1",
    runnerSessionId: prepared.receipt.runnerSessionId,
    expectedFrameCount: 1,
  });
  assert.equal(pending.state, "failed");
  gateway.deliveryState = "succeeded";
  const delivered = await service.confirmUpstream({
    schemaVersion: "v1",
    replayId: "replay-1",
    runnerSessionId: prepared.receipt.runnerSessionId,
    expectedFrameCount: 1,
  });
  assert.equal(delivered.state, "accepted");

  const restarted = new LabReplayApplicationService(
    new FileLabReplaySessionStore(root),
    gateway,
    new FixedClock(new Date("2026-07-24T16:01:00Z")),
    new FixedIdentifiers(),
  );
  await restarted.initialize();
  const recoveredPreparation = await restarted.prepare({
    schemaVersion: "v1",
    replayId: "replay-1",
    recorderGatewayRecorderCode: "LAB-01",
    spoolDatabaseSha256: "a".repeat(64),
    frameCount: 1,
  });
  const recoveredDelivery = await restarted.confirmUpstream({
    schemaVersion: "v1",
    replayId: "replay-1",
    runnerSessionId: prepared.receipt.runnerSessionId,
    expectedFrameCount: 1,
  });
  assert.deepEqual(recoveredPreparation, prepared);
  assert.deepEqual(recoveredDelivery, delivered);
});

test("Lab replay Runner does not turn exhausted Gateway delivery into success", async (context) => {
  const root = await mkdtemp(join(tmpdir(), "lab-replay-runner-failure-"));
  context.after(async () => {
    await rm(root, { recursive: true, force: true });
  });
  const gateway = new ReplayGateway();
  gateway.deliveryState = "terminal-failed";
  const service = new LabReplayApplicationService(
    new FileLabReplaySessionStore(root),
    gateway,
    new FixedClock(new Date("2026-07-24T16:00:00Z")),
    new FixedIdentifiers(),
  );
  await service.initialize();
  const prepared = await service.prepare({
    schemaVersion: "v1",
    replayId: "replay-failed",
    recorderGatewayRecorderCode: "LAB-02",
    spoolDatabaseSha256: "b".repeat(64),
    frameCount: 1,
  });
  assert.equal(prepared.state, "accepted");
  if (prepared.state !== "accepted") {
    return;
  }
  await service.sendBatch({
    schemaVersion: "v1",
    replayId: "replay-failed",
    runnerSessionId: prepared.receipt.runnerSessionId,
    batchId: labReplayBatchId("replay-failed", 0, 1),
    startOffsetSecond: 0,
    frames: [{
      offsetSeconds: 0,
      outputTime: prepared.receipt.outputStartedAt,
      tracks: [{
        outputTrackId: 1,
        sourceTrackId: 1,
        kind: 2,
        name: "HR",
        deviceName: "Monitor",
        unit: "/min",
        monitorType: 2,
        numericValue: 70,
      }],
    }],
    finalBatch: true,
  });
  const result = await service.confirmUpstream({
    schemaVersion: "v1",
    replayId: "replay-failed",
    runnerSessionId: prepared.receipt.runnerSessionId,
    expectedFrameCount: 1,
  });
  assert.equal(result.state, "rejected");
  if (result.state !== "rejected") {
    return;
  }
  assert.equal(result.issue.code, "vitalserver-delivery-terminal-failure");
});

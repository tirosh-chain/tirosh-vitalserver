"use strict";

const assert = require("assert");
const test = require("node:test");
const { createSendDataReplayWorker, replayBatchLimit } = require("../../src/application/send-data-replay-worker");
const {
  configureSendDataSpool,
  createMetrics,
  metricsSnapshot,
  recordSendDataSpoolSpooled,
} = require("../../src/observability/metrics");

test("send_data replay worker marks successful claimed item as replayed", async () => {
  const metricState = replayMetrics();
  recordSendDataSpoolSpooled(metricState, "VR_A", 7, 1);
  const moves = [];
  const worker = createSendDataReplayWorker({
    config: spoolConfig(),
    metrics: metricState,
    spoolStore: {
      claim() {
        return Promise.resolve({ ok: true, item: spoolItem({ state: "in_flight", attemptCount: 1 }), claim: { raw: "raw" } });
      },
      markReplayed(item, claim) {
        moves.push({ target: "replayed", item, claim });
        return Promise.resolve({ ok: true, depth: 1 });
      },
    },
    replayTarget: {
      send(item) {
        assert.strictEqual(item.id, "senddata_test");
        return Promise.resolve({ ok: true });
      },
    },
  });

  const result = await worker.runOnce();

  assert.deepStrictEqual(result, { ok: true, processed: 1 });
  assert.strictEqual(moves.length, 1);
  assert.strictEqual(moves[0].item.state, "replayed");
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.replay.replayedEvents, 1);
  assert.strictEqual(snapshot.replay.inFlightItems, 0);
  assert.strictEqual(snapshot.replay.pendingItems, 0);
  assert.strictEqual(snapshot.spool.pendingItems, 0);
  assert.strictEqual(snapshot.spool.pendingBytes, 0);
  assert.strictEqual(snapshot.recorders[0].replay.replayedEvents, 1);
  assert.strictEqual(snapshot.recorders[0].spool.pendingItems, 0);
});

test("send_data replay worker requeues upstream unavailable before max attempts", async () => {
  const metricState = replayMetrics();
  const moves = [];
  const worker = createSendDataReplayWorker({
    config: spoolConfig({ replay: replayConfig({ maxAttempts: 3 }) }),
    metrics: metricState,
    spoolStore: {
      claim() {
        return Promise.resolve({ ok: true, item: spoolItem({ state: "in_flight", attemptCount: 1 }), claim: { raw: "raw" } });
      },
      requeue(item, claim) {
        moves.push({ target: "pending", item, claim });
        return Promise.resolve({ ok: true, depth: 1 });
      },
    },
    replayTarget: {
      send() {
        return Promise.resolve({ ok: false, reason: "upstream_unavailable", message: "connect ECONNREFUSED" });
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.processed, 1);
  assert.strictEqual(moves[0].item.state, "retryable_failed");
  assert.strictEqual(moves[0].item.lastFailure.reason, "upstream_unavailable");
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.replay.retryableFailures, 1);
  assert.strictEqual(snapshot.replay.pendingItems, 1);
  assert.strictEqual(snapshot.replay.lastFailure.reason, "upstream_unavailable");
});

test("send_data replay worker lowers adaptive replay rate after upstream failure", async () => {
  const adaptiveSpoolConfig = spoolConfig({
    replay: replayConfig({
      batchSize: 8,
      maxBytesPerSecond: 8 * 1024 * 1024,
      adaptive: {
        enabled: true,
        minBytesPerSecond: 2 * 1024 * 1024,
        maxBytesPerSecond: 8 * 1024 * 1024,
        minItemsPerTick: 8,
        maxItemsPerTick: 8,
      },
    }),
  });
  const metricState = replayMetrics(adaptiveSpoolConfig);
  const worker = createSendDataReplayWorker({
    config: adaptiveSpoolConfig,
    metrics: metricState,
    memoryGuard: loadedMemoryGuard(0.4),
    spoolStore: {
      claim() {
        return Promise.resolve({ ok: true, item: spoolItem({ state: "in_flight", attemptCount: 1 }), claim: { raw: "raw" } });
      },
      requeue(item) {
        return Promise.resolve({ ok: true, item, depth: 1 });
      },
    },
    replayTarget: {
      send() {
        return Promise.resolve({ ok: false, reason: "upstream_unavailable", message: "connect ECONNREFUSED" });
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.processed, 8);
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.replay.maxBytesPerSecond, 4 * 1024 * 1024);
  assert.strictEqual(snapshot.replay.adaptive.currentMaxBytesPerSecond, 4 * 1024 * 1024);
  assert.strictEqual(snapshot.replay.adaptive.lastDecision, "decrease");
  assert.strictEqual(snapshot.replay.adaptive.lastReason, "replay_failures");
  assert.strictEqual(snapshot.replay.adaptive.memoryGuardStatus, "healthy");
});

test("send_data replay worker stops after byte budget is consumed", async () => {
  const metricState = replayMetrics(spoolConfig({
    replay: replayConfig({
      batchSize: 10,
      maxBytesPerSecond: 14,
      adaptive: { enabled: false },
    }),
  }));
  let claimed = 0;
  const worker = createSendDataReplayWorker({
    config: spoolConfig({
      replay: replayConfig({
        batchSize: 10,
        maxBytesPerSecond: 14,
        adaptive: { enabled: false },
      }),
    }),
    metrics: metricState,
    spoolStore: {
      claim() {
        claimed += 1;
        return Promise.resolve({ ok: true, item: spoolItem({ state: "in_flight", attemptCount: 1, id: `senddata_${claimed}` }), claim: { raw: `raw-${claimed}` } });
      },
      markReplayed(item) {
        return Promise.resolve({ ok: true, item, depth: 1 });
      },
    },
    replayTarget: {
      send() {
        return Promise.resolve({ ok: true });
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.processed, 2);
  assert.strictEqual(claimed, 2);
});

test("send_data replay worker bounds repeated claim failures by item budget", async () => {
  const metricState = replayMetrics(spoolConfig({
    replay: replayConfig({
      batchSize: 3,
      maxBytesPerSecond: 1024,
      adaptive: { enabled: false },
    }),
  }));
  let claims = 0;
  const worker = createSendDataReplayWorker({
    config: spoolConfig({
      replay: replayConfig({
        batchSize: 3,
        maxBytesPerSecond: 1024,
        adaptive: { enabled: false },
      }),
    }),
    metrics: metricState,
    spoolStore: {
      claim() {
        claims += 1;
        return Promise.resolve({
          ok: false,
          reason: "spool_unavailable",
          message: "redis unavailable",
        });
      },
    },
    replayTarget: {
      send() {
        throw new Error("should not replay without a claim");
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.processed, 0);
  assert.strictEqual(claims, 3);
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.replay.status, "failed");
  assert.strictEqual(snapshot.replay.retryableFailures, 0);
  assert.strictEqual(snapshot.replay.lastFailure.reason, "spool_unavailable");
});

test("send_data replay worker uses adaptive item budget for many small payloads", async () => {
  const config = spoolConfig({
    replay: replayConfig({
      batchSize: 1000,
      maxBytesPerSecond: 20 * 1024 * 1024,
      adaptive: {
        enabled: true,
        minBytesPerSecond: 1 * 1024 * 1024,
        maxBytesPerSecond: 20 * 1024 * 1024,
        minItemsPerTick: 50,
        maxItemsPerTick: 1000,
      },
    }),
  });
  const metricState = replayMetrics(config);
  let claimed = 0;
  let replayed = 0;
  let activeSends = 0;
  let maxActiveSends = 0;
  const worker = createSendDataReplayWorker({
    config,
    metrics: metricState,
    memoryGuard: loadedMemoryGuard(0.4),
    spoolStore: {
      claim() {
        claimed += 1;
        if (claimed > 100) {
          return Promise.resolve({ ok: true, item: null, claim: null });
        }
        return Promise.resolve({
          ok: true,
          item: spoolItem({
            state: "in_flight",
            id: `senddata_${claimed}`,
            payloadBytes: 16,
          }),
          claim: { raw: `raw-${claimed}` },
        });
      },
      markReplayed(item) {
        replayed += 1;
        return Promise.resolve({ ok: true, item, depth: Math.max(0, 100 - replayed) });
      },
    },
    replayTarget: {
      async send() {
        activeSends += 1;
        maxActiveSends = Math.max(maxActiveSends, activeSends);
        await new Promise((resolve) => setTimeout(resolve, 5));
        activeSends -= 1;
        return Promise.resolve({ ok: true });
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.processed, 100);
  assert.strictEqual(replayed, 100);
  assert.strictEqual(maxActiveSends, 8);
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.replay.adaptive.currentItemsPerTick, 1000);
  assert.strictEqual(snapshot.replay.adaptive.currentConcurrency, 8);
  assert.strictEqual(snapshot.replay.adaptive.memoryGuardStatus, "healthy");
});

test("send_data replay worker requeues thrown replay target failure before max attempts", async () => {
  const metricState = replayMetrics();
  const moves = [];
  const worker = createSendDataReplayWorker({
    config: spoolConfig({ replay: replayConfig({ maxAttempts: 3 }) }),
    metrics: metricState,
    spoolStore: {
      claim() {
        return Promise.resolve({ ok: true, item: spoolItem({ state: "in_flight", attemptCount: 1 }), claim: { raw: "raw" } });
      },
      requeue(item, claim) {
        moves.push({ target: "pending", item, claim });
        return Promise.resolve({ ok: true, depth: 1 });
      },
    },
    replayTarget: {
      send() {
        throw new Error("target config failed");
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.processed, 1);
  assert.strictEqual(moves[0].item.state, "retryable_failed");
  assert.strictEqual(moves[0].item.lastFailure.reason, "upstream_unavailable");
  assert.strictEqual(moves[0].item.lastFailure.message, "target config failed");
});

test("send_data replay worker dead-letters invalid claimed spool document", async () => {
  const metricState = replayMetrics();
  const moves = [];
  const worker = createSendDataReplayWorker({
    config: spoolConfig(),
    metrics: metricState,
    spoolStore: {
      claim() {
        return Promise.resolve({
          ok: false,
          reason: "invalid_payload",
          message: "Unexpected token",
          raw: "{bad",
          claim: { raw: "{bad" },
        });
      },
      deadLetter(item, claim) {
        moves.push({ target: "dead_letter", item, claim });
        return Promise.resolve({ ok: true, depth: 1 });
      },
    },
    replayTarget: {
      send() {
        throw new Error("send should not be called");
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.processed, 1);
  assert.strictEqual(moves[0].item.state, "dead_lettered");
  assert.strictEqual(moves[0].item.lastFailure.reason, "invalid_payload");
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.replay.deadLetteredEvents, 1);
});

test("send_data replay worker applies configured batch size", async () => {
  assert.strictEqual(replayBatchLimit({ batchSize: 10, maxBytesPerSecond: 3 }), 10);
  assert.strictEqual(replayBatchLimit({ batchSize: 2, maxBytesPerSecond: 5 }), 2);
});

function replayMetrics(config = spoolConfig()) {
  const metricState = createMetrics();
  configureSendDataSpool(metricState, config);
  return metricState;
}

function spoolConfig(overrides = {}) {
  return {
    enabled: true,
    mode: "spool_and_replay",
    storage: "redis_list",
    listKey: "vitalserver:recorder_ingress:send_data:pending",
    maxPendingItems: 100,
    maxPendingBytes: 1000,
    maxPayloadBytes: 100,
    replay: replayConfig(),
    ...overrides,
  };
}

function replayConfig(overrides = {}) {
  return {
    enabled: true,
    intervalMs: 1000,
    batchSize: 1,
    maxAttempts: 3,
    maxBytesPerSecond: 1,
    targetTimeoutMs: 5000,
    ...overrides,
  };
}

function spoolItem(overrides = {}) {
  return {
    schemaVersion: 1,
    id: "senddata_test",
    state: "in_flight",
    vrcode: "VR_A",
    connectionId: "connection-1",
    requestId: "request-1",
    receivedAt: "2026-06-22T10:00:00.000Z",
    payloadEncoding: "binary",
    payloadBytes: 7,
    payloadBase64: Buffer.from("payload").toString("base64"),
    payloadSummary: { bytes: 7, vrcode: "VR_A" },
    attemptCount: 1,
    lastAttemptAt: "2026-06-22T10:00:01.000Z",
    lastFailure: null,
    ...overrides,
  };
}

function loadedMemoryGuard(ratio) {
  return {
    read() {
      return Promise.resolve({
        status: "loaded",
        vitalServer: {
          memoryUsedBytes: Math.floor(ratio * 1000),
          memoryLimitBytes: 1000,
          usageRatio: ratio,
          observedAt: new Date().toISOString(),
        },
      });
    },
  };
}

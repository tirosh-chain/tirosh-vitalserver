"use strict";

const assert = require("assert");
const test = require("node:test");
const { createSendDataReplayWorker, replayBatchLimit } = require("../../src/application/send-data-replay-worker");
const { configureSendDataSpool, createMetrics, metricsSnapshot } = require("../../src/observability/metrics");

test("send_data replay worker marks successful claimed item as replayed", async () => {
  const metricState = replayMetrics();
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
  assert.strictEqual(snapshot.recorders[0].replay.replayedEvents, 1);
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

test("send_data replay worker applies configured batch and rate limit", async () => {
  assert.strictEqual(replayBatchLimit({ batchSize: 10, rateLimitPerSecond: 3 }), 3);
  assert.strictEqual(replayBatchLimit({ batchSize: 2, rateLimitPerSecond: 5 }), 2);
});

function replayMetrics() {
  const metricState = createMetrics();
  configureSendDataSpool(metricState, spoolConfig());
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
    rateLimitPerSecond: 1,
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

"use strict";

const assert = require("assert");
const test = require("node:test");
const { createSendDataIngressService } = require("../../src/application/send-data-ingress-service");
const {
  configureSendDataSpool,
  createMetrics,
  metricsSnapshot,
} = require("../../src/observability/metrics");

test("send_data ingress service writes accepted payload to durable spool", async () => {
  const metricState = configuredMetrics();
  const writes = [];
  const service = createSendDataIngressService({
    config: { spool: spoolConfig() },
    metrics: metricState,
    spoolStore: {
      append(item) {
        writes.push(item);
        return Promise.resolve({ ok: true, depth: 1 });
      },
    },
    now: () => new Date("2026-06-22T09:00:00.000Z"),
    idFactory: () => "senddata_test",
  });

  const result = await service.record(
    "payload",
    { request_id: "request-1", connection_id: "connection-1", joined_vrcode: "VR_A" },
    { bytes: 7 }
  );

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.outcome, "spooled");
  assert.strictEqual(writes.length, 1);
  assert.strictEqual(writes[0].id, "senddata_test");
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.spool.acceptedEvents, 1);
  assert.strictEqual(snapshot.spool.spooledEvents, 1);
  assert.strictEqual(snapshot.spool.pendingItems, 1);
  assert.strictEqual(snapshot.spool.pendingBytes, 7);
  assert.strictEqual(snapshot.recorders[0].spool.spooledEvents, 1);
});

test("send_data ingress service preserves spool write failure", async () => {
  const metricState = configuredMetrics();
  const service = createSendDataIngressService({
    config: { spool: spoolConfig() },
    metrics: metricState,
    spoolStore: {
      append() {
        return Promise.resolve({ ok: false, error: new Error("redis unavailable") });
      },
    },
    now: () => new Date("2026-06-22T09:00:00.000Z"),
    idFactory: () => "senddata_test",
  });

  const result = await service.record(
    "payload",
    { request_id: "request-1", connection_id: "connection-1", joined_vrcode: "VR_A" },
    { bytes: 7 }
  );

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.outcome, "spool_write_failed");
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.spool.acceptedEvents, 1);
  assert.strictEqual(snapshot.spool.spooledEvents, 0);
  assert.strictEqual(snapshot.spool.writeFailures, 1);
  assert.strictEqual(snapshot.spool.status, "failed");
  assert.strictEqual(snapshot.spool.lastFailure.reason, "spool_write_failed");
  assert.strictEqual(snapshot.spool.lastFailure.message, "redis unavailable");
});

test("send_data ingress service reports spool queue full as backpressure", async () => {
  const metricState = configuredMetrics();
  const queueFull = new Error("redis command queue full length=50001");
  const service = createSendDataIngressService({
    config: { spool: spoolConfig() },
    metrics: metricState,
    spoolStore: {
      append() {
        return Promise.resolve({ ok: false, reason: "spool_full", error: queueFull });
      },
    },
    now: () => new Date("2026-06-22T09:00:00.000Z"),
    idFactory: () => "senddata_test",
  });

  const result = await service.record(
    "payload",
    { request_id: "request-1", connection_id: "connection-1", joined_vrcode: "VR_A" },
    { bytes: 7 }
  );

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.outcome, "rejected");
  assert.strictEqual(result.reason, "spool_full");
  assert.strictEqual(result.message, "redis command queue full length=50001");
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.spool.acceptedEvents, 1);
  assert.strictEqual(snapshot.spool.rejectedEvents, 1);
  assert.strictEqual(snapshot.spool.writeFailures, 0);
  assert.strictEqual(snapshot.spool.status, "degraded");
  assert.strictEqual(snapshot.spool.lastFailure.reason, "spool_full");
});

test("send_data ingress service preserves thrown spool dependency failure", async () => {
  const metricState = configuredMetrics();
  const service = createSendDataIngressService({
    config: { spool: spoolConfig() },
    metrics: metricState,
    spoolStore: {
      append() {
        throw new Error("spool dependency crashed");
      },
    },
    now: () => new Date("2026-06-22T09:00:00.000Z"),
    idFactory: () => "senddata_test",
  });

  const result = await service.record(
    "payload",
    { request_id: "request-1", connection_id: "connection-1", joined_vrcode: "VR_A" },
    { bytes: 7 }
  );

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.outcome, "spool_write_failed");
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.spool.writeFailures, 1);
  assert.strictEqual(snapshot.spool.lastFailure.message, "spool dependency crashed");
});

test("send_data ingress service rejects spool when limits are reached", async () => {
  const metricState = configuredMetrics({ maxPendingItems: 0, maxPendingBytes: 0, maxPayloadBytes: 1 });
  const service = createSendDataIngressService({
    config: { spool: spoolConfig({ maxPendingItems: 0, maxPendingBytes: 0, maxPayloadBytes: 1 }) },
    metrics: metricState,
    spoolStore: {
      append() {
        throw new Error("append should not be called");
      },
    },
  });

  const result = await service.record(
    "payload",
    { request_id: "request-1", connection_id: "connection-1", joined_vrcode: "VR_A" },
    { bytes: 7 }
  );

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.outcome, "rejected");
  assert.strictEqual(result.reason, "spool_full");
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.spool.rejectedEvents, 1);
  assert.strictEqual(snapshot.spool.status, "degraded");
  assert.strictEqual(snapshot.recorders[0].spool.rejectedEvents, 1);
});

function configuredMetrics(overrides = {}) {
  const metricState = createMetrics();
  configureSendDataSpool(metricState, spoolConfig(overrides));
  return metricState;
}

function spoolConfig(overrides = {}) {
  return {
    enabled: true,
    mode: "mirror_spool",
    storage: "redis_list",
    listKey: "vitalserver:recorder_ingress:send_data:pending",
    maxPendingItems: 100,
    maxPendingBytes: 1000,
    maxPayloadBytes: 100,
    ...overrides,
  };
}

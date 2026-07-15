"use strict";

const assert = require("assert");
const test = require("node:test");
const { createSendDataIngressService } = require("../../src/application/send-data-ingress-service");
const {
  configureSendDataRawArchive,
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
  const failures = [];
  const service = createSendDataIngressService({
    config: { spool: spoolConfig() },
    failureSink: { record: (event) => failures.push(event) },
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
  assert.strictEqual(failures.length, 1);
  assert.strictEqual(failures[0].kind, "send_data_spool_write_failed");
  assert.strictEqual(failures[0].reason, "spool_write_failed");
  assert.strictEqual(failures[0].vrcode, "VR_A");
  assert.strictEqual(failures[0].payloadBytes, 7);
  assert.strictEqual(failures[0].payloadSha256, "239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5");
});

test("send_data ingress service archives raw payload before durable spool", async () => {
  const metricState = configuredMetrics({}, rawArchiveConfig());
  const archived = [];
  const writes = [];
  const service = createSendDataIngressService({
    config: { spool: spoolConfig(), rawArchive: rawArchiveConfig() },
    metrics: metricState,
    rawArchive: {
      append(item) {
        archived.push(item);
        return { ok: true, archiveId: "send-data-raw.jsonl", path: "/tmp/send-data-raw.jsonl", offset: 0, endOffset: 321, bytes: 321 };
      },
    },
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
  assert.strictEqual(archived.length, 1);
  assert.strictEqual(writes.length, 1);
  assert.strictEqual(archived[0].id, writes[0].id);
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.rawArchive.persistedEvents, 1);
  assert.strictEqual(snapshot.rawArchive.persistedBytes, 7);
  assert.strictEqual(snapshot.rawArchive.writeFailures, 0);
  assert.strictEqual(snapshot.spool.spooledEvents, 1);
});

test("send_data ingress service stops hot path when raw archive write fails", async () => {
  const metricState = configuredMetrics({}, rawArchiveConfig());
  const failures = [];
  const service = createSendDataIngressService({
    config: { spool: spoolConfig(), rawArchive: rawArchiveConfig() },
    failureSink: { record: (event) => failures.push(event) },
    metrics: metricState,
    rawArchive: {
      append() {
        return { ok: false, reason: "raw_archive_write_failed", message: "disk full" };
      },
    },
    spoolStore: {
      append() {
        throw new Error("spool append should not be called");
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
  assert.strictEqual(result.outcome, "raw_archive_write_failed");
  assert.strictEqual(result.reason, "raw_archive_write_failed");
  assert.strictEqual(result.message, "disk full");
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.rawArchive.persistedEvents, 0);
  assert.strictEqual(snapshot.rawArchive.writeFailures, 1);
  assert.strictEqual(snapshot.rawArchive.status, "failed");
  assert.strictEqual(snapshot.rawArchive.lastFailure.reason, "raw_archive_write_failed");
  assert.strictEqual(snapshot.spool.acceptedEvents, 0);
  assert.strictEqual(snapshot.spool.spooledEvents, 0);
  assert.strictEqual(failures.length, 1);
  assert.strictEqual(failures[0].kind, "send_data_raw_archive_write_failed");
  assert.strictEqual(failures[0].reason, "raw_archive_write_failed");
  assert.strictEqual(failures[0].vrcode, "VR_A");
});

test("send_data ingress service reports spool queue full as backpressure", async () => {
  const metricState = configuredMetrics();
  const failures = [];
  const queueFull = new Error("redis command queue full length=50001");
  const service = createSendDataIngressService({
    config: { spool: spoolConfig() },
    failureSink: { record: (event) => failures.push(event) },
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
  assert.strictEqual(failures.length, 1);
  assert.strictEqual(failures[0].kind, "send_data_spool_rejected");
  assert.strictEqual(failures[0].reason, "spool_full");
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

function configuredMetrics(overrides = {}, rawArchive = { enabled: false, path: "" }) {
  const metricState = createMetrics();
  configureSendDataSpool(metricState, spoolConfig(overrides));
  configureSendDataRawArchive(metricState, rawArchive);
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

function rawArchiveConfig(overrides = {}) {
  return {
    enabled: true,
    path: "/tmp/send-data-raw.jsonl",
    ...overrides,
  };
}

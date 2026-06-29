"use strict";

const assert = require("assert");
const test = require("node:test");
const { createSendDataRawArchiveExportWorker } = require("../../src/application/send-data-raw-archive-export-worker");
const { configureSendDataRawArchive, createMetrics } = require("../../src/observability/metrics");

test("raw archive export worker uploads finalizable archive and checkpoints cursor", async () => {
  const metrics = metricsWithFinalizableArchive();
  const state = stateWithStableCursor();
  const requests = [];
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    executor: {
      async recover(request) {
        requests.push(request);
        return { ok: true, statusCode: 200, response: { upload: { successfulRequests: 1 } } };
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.state, "uploaded");
  assert.strictEqual(requests.length, 1);
  assert.strictEqual(requests[0].rawArchivePath, "/raw/send-data-raw.jsonl");
  assert.strictEqual(state.checkpoint.archiveCursor, 42);
  assert.strictEqual(state.activeJob, null);
  assert.strictEqual(state.history[0].state, "uploaded");
  assert.strictEqual(metrics.sendDataRawArchive.autoExport.status, "uploaded");
});

test("raw archive export worker persists retryable failure with next attempt", async () => {
  const metrics = metricsWithFinalizableArchive();
  const state = stateWithStableCursor();
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig({ maxAttempts: 2, retryDelayMs: 1000 }),
    metrics,
    jobStore: memoryJobStore(state),
    executor: {
      async recover() {
        return { ok: false, reason: "http_failed", message: "HTTP 503", statusCode: 503 };
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.state, "retryable_failed");
  assert.strictEqual(state.activeJob.state, "retryable_failed");
  assert.strictEqual(state.activeJob.attempts, 1);
  assert.strictEqual(state.activeJob.lastFailure.reason, "http_failed");
  assert.ok(state.activeJob.nextAttemptAt);
  assert.strictEqual(metrics.sendDataRawArchive.autoExport.status, "retryable_failed");
});

test("raw archive export worker waits for stable cursor before upload", async () => {
  const metrics = metricsWithFinalizableArchive();
  const state = emptyState();
  let calls = 0;
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    executor: {
      async recover() {
        calls += 1;
        return { ok: true, statusCode: 200, response: {} };
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.state, "inactive_candidate");
  assert.strictEqual(calls, 0);
  assert.strictEqual(state.lastObserved.archiveCursor, 42);
});

test("raw archive export worker uploads on shutdown without waiting for stable cursor", async () => {
  const metrics = metricsWithFinalizableArchive();
  const state = emptyState();
  const requests = [];
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    executor: {
      async recover(request) {
        requests.push(request);
        return { ok: true, statusCode: 200, response: { upload: { successfulRequests: 1 } } };
      },
    },
  });

  const result = await worker.runOnce({ trigger: "shutdown" });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.state, "uploaded");
  assert.strictEqual(requests.length, 1);
  assert.strictEqual(state.checkpoint.archiveCursor, 42);
});

test("raw archive export worker keeps shutdown archive pending when replay is not drained", async () => {
  const metrics = metricsWithFinalizableArchive();
  metrics.sendDataReplay.pendingItems = 1;
  const state = emptyState();
  let calls = 0;
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    executor: {
      async recover() {
        calls += 1;
        return { ok: true, statusCode: 200, response: {} };
      },
    },
  });

  const result = await worker.runOnce({ trigger: "shutdown" });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.state, "inactive_candidate");
  assert.strictEqual(calls, 0);
  assert.deepStrictEqual(metrics.sendDataRawArchive.autoExport.reasons, ["realtime_replay_not_drained"]);
});

function metricsWithFinalizableArchive() {
  const metrics = createMetrics();
  configureSendDataRawArchive(metrics, {
    enabled: true,
    path: "/raw/send-data-raw.jsonl",
    autoExport: { enabled: true },
  });
  metrics.sendDataRawArchive.persistedEvents = 10;
  metrics.sendDataRawArchive.lastArchivedAt = "2000-01-01T00:00:00.000Z";
  metrics.sendDataRawArchive.lastOffset = 42;
  metrics.recorders.set("VR-1", {
    activeConnections: 0,
    selectedIp: "127.0.0.1",
    ipSource: "remoteAddress",
    lastSeenAt: "2000-01-01T00:00:00.000Z",
    sendDataEventsObserved: 10,
    sendDataBytesObserved: 1000,
    lastSendDataObservedAt: "2000-01-01T00:00:00.000Z",
    redisIpSync: null,
  });
  return metrics;
}

function workerConfig(overrides = {}) {
  return {
    rawArchive: {
      autoExport: {
        enabled: true,
        quietWindowMs: 1,
        scanIntervalMs: 1,
        cursorStableMs: 1,
        retryDelayMs: 1,
        maxAttempts: 3,
        requestTimeoutMs: 1000,
        outputDir: "/exports",
        vitalserverUrl: "http://app",
        uploadEndpoint: "/upload",
        ...overrides,
      },
    },
  };
}

function stateWithStableCursor() {
  return {
    schemaVersion: 1,
    updatedAt: "2000-01-01T00:00:00.000Z",
    lastObserved: {
      archivePath: "/raw/send-data-raw.jsonl",
      archiveCursor: 42,
      observedAt: "2000-01-01T00:00:00.000Z",
    },
    checkpoint: null,
    activeJob: null,
    history: [],
  };
}

function emptyState() {
  return {
    schemaVersion: 1,
    updatedAt: "1970-01-01T00:00:00.000Z",
    lastObserved: null,
    checkpoint: null,
    activeJob: null,
    history: [],
  };
}

function memoryJobStore(state) {
  return {
    read() {
      return state;
    },
    write(document) {
      Object.keys(state).forEach((key) => delete state[key]);
      Object.assign(state, document);
    },
  };
}

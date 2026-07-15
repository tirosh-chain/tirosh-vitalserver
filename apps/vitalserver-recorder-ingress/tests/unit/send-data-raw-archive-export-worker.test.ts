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
  assert.strictEqual(requests[0].vrcode, "VR-1");
  assert.strictEqual(requests[0].startOffset, 0);
  assert.strictEqual(requests[0].endOffset, 42);
  assert.strictEqual(state.checkpointsByVrcode["VR-1"].endOffset, 42);
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
  assert.strictEqual(state.observedByVrcode["VR-1"].endOffset, 42);
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
  assert.strictEqual(state.checkpointsByVrcode["VR-1"].endOffset, 42);
});

test("raw archive export worker keeps shutdown archive pending when replay is not drained", async () => {
  const metrics = metricsWithFinalizableArchive();
  metrics.recorders.get("VR-1").replay.pendingItems = 1;
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

test("raw archive export worker finalizes a disconnected recorder while another recorder stays connected", async () => {
  const metrics = metricsWithFinalizableArchive();
  metrics.recorders.set("VR-2", recorderMetrics({ activeConnections: 1, lastOffset: 84 }));
  metrics.activeRecorderConnections = 1;
  const requests = [];
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(stateWithStableCursor()),
    executor: {
      async recover(request) {
        requests.push(request);
        return { ok: true, statusCode: 200, response: { upload: { successfulRequests: 1 } } };
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.state, "uploaded");
  assert.strictEqual(requests[0].vrcode, "VR-1");
});

test("raw archive export worker persists explicit Lab finalization before upload", async () => {
  const metrics = metricsWithFinalizableArchive();
  metrics.recorders.get("VR-1").lastSendDataObservedAt = new Date().toISOString();
  metrics.recorders.get("VR-1").rawArchive.lastArchivedAt = new Date().toISOString();
  const state = emptyState();
  const requests = [];
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig({ quietWindowMs: 300000, cursorStableMs: 60000 }),
    metrics,
    jobStore: memoryJobStore(state),
    executor: {
      async recover(request) {
        requests.push(request);
        return { ok: true, statusCode: 200, response: { upload: { successfulRequests: 1 } } };
      },
    },
  });

  const accepted = await worker.requestFinalization({
    vrcodes: ["VR-1"],
    reason: "lab_session_stopped",
  });

  assert.strictEqual(accepted.state, "accepted");
  assert.strictEqual(requests.length, 1);
  assert.strictEqual(requests[0].vrcode, "VR-1");
  assert.strictEqual(state.pendingFinalizations.length, 0);
  assert.strictEqual(state.history[0].trigger, "explicit");
});

test("raw archive export worker processes every ready recorder in one Lab stop request", async () => {
  const metrics = metricsWithFinalizableArchive();
  metrics.recorders.set("VR-2", recorderMetrics({ lastOffset: 84 }));
  const recovered = [];
  const state = emptyState();
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    executor: {
      async recover(request) {
        recovered.push(request.vrcode);
        return { ok: true, statusCode: 200, response: { upload: { successfulRequests: 1 } } };
      },
    },
  });

  const accepted = await worker.requestFinalization({
    vrcodes: ["VR-1", "VR-2"],
    reason: "lab_session_stopped",
  });

  assert.strictEqual(accepted.state, "accepted");
  assert.deepStrictEqual(recovered, ["VR-1", "VR-2"]);
  assert.deepStrictEqual(state.pendingFinalizations, []);
  assert.strictEqual(state.checkpointsByVrcode["VR-1"].endOffset, 42);
  assert.strictEqual(state.checkpointsByVrcode["VR-2"].endOffset, 84);
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
  metrics.recorders.set("VR-1", recorderMetrics());
  return metrics;
}

function recorderMetrics(overrides: { activeConnections?: number; lastOffset?: number } = {}) {
  return {
    activeConnections: overrides.activeConnections || 0,
    selectedIp: "127.0.0.1",
    ipSource: "remoteAddress",
    lastSeenAt: "2000-01-01T00:00:00.000Z",
    sendDataEventsObserved: 10,
    sendDataBytesObserved: 1000,
    lastSendDataObservedAt: "2000-01-01T00:00:00.000Z",
    redisIpSync: null,
    rawArchive: {
      persistedEvents: 10,
      persistedBytes: 1000,
      lastArchivedAt: "2000-01-01T00:00:00.000Z",
      lastArchiveId: "send-data-raw.jsonl",
      lastOffset: overrides.lastOffset || 42,
    },
    spool: { pendingItems: 0 },
    replay: { pendingItems: 0, inFlightItems: 0 },
  };
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
    schemaVersion: 2,
    updatedAt: "2000-01-01T00:00:00.000Z",
    observedByVrcode: {
      "VR-1": {
        vrcode: "VR-1",
        archivePath: "/raw/send-data-raw.jsonl",
        endOffset: 42,
        observedAt: "2000-01-01T00:00:00.000Z",
      },
    },
    checkpointsByVrcode: {},
    pendingFinalizations: [],
    activeJob: null,
    history: [],
  };
}

function emptyState() {
  return {
    schemaVersion: 2,
    updatedAt: "1970-01-01T00:00:00.000Z",
    observedByVrcode: {},
    checkpointsByVrcode: {},
    pendingFinalizations: [],
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

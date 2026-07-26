"use strict";

const assert = require("assert");
const test = require("node:test");
const { createSendDataRawArchiveExportWorker } = require("../../src/application/send-data-raw-archive-export-worker");
const { configureSendDataRawArchive, createMetrics } = require("../../src/observability/metrics");

test("raw archive export worker exports finalizable archive and checkpoints cursor", async () => {
  const metrics = metricsWithFinalizableArchive();
  const state = stateWithStableCursor();
  const requests = [];
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    exporter: {
      async export(request) {
        requests.push(request);
        return successfulExport();
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.state, "exported");
  assert.strictEqual(requests.length, 1);
  assert.strictEqual(requests[0].rawArchivePath, "/raw/send-data-raw.jsonl");
  assert.strictEqual(requests[0].vrcode, "VR-1");
  assert.strictEqual(requests[0].startOffset, 0);
  assert.strictEqual(requests[0].endOffset, 42);
  assert.strictEqual(state.checkpointsByVrcode["VR-1"].endOffset, 42);
  assert.strictEqual(state.activeJob, null);
  assert.strictEqual(state.history[0].state, "exported");
  assert.strictEqual(state.history[0].publishState, "notRequested");
  assert.strictEqual(state.history[0].artifacts[0].origin, "coldPathRecovery");
  assert.strictEqual(metrics.sendDataRawArchive.autoExport.status, "exported");
});

test("raw archive export worker persists retryable failure with next attempt", async () => {
  const metrics = metricsWithFinalizableArchive();
  const state = stateWithStableCursor();
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig({ maxAttempts: 2, retryDelayMs: 1000 }),
    metrics,
    jobStore: memoryJobStore(state),
    exporter: {
      async export() {
        return { ok: false, reason: "http_failed", message: "HTTP 503", statusCode: 503 };
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.state, "export_retryable_failed");
  assert.strictEqual(state.activeJob.state, "export_retryable_failed");
  assert.strictEqual(state.activeJob.attempts, 1);
  assert.strictEqual(state.activeJob.lastFailure.reason, "http_failed");
  assert.ok(state.activeJob.nextAttemptAt);
  assert.strictEqual(metrics.sendDataRawArchive.autoExport.status, "export_retryable_failed");
});

test("raw archive export worker waits for stable cursor before export", async () => {
  const metrics = metricsWithFinalizableArchive();
  const state = emptyState();
  let calls = 0;
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    exporter: {
      async export() {
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

test("raw archive export worker exports on shutdown without waiting for stable cursor", async () => {
  const metrics = metricsWithFinalizableArchive();
  const state = emptyState();
  const requests = [];
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    exporter: {
      async export(request) {
        requests.push(request);
        return successfulExport();
      },
    },
  });

  const result = await worker.runOnce({ trigger: "shutdown" });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.state, "exported");
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
    exporter: {
      async export() {
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
    exporter: {
      async export(request) {
        requests.push(request);
        return successfulExport();
      },
    },
  });

  const result = await worker.runOnce();

  assert.strictEqual(result.state, "exported");
  assert.strictEqual(requests[0].vrcode, "VR-1");
});

test("raw archive export worker persists explicit Lab finalization before asynchronous export", async () => {
  const metrics = metricsWithFinalizableArchive();
  metrics.recorders.get("VR-1").lastSendDataObservedAt = new Date().toISOString();
  metrics.recorders.get("VR-1").rawArchive.lastArchivedAt = new Date().toISOString();
  const state = emptyState();
  const requests = [];
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig({ quietWindowMs: 300000, cursorStableMs: 60000 }),
    metrics,
    jobStore: memoryJobStore(state),
    exporter: {
      async export(request) {
        requests.push(request);
        return successfulExport();
      },
    },
  });

  const accepted = await worker.requestFinalization({
    vrcodes: ["VR-1"],
    reason: "lab_session_finished",
  });

  assert.strictEqual(accepted.state, "accepted");
  await waitFor(() => requests.length === 1);
  assert.strictEqual(requests[0].vrcode, "VR-1");
  await waitFor(() => state.history.length === 1);
  assert.strictEqual(state.pendingFinalizations.length, 0);
  assert.strictEqual(state.history[0].trigger, "explicit");
});

test("raw archive export worker processes every ready recorder in one Lab finish request", async () => {
  const metrics = metricsWithFinalizableArchive();
  metrics.recorders.set("VR-2", recorderMetrics({ lastOffset: 84 }));
  const exported = [];
  const state = emptyState();
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    exporter: {
      async export(request) {
        exported.push(request.vrcode);
        return successfulExport(request.vrcode);
      },
    },
  });

  const accepted = await worker.requestFinalization({
    vrcodes: ["VR-1", "VR-2"],
    reason: "lab_session_finished",
  });

  assert.strictEqual(accepted.state, "accepted");
  await waitFor(() => exported.length === 2);
  assert.deepStrictEqual(exported, ["VR-1", "VR-2"]);
  assert.deepStrictEqual(state.pendingFinalizations, []);
  assert.strictEqual(state.checkpointsByVrcode["VR-1"].endOffset, 42);
  assert.strictEqual(state.checkpointsByVrcode["VR-2"].endOffset, 84);
});

test("raw archive export worker reports owner-side progress without waiting for export", async () => {
  const metrics = metricsWithFinalizableArchive();
  const state = emptyState();
  let completeExport;
  const exportStarted = new Promise((resolve) => {
    completeExport = resolve;
  });
  const worker = createSendDataRawArchiveExportWorker({
    config: workerConfig(),
    metrics,
    jobStore: memoryJobStore(state),
    exporter: {
      async export() {
        await exportStarted;
        return successfulExport();
      },
    },
  });

  const accepted = await worker.requestFinalization({
    vrcodes: ["VR-1"],
    reason: "lab_session_finished",
  });

  assert.strictEqual(accepted.state, "accepted");
  const requestId = accepted.requestIds[0];
  const initial = worker.finalizationStatus([requestId]);
  assert.strictEqual(initial.state, "loaded");
  assert.ok(["queued", "processing"].includes(initial.finalization.state));
  await waitFor(() => state.activeJob && state.activeJob.state === "exporting");
  const processing = worker.finalizationStatus([requestId]);
  assert.strictEqual(processing.finalization.state, "processing");
  assert.strictEqual(processing.finalization.requests[0].state, "processing");

  completeExport();
  await waitFor(() => state.history.length === 1);
  assert.strictEqual(state.history[0].requestId, requestId);
  assert.strictEqual(state.checkpointsByVrcode["VR-1"].requestId, requestId);

  const exported = worker.finalizationStatus([requestId]);
  assert.strictEqual(exported.finalization.state, "exported");
  assert.strictEqual(exported.finalization.requests[0].state, "exported");
  assert.strictEqual(exported.finalization.requests[0].attempts, 1);
});

function successfulExport(vrcode = "VR-1") {
  const artifact = {
    artifactId: "a".repeat(64),
    origin: "coldPathRecovery",
    producer: "vitalserver-recorder-recovery",
    writerVersion: "1",
    vrcode,
    roomNames: ["OR-A"],
    sourceArchiveId: "/raw/send-data-raw.jsonl",
    sourceStartOffset: 0,
    sourceEndOffset: 42,
    coverageStartedAt: 1,
    coverageEndedAt: 2,
    formatVersion: 3,
    sha256: "b".repeat(64),
    filename: `${vrcode}_260101_000000.vital`,
    sizeBytes: 10,
    createdAt: 3,
    trackCount: 1,
  };
  const response = { operation: "export", artifacts: [artifact] };
  return { ok: true, statusCode: 200, artifacts: [artifact], response };
}

async function waitFor(predicate) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
  assert.fail("timed out waiting for asynchronous worker state");
}

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
        ...overrides,
      },
    },
  };
}

function stateWithStableCursor() {
  return {
    schemaVersion: 3,
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
    schemaVersion: 3,
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

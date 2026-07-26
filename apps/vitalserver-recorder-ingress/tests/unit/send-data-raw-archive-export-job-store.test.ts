"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const { createSendDataRawArchiveExportJobStore } = require("../../src/adapters/outbound/file/send-data-raw-archive-export-job-store");

test("raw archive export state migrates idle schema version 1 explicitly", () => {
  const statePath = temporaryStatePath();
  fs.writeFileSync(statePath, JSON.stringify({
    schemaVersion: 1,
    updatedAt: "2026-01-01T00:00:00.000Z",
    lastObserved: null,
    checkpoint: null,
    activeJob: null,
    history: [],
  }));
  const store = createStore(statePath);

  const state = store.read();

  assert.strictEqual(state.schemaVersion, 3);
  assert.deepStrictEqual(state.observedByVrcode, {});
  assert.deepStrictEqual(state.checkpointsByVrcode, {});
  assert.deepStrictEqual(state.pendingFinalizations, []);
});

test("raw archive export state rejects incomplete schema version 2 migration input", () => {
  const statePath = temporaryStatePath();
  fs.writeFileSync(statePath, JSON.stringify({ schemaVersion: 2 }));
  const store = createStore(statePath);

  assert.throws(() => store.read(), /requires string updatedAt/);
});

test("raw archive export state migrates completed schema version 2 as published legacy evidence", () => {
  const statePath = temporaryStatePath();
  fs.writeFileSync(statePath, JSON.stringify({
    schemaVersion: 2,
    updatedAt: "2026-07-01T00:00:00.000Z",
    observedByVrcode: {},
    checkpointsByVrcode: {
      "VR-A": {
        vrcode: "VR-A",
        archivePath: "/raw/archive.jsonl",
        endOffset: 42,
        jobId: "job-a",
        requestId: null,
        completedAt: "2026-07-01T00:00:00.000Z",
      },
    },
    pendingFinalizations: [],
    activeJob: null,
    history: [{
      schemaVersion: 2,
      jobId: "job-a",
      requestId: null,
      trigger: "inactivity",
      vrcode: "VR-A",
      archivePath: "/raw/archive.jsonl",
      startOffset: 0,
      endOffset: 42,
      state: "uploaded",
      attempts: 1,
      maxAttempts: 3,
      createdAt: "2026-07-01T00:00:00.000Z",
      updatedAt: "2026-07-01T00:00:00.000Z",
      startedAt: "2026-07-01T00:00:00.000Z",
      completedAt: "2026-07-01T00:00:00.000Z",
      nextAttemptAt: null,
      lastFailure: null,
      result: { upload: { successfulRequests: 1 } },
    }],
  }));

  const state = createStore(statePath).read();

  assert.strictEqual(state.schemaVersion, 3);
  assert.strictEqual(state.history[0].origin, "coldPathRecovery");
  assert.strictEqual(state.history[0].state, "exported");
  assert.strictEqual(state.history[0].publishState, "published");
  assert.deepStrictEqual(state.history[0].artifacts, []);
  assert.strictEqual(state.checkpointsByVrcode["VR-A"].publishState, "published");
  assert.deepStrictEqual(state.checkpointsByVrcode["VR-A"].artifactIds, []);
});

test("raw archive export state preserves unknown legacy failure stage", () => {
  const statePath = temporaryStatePath();
  fs.writeFileSync(statePath, JSON.stringify({
    schemaVersion: 2,
    updatedAt: "2026-07-01T00:00:00.000Z",
    observedByVrcode: {},
    checkpointsByVrcode: {},
    pendingFinalizations: [],
    activeJob: {
      schemaVersion: 2,
      jobId: "job-failed",
      requestId: null,
      trigger: "shutdown",
      vrcode: "VR-A",
      archivePath: "/raw/archive.jsonl",
      startOffset: 0,
      endOffset: 42,
      state: "failed",
      attempts: 3,
      maxAttempts: 3,
      createdAt: "2026-07-01T00:00:00.000Z",
      updatedAt: "2026-07-01T00:00:01.000Z",
      startedAt: "2026-07-01T00:00:00.000Z",
      completedAt: "2026-07-01T00:00:01.000Z",
      nextAttemptAt: null,
      lastFailure: {
        reason: "request_failed",
        message: "unknown old boundary",
        occurredAt: "2026-07-01T00:00:01.000Z",
      },
      result: null,
    },
    history: [],
  }));

  const state = createStore(statePath).read();

  assert.strictEqual(state.activeJob.state, "export_failed");
  assert.strictEqual(state.activeJob.publishState, "unknownLegacy");
  assert.strictEqual(state.activeJob.lastFailure.stage, "unknownLegacyStage");
});

function createStore(statePath) {
  return createSendDataRawArchiveExportJobStore({
    rawArchive: { autoExport: { enabled: true, statePath } },
  });
}

function temporaryStatePath() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "raw-export-state-"));
  return path.join(directory, "state.json");
}

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

  assert.strictEqual(state.schemaVersion, 2);
  assert.deepStrictEqual(state.observedByVrcode, {});
  assert.deepStrictEqual(state.checkpointsByVrcode, {});
  assert.deepStrictEqual(state.pendingFinalizations, []);
});

test("raw archive export state rejects incomplete schema version 2", () => {
  const statePath = temporaryStatePath();
  fs.writeFileSync(statePath, JSON.stringify({ schemaVersion: 2 }));
  const store = createStore(statePath);

  assert.throws(() => store.read(), /requires string updatedAt/);
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

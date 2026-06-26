"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const { createRuntimeStateMemoryGuardReader } = require("../../src/adapters/outbound/file/runtime-state-memory-guard-reader");

test("runtime state memory guard reader reports loaded VitalServer memory", async () => {
  const file = runtimeStateFile();
  fs.writeFileSync(file, JSON.stringify({
    updatedAt: new Date().toISOString(),
    containerServices: [
      {
        service: "app",
        memoryUsedBytes: 512,
        memoryLimitBytes: 1024,
      },
    ],
  }));

  const result = await createRuntimeStateMemoryGuardReader({ runtimeStatePath: file, maxAgeMs: 60000 }).read();

  assert.strictEqual(result.status, "loaded");
  assert.strictEqual(result.vitalServer.memoryUsedBytes, 512);
  assert.strictEqual(result.vitalServer.memoryLimitBytes, 1024);
  assert.strictEqual(result.vitalServer.usageRatio, 0.5);
});

test("runtime state memory guard reader preserves explicit zero VitalServer memory usage", async () => {
  const file = runtimeStateFile();
  fs.writeFileSync(file, JSON.stringify({
    updatedAt: new Date().toISOString(),
    containerServices: [
      {
        service: "app",
        memoryUsedBytes: 0,
        memoryLimitBytes: 1024,
      },
    ],
  }));

  const result = await createRuntimeStateMemoryGuardReader({ runtimeStatePath: file, maxAgeMs: 60000 }).read();

  assert.strictEqual(result.status, "loaded");
  assert.strictEqual(result.vitalServer.memoryUsedBytes, 0);
  assert.strictEqual(result.vitalServer.memoryLimitBytes, 1024);
  assert.strictEqual(result.vitalServer.usageRatio, 0);
});

test("runtime state memory guard reader preserves missing and stale states", async () => {
  const missing = await createRuntimeStateMemoryGuardReader({
    runtimeStatePath: path.join(os.tmpdir(), "missing-runtime-state.json"),
  }).read();
  assert.strictEqual(missing.status, "missing");

  const file = runtimeStateFile();
  fs.writeFileSync(file, JSON.stringify({
    updatedAt: "2026-01-01T00:00:00.000Z",
    containerServices: [
      {
        service: "app",
        memoryUsedBytes: 512,
        memoryLimitBytes: 1024,
      },
    ],
  }));

  const stale = await createRuntimeStateMemoryGuardReader({ runtimeStatePath: file, maxAgeMs: 1 }).read();

  assert.strictEqual(stale.status, "stale");
});

test("runtime state memory guard reader does not infer missing VitalServer memory limit", async () => {
  const file = runtimeStateFile();
  fs.writeFileSync(file, JSON.stringify({
    updatedAt: new Date().toISOString(),
    containerServices: [
      {
        service: "app",
        memoryUsedBytes: 512,
        memoryLimitBytes: null,
      },
    ],
  }));

  const result = await createRuntimeStateMemoryGuardReader({ runtimeStatePath: file, maxAgeMs: 60000 }).read();

  assert.strictEqual(result.status, "unavailable");
  assert.match(result.message, /missing app memory usage/);
});

function runtimeStateFile() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "recorder-ingress-memory-guard-"));
  return path.join(dir, "runtime-state.json");
}

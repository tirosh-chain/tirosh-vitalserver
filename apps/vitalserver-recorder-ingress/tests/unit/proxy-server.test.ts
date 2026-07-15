"use strict";

const assert = require("assert");
const test = require("node:test");
const { createRecorderIngressHttpServer } = require("../../src/adapters/inbound/http/proxy-server");
const { createMetrics } = require("../../src/observability/metrics");

test("recorder ingress HTTP adapter starts and stops injected workers on server lifecycle", () => {
  const calls = [];
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    sendDataRawArchiveExportWorker: {
      start() {
        calls.push("raw-start");
      },
      stop() {
        calls.push("raw-stop");
      },
      async runOnce() {
        return { ok: true, state: "disabled", disabled: true };
      },
      async requestFinalization() {
        return { ok: true, state: "accepted", requestIds: ["request-1"] };
      },
    },
    sendDataReplayWorker: {
      start() {
        calls.push("replay-start");
      },
      stop() {
        calls.push("replay-stop");
      },
      async runOnce() {
        return { ok: true, processed: 0, disabled: true };
      },
    },
    socketIoAudit: {
      inspect() {},
      inspectBinary() {},
    },
  });

  server.emit("listening");
  server.emit("close");

  assert.deepStrictEqual(calls, ["replay-start", "raw-start", "replay-stop", "raw-stop"]);
});

test("recorder ingress HTTP adapter runs shutdown raw archive export trigger", async () => {
  const calls = [];
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    sendDataRawArchiveExportWorker: {
      start() {
        calls.push("raw-start");
      },
      stop() {
        calls.push("raw-stop");
      },
      async runOnce(options) {
        calls.push(`raw-run:${options && options.trigger}`);
        return { ok: true, state: "uploaded" };
      },
      async requestFinalization() {
        return { ok: true, state: "accepted", requestIds: ["request-1"] };
      },
    },
    sendDataReplayWorker: {
      start() {
        calls.push("replay-start");
      },
      stop() {
        calls.push("replay-stop");
      },
      async runOnce() {
        return { ok: true, processed: 0, disabled: true };
      },
    },
    socketIoAudit: {
      inspect() {},
      inspectBinary() {},
    },
  });

  const result = await server.prepareShutdown();

  assert.deepStrictEqual(result, { ok: true, state: "uploaded" });
  assert.deepStrictEqual(calls, ["replay-stop", "raw-stop", "raw-run:shutdown"]);
});

test("recorder ingress accepts explicit recorder archive finalization", async () => {
  const calls = [];
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    sendDataRawArchiveExportWorker: {
      start() {},
      stop() {},
      async runOnce() { return { ok: true, state: "open" }; },
      async requestFinalization(input) {
        calls.push(input);
        return { ok: true, state: "accepted", requestIds: ["request-1"] };
      },
    },
    sendDataReplayWorker: {
      start() {},
      stop() {},
      async runOnce() { return { ok: true, processed: 0 }; },
    },
    socketIoAudit: { inspect() {}, inspectBinary() {} },
  });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  const response = await fetch(`http://127.0.0.1:${address.port}/recorder-ingress/raw-archive/finalize`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ vrcodes: ["LAB-VR-1"], reason: "lab_session_finished" }),
  });
  const body = await response.json();
  await new Promise((resolve) => server.close(resolve));

  assert.strictEqual(response.status, 202);
  assert.deepStrictEqual(body, { ok: true, state: "accepted", requestIds: ["request-1"] });
  assert.deepStrictEqual(calls, [{ vrcodes: ["LAB-VR-1"], reason: "lab_session_finished" }]);
});

function httpAdapterConfig() {
  return {
    upstream: { host: "127.0.0.1", port: 1, timeoutMs: 1000 },
    audit: { maxBodyBytes: 1024 },
    spool: { mode: "mirror_spool" },
  };
}

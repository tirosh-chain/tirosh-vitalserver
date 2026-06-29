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

function httpAdapterConfig() {
  return {
    upstream: { host: "127.0.0.1", port: 1, timeoutMs: 1000 },
    audit: { maxBodyBytes: 1024 },
    spool: { mode: "mirror_spool" },
  };
}

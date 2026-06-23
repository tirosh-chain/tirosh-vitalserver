"use strict";

const assert = require("assert");
const test = require("node:test");
const { createRecorderIngressHttpServer } = require("../../src/adapters/inbound/http/proxy-server");
const { createMetrics } = require("../../src/observability/metrics");

test("recorder ingress HTTP adapter starts and stops injected replay worker on server lifecycle", () => {
  const calls = [];
  const server = createRecorderIngressHttpServer({
    audit: { record() {} },
    clientIp: { select() { return { selected_ip: "127.0.0.1" }; } },
    config: httpAdapterConfig(),
    metrics: createMetrics(),
    sendDataReplayWorker: {
      start() {
        calls.push("start");
      },
      stop() {
        calls.push("stop");
      },
    },
    socketIoAudit: {
      inspect() {},
      inspectBinary() {},
    },
  });

  server.emit("listening");
  server.emit("close");

  assert.deepStrictEqual(calls, ["start", "stop"]);
});

function httpAdapterConfig() {
  return {
    upstream: { host: "127.0.0.1", port: 1, timeoutMs: 1000 },
    audit: { maxBodyBytes: 1024 },
    spool: { mode: "mirror_spool" },
  };
}

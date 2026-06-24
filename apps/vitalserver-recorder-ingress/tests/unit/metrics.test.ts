"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  createMetrics,
  metricsSnapshot,
  recordSendDataObserved,
  recordSendDataReplaySucceeded,
  recordSendDataSpoolSpooled,
} = require("../../src/observability/metrics");

test("metrics snapshot reports send_data throughput in bytes per second", () => {
  const metrics = createMetrics();

  recordSendDataObserved(metrics, "VR_1", { bytes: 1000 });
  recordSendDataSpoolSpooled(metrics, "VR_1", 1000, 1);
  recordSendDataReplaySucceeded(metrics, "VR_1", {
    payloadBytes: 400,
    receivedAt: new Date().toISOString(),
  });

  const throughput = metricsSnapshot(metrics).throughput;

  assert.strictEqual(throughput.windowSeconds, 10);
  assert.strictEqual(throughput.observedBytesPerSecond, 100);
  assert.strictEqual(throughput.spooledBytesPerSecond, 100);
  assert.strictEqual(throughput.replayedBytesPerSecond, 40);
  assert.strictEqual(throughput.queueGrowthBytesPerSecond, 60);
});

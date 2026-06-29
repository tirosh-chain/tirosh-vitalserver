"use strict";

const assert = require("assert");
const test = require("node:test");
const { createVrIdentityStore } = require("../../src/adapters/outbound/redis/vr-identity-store");
const { metricsSnapshot } = require("../../src/observability/metrics");
const { metrics } = require("../helpers");

test("vr identity store records disabled policy without writing redis", () => {
  const metricState = metrics();
  const calls = [];
  const redis = {
    command(args) {
      calls.push(args);
    },
  };
  const store = createVrIdentityStore(redis, metricState);

  store.setRecorderIp("VR_A", "172.31.0.152", { enabled: false, verifyDelaysMs: [0] });

  assert.deepStrictEqual(calls, []);
  const sync = metricsSnapshot(metricState).recorders[0].redisIpSync;
  assert.strictEqual(sync.status, "disabled");
  assert.strictEqual(sync.redisKey, "ip_VR_A");
  assert.strictEqual(sync.selectedIp, "172.31.0.152");
});

test("vr identity store verifies redis ip after writing", async () => {
  const metricState = metrics();
  const calls = [];
  const redis = {
    command(args, callback) {
      calls.push(args);
      if (args[0] === "GET") {
        callback(null, "172.31.0.152");
        return;
      }
      callback(null, "OK");
    },
  };
  const store = createVrIdentityStore(redis, metricState);

  store.setRecorderIp("VR_A", "172.31.0.152", { enabled: true, verifyDelaysMs: [0] });
  await new Promise((resolve) => setTimeout(resolve, 5));

  assert.deepStrictEqual(calls, [
    ["SET", "ip_VR_A", "172.31.0.152"],
    ["GET", "ip_VR_A"],
  ]);
  const sync = metricsSnapshot(metricState).recorders[0].redisIpSync;
  assert.strictEqual(sync.status, "verified");
  assert.strictEqual(sync.redisValue, "172.31.0.152");
});

test("vr identity store preserves verify failure state", async () => {
  const metricState = metrics();
  const redis = {
    command(args, callback) {
      if (args[0] === "GET") {
        callback(new Error("redis read failed"));
        return;
      }
      callback(null, "OK");
    },
  };
  const store = createVrIdentityStore(redis, metricState);

  store.setRecorderIp("VR_A", "172.31.0.152", { enabled: true, verifyDelaysMs: [0] });
  await new Promise((resolve) => setTimeout(resolve, 5));

  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.redisIpVerifyFailures, 1);
  assert.strictEqual(snapshot.recorders[0].redisIpSync.status, "verify_failed");
  assert.strictEqual(snapshot.recorders[0].redisIpSync.lastFailure, "redis read failed");
});

test("vr identity store rewrites mismatch and records bounded failure", async () => {
  const metricState = metrics();
  const calls = [];
  const redis = {
    command(args, callback) {
      calls.push(args);
      if (args[0] === "GET") {
        callback(null, "172.18.0.4");
        return;
      }
      callback(null, "OK");
    },
  };
  const store = createVrIdentityStore(redis, metricState);

  store.setRecorderIp("VR_A", "172.31.0.152", { enabled: true, verifyDelaysMs: [0, 1] });
  await new Promise((resolve) => setTimeout(resolve, 10));

  assert.deepStrictEqual(calls, [
    ["SET", "ip_VR_A", "172.31.0.152"],
    ["GET", "ip_VR_A"],
    ["SET", "ip_VR_A", "172.31.0.152"],
    ["GET", "ip_VR_A"],
    ["SET", "ip_VR_A", "172.31.0.152"],
  ]);
  const snapshot = metricsSnapshot(metricState);
  assert.strictEqual(snapshot.redisIpVerifyMismatches, 2);
  assert.strictEqual(snapshot.recorders[0].redisIpSync.status, "mismatch");
  assert.strictEqual(snapshot.recorders[0].redisIpSync.redisValue, "172.18.0.4");
});

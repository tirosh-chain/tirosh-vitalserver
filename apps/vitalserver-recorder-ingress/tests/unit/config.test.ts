"use strict";

const assert = require("assert");
const test = require("node:test");
const { loadConfig } = require("../../src/config");

test("config loads explicit redis ip rewrite policy", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_VR_IP_REWRITE_ENABLED: "0",
    RECORDER_INGRESS_VR_IP_VERIFY_DELAYS_MS: "10,250",
  }).vitalServer.ipRewrite, {
    enabled: false,
    verifyDelaysMs: [10, 250],
  });
});

test("config enables bounded spool and replay by default", () => {
  assert.deepStrictEqual(loadConfig({}).spool, {
    enabled: true,
    mode: "spool_and_replay",
    storage: "redis_list",
    listKey: "vitalserver:recorder_ingress:send_data:pending",
    inFlightListKey: "vitalserver:recorder_ingress:send_data:in_flight",
    replayedListKey: "vitalserver:recorder_ingress:send_data:replayed",
    deadLetterListKey: "vitalserver:recorder_ingress:send_data:dead_letter",
    maxPendingItems: 10000,
    maxPendingBytes: 512 * 1024 * 1024,
    maxPayloadBytes: 10 * 1024 * 1024,
    replay: {
      enabled: true,
      intervalMs: 1000,
      batchSize: 10,
      maxAttempts: 3,
      rateLimitPerSecond: 10,
      targetTimeoutMs: 5000,
    },
  });
});

test("config supports explicit send_data passthrough mode", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_SEND_DATA_MODE: "passthrough",
    RECORDER_INGRESS_SEND_DATA_REDIS_LIST: "custom:list",
    RECORDER_INGRESS_SEND_DATA_MAX_PENDING_ITEMS: "7",
    RECORDER_INGRESS_SEND_DATA_MAX_PENDING_BYTES: "11",
    RECORDER_INGRESS_SEND_DATA_MAX_PAYLOAD_BYTES: "13",
  }).spool, {
    enabled: false,
    mode: "passthrough",
    storage: "redis_list",
    listKey: "custom:list",
    inFlightListKey: "vitalserver:recorder_ingress:send_data:in_flight",
    replayedListKey: "vitalserver:recorder_ingress:send_data:replayed",
    deadLetterListKey: "vitalserver:recorder_ingress:send_data:dead_letter",
    maxPendingItems: 7,
    maxPendingBytes: 11,
    maxPayloadBytes: 13,
    replay: {
      enabled: false,
      intervalMs: 1000,
      batchSize: 10,
      maxAttempts: 3,
      rateLimitPerSecond: 10,
      targetTimeoutMs: 5000,
    },
  });
});

test("config enables send_data replay for spool_and_replay mode", () => {
  assert.deepStrictEqual(loadConfig({
    RECORDER_INGRESS_SEND_DATA_MODE: "spool_and_replay",
    RECORDER_INGRESS_SEND_DATA_IN_FLIGHT_REDIS_LIST: "custom:inflight",
    RECORDER_INGRESS_SEND_DATA_REPLAYED_REDIS_LIST: "custom:replayed",
    RECORDER_INGRESS_SEND_DATA_DEAD_LETTER_REDIS_LIST: "custom:dead",
    RECORDER_INGRESS_SEND_DATA_REPLAY_INTERVAL_MS: "250",
    RECORDER_INGRESS_SEND_DATA_REPLAY_BATCH_SIZE: "4",
    RECORDER_INGRESS_SEND_DATA_REPLAY_MAX_ATTEMPTS: "5",
    RECORDER_INGRESS_SEND_DATA_REPLAY_RATE_LIMIT_PER_SECOND: "2",
    RECORDER_INGRESS_SEND_DATA_REPLAY_TARGET_TIMEOUT_MS: "750",
  }).spool.replay, {
    enabled: true,
    intervalMs: 250,
    batchSize: 4,
    maxAttempts: 5,
    rateLimitPerSecond: 2,
    targetTimeoutMs: 750,
  });
  assert.strictEqual(loadConfig({
    RECORDER_INGRESS_SEND_DATA_MODE: "spool_and_replay",
    RECORDER_INGRESS_SEND_DATA_IN_FLIGHT_REDIS_LIST: "custom:inflight",
    RECORDER_INGRESS_SEND_DATA_REPLAYED_REDIS_LIST: "custom:replayed",
    RECORDER_INGRESS_SEND_DATA_DEAD_LETTER_REDIS_LIST: "custom:dead",
  }).spool.inFlightListKey, "custom:inflight");
});

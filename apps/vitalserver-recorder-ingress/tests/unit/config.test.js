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

test("config enables bounded mirror spool by default", () => {
  assert.deepStrictEqual(loadConfig({}).spool, {
    enabled: true,
    mode: "mirror_spool",
    storage: "redis_list",
    listKey: "vitalserver:recorder_ingress:send_data:pending",
    maxPendingItems: 10000,
    maxPendingBytes: 512 * 1024 * 1024,
    maxPayloadBytes: 10 * 1024 * 1024,
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
    maxPendingItems: 7,
    maxPendingBytes: 11,
    maxPayloadBytes: 13,
  });
});

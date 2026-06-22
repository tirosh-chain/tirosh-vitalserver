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

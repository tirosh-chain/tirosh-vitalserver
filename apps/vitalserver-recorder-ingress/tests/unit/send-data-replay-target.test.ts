"use strict";

const assert = require("assert");
const test = require("node:test");
const { payloadFromSpoolItem } = require("../../src/adapters/outbound/socketio/send-data-replay-target");

test("send_data replay target restores binary payload from spool item", () => {
  const result = payloadFromSpoolItem({
    payloadEncoding: "binary",
    payloadBase64: Buffer.from("payload").toString("base64"),
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(Buffer.isBuffer(result.value), true);
  assert.strictEqual(result.value.toString(), "payload");
});

test("send_data replay target restores binary-string payload from spool item", () => {
  const result = payloadFromSpoolItem({
    payloadEncoding: "string",
    payloadBase64: Buffer.from("payload", "binary").toString("base64"),
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.value, "payload");
});

test("send_data replay target rejects unsupported payload encoding", () => {
  const result = payloadFromSpoolItem({
    payloadEncoding: "json",
    payloadBase64: Buffer.from("payload").toString("base64"),
  });

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "invalid_payload");
  assert.match(result.message, /unsupported/);
});

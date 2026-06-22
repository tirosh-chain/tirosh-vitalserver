"use strict";

const assert = require("assert");
const test = require("node:test");
const { createSendDataSpoolItem } = require("../../src/domain/send-data-spool-item");

test("send_data spool item preserves opaque string payload", () => {
  const result = createSendDataSpoolItem(
    "payload",
    { request_id: "request-1", connection_id: "connection-1", joined_vrcode: "VR_CONTEXT" },
    { vrcode: "VR_PAYLOAD", bytes: 7 },
    { now: () => new Date("2026-06-22T09:00:00.000Z"), idFactory: () => "senddata_test" }
  );

  assert.strictEqual(result.ok, true);
  assert.deepStrictEqual(result.item, {
    schemaVersion: 1,
    id: "senddata_test",
    state: "pending",
    vrcode: "VR_PAYLOAD",
    connectionId: "connection-1",
    requestId: "request-1",
    receivedAt: "2026-06-22T09:00:00.000Z",
    payloadEncoding: "string",
    payloadBytes: 7,
    payloadBase64: Buffer.from("payload", "binary").toString("base64"),
    payloadSummary: { vrcode: "VR_PAYLOAD", bytes: 7 },
    attemptCount: 0,
    lastAttemptAt: null,
    lastFailure: null,
  });
});

test("send_data spool item falls back to joined recorder context", () => {
  const result = createSendDataSpoolItem(
    Buffer.from("payload"),
    { request_id: "request-1", connection_id: "connection-1", joined_vrcode: "VR_CONTEXT" },
    { bytes: 7 },
    { now: () => new Date("2026-06-22T09:00:00.000Z"), idFactory: () => "senddata_test" }
  );

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.item.vrcode, "VR_CONTEXT");
  assert.strictEqual(result.item.payloadEncoding, "binary");
  assert.strictEqual(result.item.payloadBase64, Buffer.from("payload").toString("base64"));
});

test("send_data spool item rejects payload without recorder identity", () => {
  const result = createSendDataSpoolItem("payload", { request_id: "request-1" }, { bytes: 7 });

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "invalid_payload");
  assert.match(result.message, /no vrcode/);
});

test("send_data spool item rejects non-byte payloads", () => {
  const result = createSendDataSpoolItem({ unexpected: true }, { joined_vrcode: "VR_A" }, {});

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "invalid_payload");
});

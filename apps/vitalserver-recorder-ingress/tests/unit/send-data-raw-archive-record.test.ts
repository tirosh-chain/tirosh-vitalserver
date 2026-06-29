"use strict";

const assert = require("assert");
const test = require("node:test");
const { createSendDataRawArchiveRecord } = require("../../src/application/send-data-raw-archive-record");

test("send_data raw archive record preserves source payload contract", () => {
  const record = createSendDataRawArchiveRecord(spoolItem(), "2026-06-22T10:00:01.000Z");

  assert.deepStrictEqual(record, {
    schemaVersion: 1,
    kind: "send_data_raw_payload",
    archivedAt: "2026-06-22T10:00:01.000Z",
    itemId: "senddata_test",
    state: "pending",
    vrcode: "VR_A",
    connectionId: "connection-1",
    requestId: "request-1",
    receivedAt: "2026-06-22T10:00:00.000Z",
    payloadEncoding: "binary",
    payloadBytes: 7,
    payloadSha256: "239f59ed55e737c77147cf55ad0c1b030b6d7ee748a7426952f9b852d5a935e5",
    payloadBase64: Buffer.from("payload").toString("base64"),
    payloadSummary: { bytes: 7, vrcode: "VR_A" },
  });
});

function spoolItem() {
  return {
    schemaVersion: 1,
    id: "senddata_test",
    state: "pending",
    vrcode: "VR_A",
    connectionId: "connection-1",
    requestId: "request-1",
    receivedAt: "2026-06-22T10:00:00.000Z",
    payloadEncoding: "binary",
    payloadBytes: 7,
    payloadBase64: Buffer.from("payload").toString("base64"),
    payloadSummary: { bytes: 7, vrcode: "VR_A" },
    attemptCount: 0,
    lastAttemptAt: null,
    lastFailure: null,
  };
}

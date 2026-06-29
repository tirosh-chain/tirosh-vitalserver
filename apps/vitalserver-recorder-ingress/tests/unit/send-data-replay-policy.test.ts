"use strict";

const assert = require("assert");
const test = require("node:test");
const {
  beginSendDataReplayAttempt,
  completeSendDataReplayAttempt,
  deadLetterInvalidSendDataSpoolDocument,
} = require("../../src/domain/send-data-replay-policy");

test("send_data replay policy moves replayable pending item to in_flight", () => {
  const result = beginSendDataReplayAttempt(spoolItem({ state: "pending", attemptCount: 1 }), {
    now: () => new Date("2026-06-22T10:00:00.000Z"),
  });

  assert.strictEqual(result.ok, true);
  assert.strictEqual(result.item.state, "in_flight");
  assert.strictEqual(result.item.attemptCount, 2);
  assert.strictEqual(result.item.lastAttemptAt, "2026-06-22T10:00:00.000Z");
});

test("send_data replay policy rejects item without explicit replay payload", () => {
  const item = spoolItem();
  delete item.payloadBase64;

  const result = beginSendDataReplayAttempt(item);

  assert.strictEqual(result.ok, false);
  assert.strictEqual(result.reason, "invalid_payload");
  assert.match(result.message, /payloadBase64/);
});

test("send_data replay policy marks successful attempt as replayed", () => {
  const result = completeSendDataReplayAttempt(
    spoolItem({ state: "in_flight", attemptCount: 1 }),
    { ok: true },
    { maxAttempts: 3 },
    { now: () => new Date("2026-06-22T10:01:00.000Z") }
  );

  assert.strictEqual(result.action, "mark_replayed");
  assert.strictEqual(result.item.state, "replayed");
  assert.strictEqual(result.item.replayedAt, "2026-06-22T10:01:00.000Z");
  assert.strictEqual(result.item.lastFailure, null);
});

test("send_data replay policy keeps upstream failure retryable before max attempts", () => {
  const result = completeSendDataReplayAttempt(
    spoolItem({ state: "in_flight", attemptCount: 2 }),
    { ok: false, reason: "upstream_unavailable", message: "connect ECONNREFUSED" },
    { maxAttempts: 3 },
    { now: () => new Date("2026-06-22T10:02:00.000Z") }
  );

  assert.strictEqual(result.action, "requeue");
  assert.strictEqual(result.item.state, "retryable_failed");
  assert.deepStrictEqual(result.item.lastFailure, {
    reason: "upstream_unavailable",
    message: "connect ECONNREFUSED",
    occurredAt: "2026-06-22T10:02:00.000Z",
  });
});

test("send_data replay policy dead-letters failed item at max attempts", () => {
  const result = completeSendDataReplayAttempt(
    spoolItem({ state: "in_flight", attemptCount: 3 }),
    { ok: false, reason: "upstream_timeout", message: "timeout" },
    { maxAttempts: 3 },
    { now: () => new Date("2026-06-22T10:03:00.000Z") }
  );

  assert.strictEqual(result.action, "dead_letter");
  assert.strictEqual(result.item.state, "dead_lettered");
  assert.strictEqual(result.item.deadLetteredAt, "2026-06-22T10:03:00.000Z");
  assert.strictEqual(result.item.lastFailure.reason, "upstream_timeout");
});

test("send_data replay policy dead-letters invalid replay payload without retry", () => {
  const result = completeSendDataReplayAttempt(
    spoolItem({ state: "in_flight", attemptCount: 1 }),
    { ok: false, reason: "invalid_payload", message: "bad base64" },
    { maxAttempts: 3 },
    { now: () => new Date("2026-06-22T10:04:00.000Z") }
  );

  assert.strictEqual(result.action, "dead_letter");
  assert.strictEqual(result.item.state, "dead_lettered");
  assert.strictEqual(result.item.lastFailure.reason, "invalid_payload");
});

test("send_data replay policy creates explicit dead-letter document for invalid spool raw data", () => {
  const item = deadLetterInvalidSendDataSpoolDocument("{bad json", "invalid_payload", "decode failed", {
    now: () => new Date("2026-06-22T10:05:00.000Z"),
  });

  assert.strictEqual(item.state, "dead_lettered");
  assert.strictEqual(item.rawDocument, "{bad json");
  assert.strictEqual(item.lastFailure.reason, "invalid_payload");
  assert.strictEqual(item.deadLetteredAt, "2026-06-22T10:05:00.000Z");
});

function spoolItem(overrides = {}) {
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
    ...overrides,
  };
}

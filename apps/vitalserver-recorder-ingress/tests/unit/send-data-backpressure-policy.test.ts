"use strict";

const assert = require("assert");
const test = require("node:test");
const { evaluateSendDataBackpressure } = require("../../src/domain/send-data-backpressure-policy");

test("send_data backpressure accepts item within configured limits", () => {
  assert.deepStrictEqual(evaluateSendDataBackpressure(
    { enabled: true, maxPendingItems: 2, maxPendingBytes: 100, maxPayloadBytes: 50 },
    { pendingItems: 1, pendingBytes: 40 },
    { payloadBytes: 20 }
  ), {
    action: "accept",
  });
});

test("send_data backpressure rejects disabled spool", () => {
  assert.deepStrictEqual(evaluateSendDataBackpressure(
    { enabled: false, maxPendingItems: 2, maxPendingBytes: 100, maxPayloadBytes: 50 },
    { pendingItems: 0, pendingBytes: 0 },
    { payloadBytes: 20 }
  ), {
    action: "reject",
    reason: "spool_unavailable",
    message: "send_data spool is disabled",
  });
});

test("send_data backpressure rejects item limit", () => {
  assert.deepStrictEqual(evaluateSendDataBackpressure(
    { enabled: true, maxPendingItems: 2, maxPendingBytes: 100, maxPayloadBytes: 50 },
    { pendingItems: 2, pendingBytes: 40 },
    { payloadBytes: 20 }
  ), {
    action: "reject",
    reason: "spool_full",
    message: "send_data spool pending item limit reached",
  });
});

test("send_data backpressure rejects byte limit", () => {
  assert.deepStrictEqual(evaluateSendDataBackpressure(
    { enabled: true, maxPendingItems: 10, maxPendingBytes: 50, maxPayloadBytes: 50 },
    { pendingItems: 1, pendingBytes: 40 },
    { payloadBytes: 20 }
  ), {
    action: "reject",
    reason: "spool_full",
    message: "send_data spool pending byte limit reached",
  });
});

test("send_data backpressure rejects payload limit", () => {
  assert.deepStrictEqual(evaluateSendDataBackpressure(
    { enabled: true, maxPendingItems: 10, maxPendingBytes: 100, maxPayloadBytes: 10 },
    { pendingItems: 1, pendingBytes: 20 },
    { payloadBytes: 20 }
  ), {
    action: "reject",
    reason: "spool_full",
    message: "send_data payload exceeds spool payload limit",
  });
});

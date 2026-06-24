"use strict";

const assert = require("assert");
const test = require("node:test");
const { decideSendDataReplayRate } = require("../../src/domain/send-data-replay-rate-policy");

const MIB = 1024 * 1024;

test("adaptive replay rate decreases on explicit replay failures", () => {
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: 10 * MIB,
    currentMaxBytesPerSecond: 8 * MIB,
    adaptive: {
      enabled: true,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 10 * MIB,
    },
    pendingItems: 100,
    queueGrowthBytesPerSecond: 1024,
    replayFailures: 1,
  });

  assert.deepStrictEqual(decision, {
    maxBytesPerSecond: 4 * MIB,
    action: "decrease",
    reason: "replay_failures",
  });
});

test("adaptive replay rate increases while backlog grows without failures", () => {
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: 10 * MIB,
    currentMaxBytesPerSecond: 4 * MIB,
    adaptive: {
      enabled: true,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 10 * MIB,
    },
    pendingItems: 100,
    queueGrowthBytesPerSecond: 1024,
    replayFailures: 0,
  });

  assert.deepStrictEqual(decision, {
    maxBytesPerSecond: 5 * MIB,
    action: "increase",
    reason: "queue_growing",
  });
});

test("adaptive replay rate preserves fixed configured rate when disabled", () => {
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: 10 * MIB,
    currentMaxBytesPerSecond: 4 * MIB,
    adaptive: {
      enabled: false,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 10 * MIB,
    },
    pendingItems: 100,
    queueGrowthBytesPerSecond: 1024,
    replayFailures: 0,
  });

  assert.deepStrictEqual(decision, {
    maxBytesPerSecond: 10 * MIB,
    action: "fixed",
    reason: "adaptive_disabled",
  });
});

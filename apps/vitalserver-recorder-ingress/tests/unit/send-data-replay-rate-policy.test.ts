"use strict";

const assert = require("assert");
const test = require("node:test");
const { decideSendDataReplayRate } = require("../../src/domain/send-data-replay-rate-policy");

const MIB = 1024 * 1024;

test("adaptive replay rate decreases on explicit replay failures", () => {
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: 10 * MIB,
    currentMaxBytesPerSecond: 8 * MIB,
    currentItemsPerTick: 800,
    currentConcurrency: 8,
    adaptive: {
      enabled: true,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 10 * MIB,
      minItemsPerTick: 50,
      maxItemsPerTick: 1000,
      minConcurrency: 1,
      maxConcurrency: 8,
    },
    pendingItems: 100,
    queueGrowthBytesPerSecond: 1024,
    replayFailures: 1,
    memoryGuard: loadedMemoryGuard(0.4),
  });

  assert.deepStrictEqual(decision, {
    maxBytesPerSecond: 4 * MIB,
    itemsPerTick: 400,
    concurrency: 4,
    action: "decrease",
    reason: "replay_failures",
    memoryGuardStatus: "healthy",
  });
});

test("adaptive replay rate increases while backlog grows without failures", () => {
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: 10 * MIB,
    currentMaxBytesPerSecond: 4 * MIB,
    currentItemsPerTick: 500,
    currentConcurrency: 4,
    adaptive: {
      enabled: true,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 10 * MIB,
      minItemsPerTick: 50,
      maxItemsPerTick: 1000,
      minConcurrency: 1,
      maxConcurrency: 8,
    },
    pendingItems: 100,
    queueGrowthBytesPerSecond: 1024,
    replayFailures: 0,
    memoryGuard: loadedMemoryGuard(0.4),
  });

  assert.deepStrictEqual(decision, {
    maxBytesPerSecond: 5 * MIB,
    itemsPerTick: 600,
    concurrency: 5,
    action: "increase",
    reason: "queue_growing",
    memoryGuardStatus: "healthy",
  });
});

test("adaptive replay rate decreases under VitalServer memory pressure", () => {
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: 10 * MIB,
    currentMaxBytesPerSecond: 8 * MIB,
    currentItemsPerTick: 800,
    currentConcurrency: 8,
    adaptive: {
      enabled: true,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 10 * MIB,
      minItemsPerTick: 50,
      maxItemsPerTick: 1000,
      minConcurrency: 1,
      maxConcurrency: 8,
    },
    pendingItems: 100,
    queueGrowthBytesPerSecond: 1024,
    replayFailures: 0,
    memoryGuard: loadedMemoryGuard(0.84),
  });

  assert.deepStrictEqual(decision, {
    maxBytesPerSecond: 4 * MIB,
    itemsPerTick: 400,
    concurrency: 4,
    action: "decrease",
    reason: "memory_hot",
    memoryGuardStatus: "hot",
  });
});

test("adaptive replay rate drops to minimum under critical VitalServer memory pressure", () => {
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: 10 * MIB,
    currentMaxBytesPerSecond: 8 * MIB,
    currentItemsPerTick: 800,
    currentConcurrency: 8,
    adaptive: {
      enabled: true,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 10 * MIB,
      minItemsPerTick: 50,
      maxItemsPerTick: 1000,
      minConcurrency: 1,
      maxConcurrency: 8,
    },
    pendingItems: 100,
    queueGrowthBytesPerSecond: 1024,
    replayFailures: 0,
    memoryGuard: loadedMemoryGuard(0.92),
  });

  assert.deepStrictEqual(decision, {
    maxBytesPerSecond: 2 * MIB,
    itemsPerTick: 50,
    concurrency: 1,
    action: "decrease",
    reason: "memory_critical",
    memoryGuardStatus: "critical",
  });
});

test("adaptive replay rate uses conservative budget when memory guard is unavailable", () => {
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: 10 * MIB,
    currentMaxBytesPerSecond: 8 * MIB,
    currentItemsPerTick: 800,
    currentConcurrency: 8,
    adaptive: {
      enabled: true,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 10 * MIB,
      minItemsPerTick: 50,
      maxItemsPerTick: 1000,
      minConcurrency: 1,
      maxConcurrency: 8,
    },
    pendingItems: 100,
    queueGrowthBytesPerSecond: 1024,
    replayFailures: 0,
    memoryGuard: { status: "stale", message: "old state" },
  });

  assert.deepStrictEqual(decision, {
    maxBytesPerSecond: 2 * MIB,
    itemsPerTick: 50,
    concurrency: 1,
    action: "decrease",
    reason: "memory_guard_stale",
    memoryGuardStatus: "stale",
  });
});

test("adaptive replay rate preserves fixed configured rate when disabled", () => {
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: 10 * MIB,
    currentMaxBytesPerSecond: 4 * MIB,
    currentItemsPerTick: 500,
    currentConcurrency: 4,
    adaptive: {
      enabled: false,
      minBytesPerSecond: 2 * MIB,
      maxBytesPerSecond: 10 * MIB,
      minItemsPerTick: 50,
      maxItemsPerTick: 1000,
      minConcurrency: 1,
      maxConcurrency: 8,
    },
    pendingItems: 100,
    queueGrowthBytesPerSecond: 1024,
    replayFailures: 0,
    memoryGuard: loadedMemoryGuard(0.92),
  });

  assert.deepStrictEqual(decision, {
    maxBytesPerSecond: 10 * MIB,
    itemsPerTick: 500,
    concurrency: 4,
    action: "fixed",
    reason: "adaptive_disabled",
    memoryGuardStatus: "disabled",
  });
});

function loadedMemoryGuard(ratio) {
  return {
    status: "loaded",
    vitalServer: {
      memoryUsedBytes: Math.floor(ratio * 1000),
      memoryLimitBytes: 1000,
      usageRatio: ratio,
      observedAt: new Date().toISOString(),
    },
  };
}

"use strict";

const MIB = 1024 * 1024;
const DEFAULT_MIN_ITEMS_PER_TICK = 50;
const DEFAULT_MAX_ITEMS_PER_TICK = 1000;
const DEFAULT_MIN_CONCURRENCY = 1;
const DEFAULT_MAX_CONCURRENCY = 8;

function decideSendDataReplayRate(input) {
  const configuredRate = positiveInteger(input && input.configuredMaxBytesPerSecond, 1);
  const adaptive = (input && input.adaptive) || {};
  if (!adaptive.enabled) {
    return decision(
      configuredRate,
      fixedItemBudget(input, adaptive),
      fixedConcurrency(input, adaptive),
      "fixed",
      "adaptive_disabled",
      "disabled"
    );
  }

  const minRate = positiveInteger(adaptive.minBytesPerSecond, 1);
  const maxRate = Math.max(minRate, positiveInteger(adaptive.maxBytesPerSecond, configuredRate));
  const minItems = positiveInteger(adaptive.minItemsPerTick, DEFAULT_MIN_ITEMS_PER_TICK);
  const maxItems = Math.max(minItems, positiveInteger(adaptive.maxItemsPerTick, DEFAULT_MAX_ITEMS_PER_TICK));
  const minConcurrency = positiveInteger(adaptive.minConcurrency, DEFAULT_MIN_CONCURRENCY);
  const maxConcurrency = Math.max(minConcurrency, positiveInteger(adaptive.maxConcurrency, DEFAULT_MAX_CONCURRENCY));
  const currentRate = clamp(
    positiveInteger(input && input.currentMaxBytesPerSecond, configuredRate),
    minRate,
    maxRate
  );
  const currentItems = clamp(positiveInteger(input && input.currentItemsPerTick, maxItems), minItems, maxItems);
  const currentConcurrency = clamp(positiveInteger(input && input.currentConcurrency, maxConcurrency), minConcurrency, maxConcurrency);
  const failures = positiveInteger(input && input.replayFailures, 0);
  const pendingItems = positiveInteger(input && input.pendingItems, 0);
  const queueGrowthBytesPerSecond = finiteNumber(input && input.queueGrowthBytesPerSecond, 0);
  const memory = memoryGuard(input && input.memoryGuard);

  if (memory.status !== "loaded") {
    return decision(minRate, minItems, minConcurrency, "decrease", `memory_guard_${memory.status}`, memory.status);
  }

  if (failures > 0) {
    return decision(
      Math.max(minRate, Math.floor(currentRate / 2)),
      Math.max(minItems, Math.floor(currentItems / 2)),
      Math.max(minConcurrency, Math.floor(currentConcurrency / 2)),
      "decrease",
      "replay_failures",
      memory.pressure
    );
  }

  if (memory.pressure === "critical") {
    return decision(minRate, minItems, minConcurrency, "decrease", "memory_critical", memory.pressure);
  }

  if (memory.pressure === "hot") {
    return decision(
      Math.max(minRate, Math.floor(currentRate / 2)),
      Math.max(minItems, Math.floor(currentItems / 2)),
      Math.max(minConcurrency, Math.floor(currentConcurrency / 2)),
      "decrease",
      "memory_hot",
      memory.pressure
    );
  }

  if (memory.pressure === "warm") {
    return decision(
      currentRate,
      Math.min(currentItems, warmItemBudget(minItems, maxItems)),
      Math.min(currentConcurrency, warmConcurrency(minConcurrency, maxConcurrency)),
      "keep",
      "memory_warm",
      memory.pressure
    );
  }

  if (pendingItems > 0 && queueGrowthBytesPerSecond > 0) {
    return decision(
      Math.min(maxRate, currentRate + MIB),
      Math.min(maxItems, currentItems + Math.max(minItems, Math.floor(maxItems / 10))),
      Math.min(maxConcurrency, currentConcurrency + 1),
      "increase",
      "queue_growing",
      memory.pressure
    );
  }

  return decision(currentRate, currentItems, currentConcurrency, "keep", "steady", memory.pressure);
}

function decision(maxBytesPerSecond, itemsPerTick, concurrency, action, reason, memoryGuardStatus) {
  return {
    maxBytesPerSecond,
    itemsPerTick,
    concurrency,
    action,
    reason,
    memoryGuardStatus,
  };
}

function memoryGuard(read) {
  if (!read || read.status !== "loaded") {
    return { status: read && read.status ? read.status : "unavailable", pressure: "unavailable" };
  }
  const ratio = finiteNumber(read.vitalServer && read.vitalServer.usageRatio, 1);
  if (ratio >= 0.9) return { status: "loaded", pressure: "critical" };
  if (ratio >= 0.8) return { status: "loaded", pressure: "hot" };
  if (ratio >= 0.65) return { status: "loaded", pressure: "warm" };
  return { status: "loaded", pressure: "healthy" };
}

function fixedItemBudget(input, adaptive) {
  return positiveInteger(
    input && input.configuredItemsPerTick,
    positiveInteger(
      input && input.currentItemsPerTick,
      positiveInteger(adaptive.maxItemsPerTick, DEFAULT_MAX_ITEMS_PER_TICK)
    )
  );
}

function fixedConcurrency(input, adaptive) {
  return positiveInteger(
    input && input.configuredConcurrency,
    positiveInteger(
      input && input.currentConcurrency,
      positiveInteger(adaptive.maxConcurrency, DEFAULT_MAX_CONCURRENCY)
    )
  );
}

function warmItemBudget(minItems, maxItems) {
  return clamp(Math.floor(maxItems / 2), minItems, maxItems);
}

function warmConcurrency(minConcurrency, maxConcurrency) {
  return clamp(Math.ceil(maxConcurrency / 2), minConcurrency, maxConcurrency);
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function positiveInteger(value, fallback) {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

function finiteNumber(value, fallback) {
  return Number.isFinite(value) ? value : fallback;
}

module.exports = { decideSendDataReplayRate };

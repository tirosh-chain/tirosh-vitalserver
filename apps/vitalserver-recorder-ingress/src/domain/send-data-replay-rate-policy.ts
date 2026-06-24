"use strict";

const MIB = 1024 * 1024;

function decideSendDataReplayRate(input) {
  const configuredRate = positiveInteger(input && input.configuredMaxBytesPerSecond, 1);
  const adaptive = (input && input.adaptive) || {};
  if (!adaptive.enabled) {
    return decision(configuredRate, "fixed", "adaptive_disabled");
  }

  const minRate = positiveInteger(adaptive.minBytesPerSecond, 1);
  const maxRate = Math.max(minRate, positiveInteger(adaptive.maxBytesPerSecond, configuredRate));
  const currentRate = clamp(
    positiveInteger(input && input.currentMaxBytesPerSecond, configuredRate),
    minRate,
    maxRate
  );
  const failures = positiveInteger(input && input.replayFailures, 0);
  const pendingItems = positiveInteger(input && input.pendingItems, 0);
  const queueGrowthBytesPerSecond = finiteNumber(input && input.queueGrowthBytesPerSecond, 0);

  if (failures > 0) {
    return decision(
      Math.max(minRate, Math.floor(currentRate / 2)),
      "decrease",
      "replay_failures"
    );
  }

  if (pendingItems > 0 && queueGrowthBytesPerSecond > 0) {
    return decision(
      Math.min(maxRate, currentRate + MIB),
      "increase",
      "queue_growing"
    );
  }

  return decision(currentRate, "keep", "steady");
}

function decision(maxBytesPerSecond, action, reason) {
  return {
    maxBytesPerSecond,
    action,
    reason,
  };
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

import type {
  SendDataReplayWorkerPort,
  SendDataReplayWorkerRunResult,
} from "./ports/inbound/send-data-replay-worker-port";
import type { SendDataReplayTargetPort } from "./ports/outbound/send-data-replay-target-port";
import type { SendDataFailureSinkPort } from "./ports/outbound/send-data-failure-sink-port";
import type { MemoryGuardPort } from "./ports/outbound/memory-guard-port";
import type {
  SendDataSpoolReplayPort,
  SendDataSpoolStoreClaimResult,
  SendDataSpoolStoreWriteResult,
} from "./ports/outbound/send-data-spool-store-port";
import type {
  SendDataReplayConfig,
  SendDataSpoolConfig,
  SendDataSpoolItem,
} from "../domain/send-data-spool-types";

"use strict";

const {
  completeSendDataReplayAttempt,
  deadLetterInvalidSendDataSpoolDocument,
} = require("../domain/send-data-replay-policy");
const { decideSendDataReplayRate } = require("../domain/send-data-replay-rate-policy");
const { sendDataFailureReasons } = require("../domain/send-data-ingress-contracts");
const { recordSendDataFailure } = require("./send-data-failure-log");
const {
  metricsSnapshot,
  recordSendDataReplayClaimFailed,
  recordSendDataReplayDeadLettered,
  recordSendDataReplayQueueDrained,
  recordSendDataReplayRateDecision,
  recordSendDataReplayRetryableFailed,
  recordSendDataReplayStarted,
  recordSendDataReplaySucceeded,
  recordSendDataRealtimeSkipped,
  sendDataReplayRateState,
} = require("../observability/metrics");

type SendDataReplayWorkerDependencies = {
  config: SendDataSpoolConfig;
  failureSink?: SendDataFailureSinkPort;
  metrics: Record<string, unknown>;
  spoolStore: SendDataSpoolReplayPort;
  replayTarget: SendDataReplayTargetPort;
  memoryGuard?: MemoryGuardPort;
  timer?: Pick<typeof globalThis, "setInterval" | "clearInterval">;
};

function createSendDataReplayWorker({
  config,
  failureSink,
  memoryGuard,
  metrics,
  spoolStore,
  replayTarget,
  timer = globalThis,
}: SendDataReplayWorkerDependencies): SendDataReplayWorkerPort {
  let interval = null;
  let running = false;

  return {
    start() {
      if (!config.replay || !config.replay.enabled || interval) return;
      interval = timer.setInterval(() => {
        this.runOnce().catch((error) => {
          recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.UPSTREAM_UNAVAILABLE, error.message);
        });
      }, config.replay.intervalMs);
    },
    stop() {
      if (!interval) return;
      timer.clearInterval(interval);
      interval = null;
    },
    async runOnce() {
      if (!config.replay || !config.replay.enabled) return { ok: true, processed: 0, disabled: true };
      if (running) return { ok: false, processed: 0, reason: "already_running" };
      running = true;
      try {
        return await runReplayBatch({ config, failureSink, memoryGuard, metrics, spoolStore, replayTarget });
      } finally {
        running = false;
      }
    },
  };
}

async function runReplayBatch({
  config,
  failureSink,
  memoryGuard,
  metrics,
  spoolStore,
  replayTarget,
}: SendDataReplayWorkerDependencies): Promise<SendDataReplayWorkerRunResult> {
  const trimResult = await trimRealtimePending({ config, metrics, spoolStore });
  if (trimResult.ok === false) return trimResult;
  const replayRate = sendDataReplayRateState(metrics);
  const memoryGuardRead = await readMemoryGuard(memoryGuard);
  const snapshot = metricsSnapshot(metrics);
  const control = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: replayRate.configuredMaxBytesPerSecond || config.replay.maxBytesPerSecond,
    currentMaxBytesPerSecond: replayRate.currentMaxBytesPerSecond || config.replay.maxBytesPerSecond,
    currentItemsPerTick: replayRate.currentItemsPerTick || replayBatchLimit(config.replay),
    currentConcurrency: replayRate.currentConcurrency || replayConcurrencyLimit(config.replay),
    configuredItemsPerTick: replayBatchLimit(config.replay),
    configuredConcurrency: replayConcurrencyLimit(config.replay),
    adaptive: config.replay.adaptive,
    pendingItems: snapshot.replay ? snapshot.replay.pendingItems : 0,
    queueGrowthBytesPerSecond: snapshot.throughput ? snapshot.throughput.queueGrowthBytesPerSecond : 0,
    replayFailures: 0,
    memoryGuard: memoryGuardRead,
  });
  recordSendDataReplayRateDecision(metrics, control);
  const itemLimit = Math.max(1, control.itemsPerTick);
  const concurrency = Math.max(1, control.concurrency || 1);
  const byteBudget = replayByteBudget({
    ...config.replay,
    maxBytesPerSecond: control.maxBytesPerSecond,
  });
  let processed = 0;
  let attempts = 0;
  let processedBytes = 0;
  const signals = {
    replayFailures: 0,
  };

  let queueEmpty = false;

  while (!queueEmpty && attempts < itemLimit) {
    const batch = [];
    while (batch.length < concurrency && attempts < itemLimit) {
      if (attempts > 0 && processedBytes >= byteBudget) break;
      const claim = await spoolStore.claim();
      attempts += 1;
      if (!claim.ok) {
        await deadLetterInvalidClaim({ claim, failureSink, metrics, spoolStore });
        if (claim.reason === sendDataFailureReasons.INVALID_PAYLOAD) {
          processed += 1;
        } else {
          signals.replayFailures += 1;
          recordSendDataReplayClaimFailed(
            metrics,
            claim.reason || sendDataFailureReasons.SPOOL_UNAVAILABLE,
            claim.error ? claim.error.message : claim.message || "send_data replay claim failed"
          );
        }
        continue;
      }
      if (!claim.item) {
        queueEmpty = true;
        recordSendDataReplayQueueDrained(metrics);
        break;
      }

      const item = claim.item;
      processedBytes += positiveInteger(item.payloadBytes, 0);
      recordSendDataReplayStarted(metrics, item.vrcode, item);
      batch.push(processReplayClaim({ config, failureSink, metrics, spoolStore, replayTarget, claim, item }));
    }

    if (batch.length === 0) break;
    const results = await Promise.all(batch);
    for (const result of results) {
      processed += 1;
      signals.replayFailures += result.replayFailures;
    }
  }

  updateAdaptiveReplayRate({ config, memoryGuardRead, metrics, signals });
  return { ok: true, processed };
}

async function trimRealtimePending({ config, metrics, spoolStore }) {
  if (!Number.isFinite(config.maxRealtimePendingItems) || config.maxRealtimePendingItems < 0) {
    return { ok: true as const };
  }
  if (typeof spoolStore.trimPending !== "function") {
    const message = "send_data spool trimPending contract is not configured";
    recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.SPOOL_UNAVAILABLE, message);
    return {
      ok: false as const,
      processed: 0,
      reason: sendDataFailureReasons.SPOOL_UNAVAILABLE,
      message,
    };
  }
  const result = await spoolStore.trimPending(config.maxRealtimePendingItems);
  if (!result.ok) {
    const reason = result.reason || sendDataFailureReasons.SPOOL_UNAVAILABLE;
    const message = failureMessage(result);
    recordSendDataReplayClaimFailed(
      metrics,
      reason,
      message
    );
    return {
      ok: false as const,
      processed: 0,
      reason,
      message,
    };
  }
  recordSendDataRealtimeSkipped(metrics, result);
  return { ok: true as const };
}

async function processReplayClaim({
  config,
  failureSink,
  metrics,
  spoolStore,
  replayTarget,
  claim,
  item,
}) {
  let replayFailures = 0;
  const result = await sendToReplayTarget(replayTarget, item);
  const decision = completeSendDataReplayAttempt(item, result, config.replay);
  const finalItem = decision.item;

  if (decision.action === "mark_replayed") {
    const stored = await spoolStore.markReplayed(finalItem, claim.claim);
    if (!stored.ok) {
      replayFailures += 1;
      recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.SPOOL_WRITE_FAILED, failureMessage(stored));
    } else {
      recordSendDataReplaySucceeded(metrics, finalItem.vrcode, finalItem);
    }
  } else if (decision.action === "dead_letter") {
    const stored = await spoolStore.deadLetter(finalItem, claim.claim);
    if (!stored.ok) {
      replayFailures += 1;
      recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.SPOOL_WRITE_FAILED, failureMessage(stored));
    } else {
      if (finalItem.lastFailure && finalItem.lastFailure.reason !== sendDataFailureReasons.INVALID_PAYLOAD) {
        replayFailures += 1;
      }
      recordSendDataReplayDeadLettered(metrics, finalItem.vrcode, finalItem, finalItem.lastFailure);
      recordSendDataFailure(failureSink, {
        kind: "send_data_replay_dead_lettered",
        reason: finalItem.lastFailure ? finalItem.lastFailure.reason : sendDataFailureReasons.UPSTREAM_UNAVAILABLE,
        message: finalItem.lastFailure ? finalItem.lastFailure.message : "send_data replay dead-lettered",
        item: finalItem,
      });
    }
  } else {
    const stored = await spoolStore.requeue(finalItem, claim.claim);
    if (!stored.ok) {
      replayFailures += 1;
      recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.SPOOL_WRITE_FAILED, failureMessage(stored));
    } else {
      replayFailures += 1;
      recordSendDataReplayRetryableFailed(metrics, finalItem.vrcode, finalItem, finalItem.lastFailure);
    }
  }

  return { replayFailures };
}

async function sendToReplayTarget(replayTarget: SendDataReplayTargetPort, item: SendDataSpoolItem) {
  try {
    return await replayTarget.send(item);
  } catch (error) {
    return {
      ok: false,
      reason: sendDataFailureReasons.UPSTREAM_UNAVAILABLE,
      message: error && error.message ? error.message : "send_data replay target failed",
    };
  }
}

async function deadLetterInvalidClaim({
  claim,
  failureSink,
  metrics,
  spoolStore,
}: {
  claim: SendDataSpoolStoreClaimResult;
  failureSink?: SendDataFailureSinkPort;
  metrics: Record<string, unknown>;
  spoolStore: SendDataSpoolReplayPort;
}) {
  if (claim.reason !== sendDataFailureReasons.INVALID_PAYLOAD) return;
  const item = deadLetterInvalidSendDataSpoolDocument(claim.raw, claim.reason, claim.message);
  const stored = await spoolStore.deadLetter(item, claim.claim);
  if (!stored.ok) {
    recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.SPOOL_WRITE_FAILED, failureMessage(stored));
    return;
  }
  recordSendDataReplayDeadLettered(metrics, null, item, item.lastFailure);
  recordSendDataFailure(failureSink, {
    kind: "send_data_replay_dead_lettered",
    reason: item.lastFailure ? item.lastFailure.reason : sendDataFailureReasons.INVALID_PAYLOAD,
    message: item.lastFailure ? item.lastFailure.message : "invalid send_data spool document",
    item,
    rawDocument: claim.raw,
  });
}

function failureMessage(result: SendDataSpoolStoreWriteResult) {
  if (result && result.error && result.error.message) return result.error.message;
  if (result && result.message) return result.message;
  return "send_data replay store command failed";
}

function replayBatchLimit(config: SendDataReplayConfig) {
  const batchSize = positiveInteger(config.batchSize, 1);
  return Math.max(1, batchSize);
}

function replayConcurrencyLimit(config: SendDataReplayConfig) {
  const adaptive = config.adaptive || {};
  return Math.max(1, positiveInteger(adaptive.maxConcurrency, 1));
}

function replayByteBudget(config: SendDataReplayConfig) {
  const maxBytesPerSecond = positiveInteger(config.maxBytesPerSecond, 1);
  const intervalMs = positiveInteger(config.intervalMs, 1000);
  return Math.max(1, Math.floor(maxBytesPerSecond * intervalMs / 1000));
}

async function readMemoryGuard(memoryGuard?: MemoryGuardPort) {
  if (!memoryGuard) {
    return { status: "unavailable", message: "memory guard reader not configured" };
  }
  try {
    return await memoryGuard.read();
  } catch (error) {
    return {
      status: "failed",
      message: error && error.message ? error.message : "memory guard read failed",
    };
  }
}

function updateAdaptiveReplayRate({ config, memoryGuardRead, metrics, signals }) {
  if (!config.replay) return;
  const rateState = sendDataReplayRateState(metrics);
  const snapshot = metricsSnapshot(metrics);
  const decision = decideSendDataReplayRate({
    configuredMaxBytesPerSecond: rateState.configuredMaxBytesPerSecond || config.replay.maxBytesPerSecond,
    currentMaxBytesPerSecond: rateState.currentMaxBytesPerSecond,
    currentItemsPerTick: rateState.currentItemsPerTick,
    currentConcurrency: rateState.currentConcurrency,
    configuredItemsPerTick: replayBatchLimit(config.replay),
    configuredConcurrency: replayConcurrencyLimit(config.replay),
    adaptive: rateState.adaptive,
    pendingItems: snapshot.replay ? snapshot.replay.pendingItems : 0,
    queueGrowthBytesPerSecond: snapshot.throughput ? snapshot.throughput.queueGrowthBytesPerSecond : 0,
    replayFailures: signals.replayFailures,
    memoryGuard: memoryGuardRead,
  });
  recordSendDataReplayRateDecision(metrics, decision);
}

function positiveInteger(value: number, fallback: number) {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

module.exports = { createSendDataReplayWorker, replayBatchLimit, sendToReplayTarget, updateAdaptiveReplayRate };

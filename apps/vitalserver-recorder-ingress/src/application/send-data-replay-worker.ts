"use strict";

const {
  completeSendDataReplayAttempt,
  deadLetterInvalidSendDataSpoolDocument,
} = require("../domain/send-data-replay-policy");
const { sendDataFailureReasons } = require("../domain/send-data-ingress-contracts");
const {
  recordSendDataReplayClaimFailed,
  recordSendDataReplayDeadLettered,
  recordSendDataReplayRetryableFailed,
  recordSendDataReplayStarted,
  recordSendDataReplaySucceeded,
} = require("../observability/metrics");

function createSendDataReplayWorker({ config, metrics, spoolStore, replayTarget, timer = globalThis }) {
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
        return await runReplayBatch({ config, metrics, spoolStore, replayTarget });
      } finally {
        running = false;
      }
    },
  };
}

async function runReplayBatch({ config, metrics, spoolStore, replayTarget }) {
  const limit = replayBatchLimit(config.replay);
  let processed = 0;

  for (let index = 0; index < limit; index += 1) {
    const claim = await spoolStore.claim();
    if (!claim.ok) {
      await deadLetterInvalidClaim({ claim, metrics, spoolStore });
      processed += claim.reason === sendDataFailureReasons.INVALID_PAYLOAD ? 1 : 0;
      if (claim.reason !== sendDataFailureReasons.INVALID_PAYLOAD) {
        recordSendDataReplayClaimFailed(
          metrics,
          claim.reason || sendDataFailureReasons.SPOOL_UNAVAILABLE,
          claim.error ? claim.error.message : claim.message || "send_data replay claim failed"
        );
      }
      continue;
    }
    if (!claim.item) break;

    const item = claim.item;
    recordSendDataReplayStarted(metrics, item.vrcode, item);
    const result = await replayTarget.send(item);
    const decision = completeSendDataReplayAttempt(item, result, config.replay);
    const finalItem = decision.item;

    if (decision.action === "mark_replayed") {
      const stored = await spoolStore.markReplayed(finalItem, claim.claim);
      if (!stored.ok) {
        recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.SPOOL_WRITE_FAILED, failureMessage(stored));
      } else {
        recordSendDataReplaySucceeded(metrics, finalItem.vrcode, finalItem);
      }
    } else if (decision.action === "dead_letter") {
      const stored = await spoolStore.deadLetter(finalItem, claim.claim);
      if (!stored.ok) {
        recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.SPOOL_WRITE_FAILED, failureMessage(stored));
      } else {
        recordSendDataReplayDeadLettered(metrics, finalItem.vrcode, finalItem, finalItem.lastFailure);
      }
    } else {
      const stored = await spoolStore.requeue(finalItem, claim.claim);
      if (!stored.ok) {
        recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.SPOOL_WRITE_FAILED, failureMessage(stored));
      } else {
        recordSendDataReplayRetryableFailed(metrics, finalItem.vrcode, finalItem, finalItem.lastFailure);
      }
    }
    processed += 1;
  }

  return { ok: true, processed };
}

async function deadLetterInvalidClaim({ claim, metrics, spoolStore }) {
  if (claim.reason !== sendDataFailureReasons.INVALID_PAYLOAD) return;
  const item = deadLetterInvalidSendDataSpoolDocument(claim.raw, claim.reason, claim.message);
  const stored = await spoolStore.deadLetter(item, claim.claim);
  if (!stored.ok) {
    recordSendDataReplayClaimFailed(metrics, sendDataFailureReasons.SPOOL_WRITE_FAILED, failureMessage(stored));
    return;
  }
  recordSendDataReplayDeadLettered(metrics, null, item, item.lastFailure);
}

function failureMessage(result) {
  if (result && result.error && result.error.message) return result.error.message;
  if (result && result.message) return result.message;
  return "send_data replay store command failed";
}

function replayBatchLimit(config) {
  const batchSize = positiveInteger(config.batchSize, 1);
  const rateLimit = positiveInteger(config.rateLimitPerSecond, batchSize);
  return Math.max(1, Math.min(batchSize, rateLimit));
}

function positiveInteger(value, fallback) {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

module.exports = { createSendDataReplayWorker, replayBatchLimit };

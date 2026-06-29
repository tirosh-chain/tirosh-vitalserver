import type {
  SendDataReplayAttemptOptions,
  SendDataReplayAttemptResult,
  SendDataReplayCompletionResult,
  SendDataReplayConfig,
  SendDataSpoolItem,
} from "./send-data-spool-types";

type ReplayItemValidationResult =
  | {
      ok: true;
    }
  | {
      ok: false;
      reason: string;
      message: string;
    };

"use strict";

const {
  sendDataFailureReasons,
  sendDataSpoolItemStates,
} = require("./send-data-ingress-contracts");

function beginSendDataReplayAttempt(
  item: SendDataSpoolItem,
  options: SendDataReplayAttemptOptions = {}
): SendDataReplayAttemptResult {
  const validation = validateReplayItem(item);
  if (validation.ok === false) return validation;

  const now = options.now || (() => new Date());
  return {
    ok: true,
    item: {
      ...item,
      state: sendDataSpoolItemStates.IN_FLIGHT,
      attemptCount: Number.isFinite(item.attemptCount) ? item.attemptCount + 1 : 1,
      lastAttemptAt: now().toISOString(),
    },
  };
}

function completeSendDataReplayAttempt(
  item: SendDataSpoolItem,
  result: { ok: boolean; reason?: string; message?: string },
  config: SendDataReplayConfig,
  options: SendDataReplayAttemptOptions = {}
): SendDataReplayCompletionResult {
  const now = options.now || (() => new Date());
  const occurredAt = now().toISOString();
  if (result && result.ok) {
    return {
      action: "mark_replayed",
      item: {
        ...item,
        state: sendDataSpoolItemStates.REPLAYED,
        replayedAt: occurredAt,
        lastFailure: null,
      },
    };
  }

  const failure = failureRecord(
    result && result.reason ? result.reason : sendDataFailureReasons.UPSTREAM_UNAVAILABLE,
    result && result.message ? result.message : "send_data replay failed",
    occurredAt
  );
  if (failure.reason === sendDataFailureReasons.INVALID_PAYLOAD) {
    return {
      action: "dead_letter",
      item: {
        ...item,
        state: sendDataSpoolItemStates.DEAD_LETTERED,
        deadLetteredAt: occurredAt,
        lastFailure: failure,
      },
    };
  }

  const maxAttempts = Number.isFinite(config && config.maxAttempts) ? config.maxAttempts : 3;
  if ((item.attemptCount || 0) >= maxAttempts) {
    return {
      action: "dead_letter",
      item: {
        ...item,
        state: sendDataSpoolItemStates.DEAD_LETTERED,
        deadLetteredAt: occurredAt,
        lastFailure: failure,
      },
    };
  }

  return {
    action: "requeue",
    item: {
      ...item,
      state: sendDataSpoolItemStates.RETRYABLE_FAILED,
      lastFailure: failure,
    },
  };
}

function deadLetterInvalidSendDataSpoolDocument(
  raw: string | undefined,
  reason: string | undefined,
  message: string | undefined,
  options: SendDataReplayAttemptOptions = {}
): SendDataSpoolItem {
  const now = options.now || (() => new Date());
  const occurredAt = now().toISOString();
  return {
    schemaVersion: 1,
    id: `invalid_senddata_${occurredAt}`,
    state: sendDataSpoolItemStates.DEAD_LETTERED,
    vrcode: null,
    connectionId: null,
    requestId: null,
    receivedAt: null,
    payloadEncoding: null,
    payloadBytes: 0,
    payloadBase64: null,
    payloadSummary: null,
    attemptCount: 0,
    lastAttemptAt: null,
    deadLetteredAt: occurredAt,
    rawDocument: raw,
    lastFailure: failureRecord(
      reason || sendDataFailureReasons.INVALID_PAYLOAD,
      message || "invalid send_data spool document",
      occurredAt
    ),
  };
}

function validateReplayItem(item: SendDataSpoolItem): ReplayItemValidationResult {
  if (!item || typeof item !== "object") {
    return invalid("send_data spool document is not an object");
  }
  if (!item.id || typeof item.id !== "string") {
    return invalid("send_data spool document has no id");
  }
  if (!item.vrcode || typeof item.vrcode !== "string") {
    return invalid("send_data spool document has no vrcode");
  }
  if (!item.payloadBase64 || typeof item.payloadBase64 !== "string") {
    return invalid("send_data spool document has no payloadBase64");
  }
  if (!["pending", "retryable_failed"].includes(item.state)) {
    return invalid(`send_data spool document cannot be replayed from state ${item.state}`);
  }
  return { ok: true };
}

function failureRecord(reason: string, message: string, occurredAt: string) {
  return { reason, message, occurredAt };
}

function invalid(message: string): SendDataReplayAttemptResult {
  return {
    ok: false,
    reason: sendDataFailureReasons.INVALID_PAYLOAD,
    message,
  };
}

module.exports = {
  beginSendDataReplayAttempt,
  completeSendDataReplayAttempt,
  deadLetterInvalidSendDataSpoolDocument,
};

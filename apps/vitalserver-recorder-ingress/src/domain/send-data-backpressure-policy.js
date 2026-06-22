"use strict";

const {
  sendDataBackpressureActions,
  sendDataFailureReasons,
} = require("./send-data-ingress-contracts");

function evaluateSendDataBackpressure(spoolConfig, spoolState, item) {
  if (!spoolConfig || !spoolConfig.enabled) {
    return reject(sendDataFailureReasons.SPOOL_UNAVAILABLE, "send_data spool is disabled");
  }

  const payloadBytes = Number.isFinite(item && item.payloadBytes) ? item.payloadBytes : 0;
  if (spoolConfig.maxPayloadBytes > 0 && payloadBytes > spoolConfig.maxPayloadBytes) {
    return reject(sendDataFailureReasons.SPOOL_FULL, "send_data payload exceeds spool payload limit");
  }

  const pendingItems = Number.isFinite(spoolState && spoolState.pendingItems)
    ? spoolState.pendingItems
    : 0;
  if (spoolConfig.maxPendingItems > 0 && pendingItems >= spoolConfig.maxPendingItems) {
    return reject(sendDataFailureReasons.SPOOL_FULL, "send_data spool pending item limit reached");
  }

  const pendingBytes = Number.isFinite(spoolState && spoolState.pendingBytes)
    ? spoolState.pendingBytes
    : 0;
  if (spoolConfig.maxPendingBytes > 0 && pendingBytes + payloadBytes > spoolConfig.maxPendingBytes) {
    return reject(sendDataFailureReasons.SPOOL_FULL, "send_data spool pending byte limit reached");
  }

  return { action: sendDataBackpressureActions.ACCEPT };
}

function reject(reason, message) {
  return {
    action: sendDataBackpressureActions.REJECT,
    reason,
    message,
  };
}

module.exports = { evaluateSendDataBackpressure };

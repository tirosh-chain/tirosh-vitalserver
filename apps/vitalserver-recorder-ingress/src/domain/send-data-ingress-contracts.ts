"use strict";

const sendDataIngressModes = Object.freeze({
  PASSTHROUGH: "passthrough",
  MIRROR_SPOOL: "mirror_spool",
  SPOOL_ONLY: "spool_only",
  SPOOL_AND_REPLAY: "spool_and_replay",
});

const sendDataIngressOutcomes = Object.freeze({
  ACCEPTED: "accepted",
  SPOOLED: "spooled",
  REJECTED: "rejected",
  INVALID_PAYLOAD: "invalid_payload",
  RAW_ARCHIVE_WRITE_FAILED: "raw_archive_write_failed",
  SPOOL_WRITE_FAILED: "spool_write_failed",
});

const sendDataSpoolItemStates = Object.freeze({
  PENDING: "pending",
  IN_FLIGHT: "in_flight",
  REPLAYED: "replayed",
  RETRYABLE_FAILED: "retryable_failed",
  DEAD_LETTERED: "dead_lettered",
});

const sendDataBackpressureActions = Object.freeze({
  ACCEPT: "accept",
  REJECT: "reject",
  DEAD_LETTER_OLDEST: "dead_letter_oldest",
});

const sendDataFailureReasons = Object.freeze({
  INVALID_PAYLOAD: "invalid_payload",
  SPOOL_UNAVAILABLE: "spool_unavailable",
  SPOOL_FULL: "spool_full",
  RAW_ARCHIVE_UNAVAILABLE: "raw_archive_unavailable",
  RAW_ARCHIVE_WRITE_FAILED: "raw_archive_write_failed",
  SPOOL_WRITE_FAILED: "spool_write_failed",
  UPSTREAM_UNAVAILABLE: "upstream_unavailable",
  UPSTREAM_TIMEOUT: "upstream_timeout",
  UPSTREAM_REJECTED: "upstream_rejected",
  REPLAY_SESSION_UNAVAILABLE: "replay_session_unavailable",
});

const terminalSpoolItemStates = new Set([
  sendDataSpoolItemStates.REPLAYED,
  sendDataSpoolItemStates.DEAD_LETTERED,
]);

function isTerminalSpoolItemState(state) {
  return terminalSpoolItemStates.has(state);
}

module.exports = {
  sendDataIngressModes,
  sendDataIngressOutcomes,
  sendDataSpoolItemStates,
  sendDataBackpressureActions,
  sendDataFailureReasons,
  isTerminalSpoolItemState,
};

export type SendDataRawArchiveFinalizationState =
  | "not_observed"
  | "open"
  | "inactive_candidate"
  | "finalizable_by_inactivity"
  | "finalizable_by_shutdown"
  | "already_exported";

export type SendDataRawArchiveFinalizationReason =
  | "recorder_not_observed"
  | "raw_archive_empty"
  | "active_connection_present"
  | "last_archive_timestamp_missing"
  | "quiet_window_not_elapsed"
  | "archive_cursor_not_stable"
  | "realtime_replay_not_drained"
  | "already_exported";

export type SendDataRawArchiveFinalizationInput = {
  vrcode: string;
  trigger?: "inactivity" | "shutdown";
  hasJoined: boolean;
  rawArchiveRecords: number;
  activeConnections: number;
  lastRawArchivedAt: string | null;
  nowMs: number;
  quietWindowMs?: number;
  archiveCursorStable: boolean;
  realtimeReplayDrained: boolean;
  alreadyExported: boolean;
};

export type SendDataRawArchiveFinalizationDecision = {
  vrcode: string;
  state: SendDataRawArchiveFinalizationState;
  finalizable: boolean;
  quietWindowMs: number;
  inactiveForMs: number | null;
  reasons: SendDataRawArchiveFinalizationReason[];
};

"use strict";

const DEFAULT_QUIET_WINDOW_MS = 5 * 60 * 1000;

function decideSendDataRawArchiveFinalization(
  input: SendDataRawArchiveFinalizationInput
): SendDataRawArchiveFinalizationDecision {
  const quietWindowMs = positiveInteger(input.quietWindowMs, DEFAULT_QUIET_WINDOW_MS);
  const inactiveForMs = ageMs(input.lastRawArchivedAt, input.nowMs);
  const reasons: SendDataRawArchiveFinalizationReason[] = [];
  const shutdownRequested = input.trigger === "shutdown";

  if (!input.hasJoined) {
    return decision(input, "not_observed", false, quietWindowMs, inactiveForMs, ["recorder_not_observed"]);
  }
  if (input.alreadyExported) {
    return decision(input, "already_exported", false, quietWindowMs, inactiveForMs, ["already_exported"]);
  }
  if (positiveInteger(input.rawArchiveRecords, 0) === 0) {
    reasons.push("raw_archive_empty");
  }
  if (positiveInteger(input.activeConnections, 0) > 0) {
    reasons.push("active_connection_present");
  }
  if (inactiveForMs === null) {
    reasons.push("last_archive_timestamp_missing");
  } else if (!shutdownRequested && inactiveForMs < quietWindowMs) {
    reasons.push("quiet_window_not_elapsed");
  }
  if (!shutdownRequested && !input.archiveCursorStable) {
    reasons.push("archive_cursor_not_stable");
  }
  if (!input.realtimeReplayDrained) {
    reasons.push("realtime_replay_not_drained");
  }

  if (reasons.length === 0) {
    return decision(
      input,
      shutdownRequested ? "finalizable_by_shutdown" : "finalizable_by_inactivity",
      true,
      quietWindowMs,
      inactiveForMs,
      []
    );
  }

  const candidate = reasons.every((reason) => reason !== "active_connection_present" && reason !== "raw_archive_empty");
  return decision(input, candidate ? "inactive_candidate" : "open", false, quietWindowMs, inactiveForMs, reasons);
}

function decision(
  input: SendDataRawArchiveFinalizationInput,
  state: SendDataRawArchiveFinalizationState,
  finalizable: boolean,
  quietWindowMs: number,
  inactiveForMs: number | null,
  reasons: SendDataRawArchiveFinalizationReason[]
): SendDataRawArchiveFinalizationDecision {
  return {
    vrcode: input.vrcode,
    state,
    finalizable,
    quietWindowMs,
    inactiveForMs,
    reasons,
  };
}

function ageMs(timestamp: string | null, nowMs: number) {
  if (!timestamp) return null;
  const parsed = Date.parse(timestamp);
  if (!Number.isFinite(parsed)) return null;
  return Math.max(0, nowMs - parsed);
}

function positiveInteger(value: number | undefined, fallback: number) {
  return Number.isFinite(value) && Number(value) > 0 ? Math.floor(Number(value)) : fallback;
}

module.exports = {
  DEFAULT_QUIET_WINDOW_MS,
  decideSendDataRawArchiveFinalization,
};

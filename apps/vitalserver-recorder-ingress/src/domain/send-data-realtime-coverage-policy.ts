export type SendDataRealtimeCoverageRecorder = {
  vrcode: string;
  activeConnections: number;
  sendDataEventsObserved: number;
  replayedEvents: number;
  lastReplayAt: string | null;
};

export type SendDataRealtimeCoverageDecision = {
  windowSeconds: number;
  observedRecorderCount: number;
  activeObservedRecorderCount: number;
  replayedRecorderCount: number;
  activeRecordersMissingRecentReplay: string[];
  minReplayedEventsPerRecorder: number;
  maxReplayedEventsPerRecorder: number;
  maxReplayAgeSeconds: number | null;
};

export type SendDataRealtimeCoverageInput = {
  recorders: SendDataRealtimeCoverageRecorder[];
  nowMs: number;
  windowSeconds: number;
};

"use strict";

function decideSendDataRealtimeCoverage(
  input: SendDataRealtimeCoverageInput
): SendDataRealtimeCoverageDecision {
  const windowSeconds = positiveInteger(input.windowSeconds, 60);
  const observed = input.recorders
    .filter((recorder) => positiveInteger(recorder.sendDataEventsObserved, 0) > 0);
  const replayed = observed
    .filter((recorder) => positiveInteger(recorder.replayedEvents, 0) > 0);
  const replayCounts = replayed.map((recorder) => positiveInteger(recorder.replayedEvents, 0));
  const activeObserved = observed.filter((recorder) => positiveInteger(recorder.activeConnections, 0) > 0);
  const activeRecordersMissingRecentReplay = activeObserved
    .filter((recorder) => !isRecentTimestamp(recorder.lastReplayAt, input.nowMs, windowSeconds))
    .map((recorder) => recorder.vrcode)
    .sort();
  const replayAges = replayed
    .map((recorder) => ageSeconds(recorder.lastReplayAt, input.nowMs))
    .filter((age) => age !== null) as number[];

  return {
    windowSeconds,
    observedRecorderCount: observed.length,
    activeObservedRecorderCount: activeObserved.length,
    replayedRecorderCount: replayed.length,
    activeRecordersMissingRecentReplay,
    minReplayedEventsPerRecorder: replayCounts.length > 0 ? Math.min(...replayCounts) : 0,
    maxReplayedEventsPerRecorder: replayCounts.length > 0 ? Math.max(...replayCounts) : 0,
    maxReplayAgeSeconds: replayAges.length > 0 ? Math.max(...replayAges) : null,
  };
}

function ageSeconds(timestamp: string | null, nowMs: number) {
  if (!timestamp) return null;
  const parsed = Date.parse(timestamp);
  if (!Number.isFinite(parsed)) return null;
  return Math.max(0, Math.floor((nowMs - parsed) / 1000));
}

function isRecentTimestamp(timestamp: string | null, nowMs: number, windowSeconds: number) {
  const age = ageSeconds(timestamp, nowMs);
  return age !== null && age <= windowSeconds;
}

function positiveInteger(value: number, fallback: number) {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

module.exports = { decideSendDataRealtimeCoverage };

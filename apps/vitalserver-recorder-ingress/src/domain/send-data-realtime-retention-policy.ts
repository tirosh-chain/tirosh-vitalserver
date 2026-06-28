export type SendDataRealtimeRetentionCandidate = {
  index: number;
  vrcode: string | null;
  payloadBytes: number;
};

export type SendDataRealtimeRetentionDecision = {
  preservedIndexes: number[];
  skippedIndexes: number[];
  skippedRealtimeItems: number;
  skippedRealtimeBytes: number;
  skippedRealtimeByRecorder: Record<string, { items: number; bytes: number }>;
  preservedRealtimeItems: number;
};

export type SendDataRealtimeRetentionInput = {
  skippedCandidates: SendDataRealtimeRetentionCandidate[];
  keptCandidates: SendDataRealtimeRetentionCandidate[];
};

"use strict";

function decideSendDataRealtimeRetention(
  input: SendDataRealtimeRetentionInput
): SendDataRealtimeRetentionDecision {
  const skippedCandidates = input.skippedCandidates;
  const keptCandidates = input.keptCandidates;
  const keptRecorders = new Set(keptCandidates
    .map((candidate) => candidate.vrcode)
    .filter(Boolean));
  const latestSkippedByRecorder = new Map<string, SendDataRealtimeRetentionCandidate>();

  for (const candidate of skippedCandidates) {
    if (!candidate || !candidate.vrcode) continue;
    latestSkippedByRecorder.set(candidate.vrcode, candidate);
  }

  const preservedCandidates = Array.from(latestSkippedByRecorder.values())
    .filter((candidate) => !keptRecorders.has(candidate.vrcode))
    .sort((left, right) => left.index - right.index);
  const preservedIndexes = new Set(preservedCandidates.map((candidate) => candidate.index));
  const skipped = skippedCandidates.filter((candidate) => !preservedIndexes.has(candidate.index));

  return {
    preservedIndexes: Array.from(preservedIndexes).sort((left, right) => left - right),
    skippedIndexes: skipped.map((candidate) => candidate.index).sort((left, right) => left - right),
    skippedRealtimeItems: skipped.length,
    skippedRealtimeBytes: skipped.reduce((total, candidate) => total + positiveInteger(candidate.payloadBytes, 0), 0),
    skippedRealtimeByRecorder: skippedByRecorder(skipped),
    preservedRealtimeItems: preservedCandidates.length,
  };
}

function skippedByRecorder(candidates: SendDataRealtimeRetentionCandidate[]) {
  const byRecorder: Record<string, { items: number; bytes: number }> = {};
  for (const candidate of candidates) {
    if (!candidate || !candidate.vrcode) continue;
    byRecorder[candidate.vrcode] = byRecorder[candidate.vrcode] || { items: 0, bytes: 0 };
    byRecorder[candidate.vrcode].items += 1;
    byRecorder[candidate.vrcode].bytes += positiveInteger(candidate.payloadBytes, 0);
  }
  return byRecorder;
}

function positiveInteger(value: number, fallback: number) {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

module.exports = { decideSendDataRealtimeRetention };

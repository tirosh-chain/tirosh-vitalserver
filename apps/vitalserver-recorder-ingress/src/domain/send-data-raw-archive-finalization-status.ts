import type {
  SendDataRawArchiveExportCheckpoint,
  SendDataRawArchiveExportJob,
  SendDataRawArchiveExportStateDocument,
  SendDataRawArchiveFinalizationRequest,
} from "../application/ports/outbound/send-data-raw-archive-export-job-store-port";

export type SendDataRawArchiveFinalizationProgressState =
  | "queued"
  | "processing"
  | "retrying"
  | "uploaded"
  | "failed"
  | "partial"
  | "missing";

export type SendDataRawArchiveFinalizationRequestProgress = {
  requestId: string;
  vrcode: string | null;
  state: Exclude<SendDataRawArchiveFinalizationProgressState, "partial">;
  attempts: number;
  maxAttempts: number | null;
  requestedAt: string | null;
  updatedAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  nextAttemptAt: string | null;
  failure: { reason: string; message: string; occurredAt: string } | null;
};

export type SendDataRawArchiveFinalizationProgress = {
  state: SendDataRawArchiveFinalizationProgressState;
  requests: SendDataRawArchiveFinalizationRequestProgress[];
  updatedAt: string | null;
};

/**
 * Project durable recorder-ingress finalization state for explicit request IDs.
 *
 * This is deliberately a pure owner-side projection.  Product Lab stores only
 * the request IDs it submitted; it never reconstructs export state from logs,
 * files, or recorder activity.
 */
export function projectSendDataRawArchiveFinalizationProgress(
  document: SendDataRawArchiveExportStateDocument,
  requestIds: string[],
): SendDataRawArchiveFinalizationProgress {
  const requests = uniqueNonEmptyStrings(requestIds).map((requestId) =>
    projectRequest(document, requestId),
  );
  return {
    state: aggregateState(requests),
    requests,
    updatedAt: latestTimestamp(requests.map((request) => request.updatedAt)),
  };
}

function projectRequest(
  document: SendDataRawArchiveExportStateDocument,
  requestId: string,
): SendDataRawArchiveFinalizationRequestProgress {
  const active = document.activeJob;
  if (active && active.requestId === requestId) return jobProgress(active);

  const historic = document.history.find((job) => job.requestId === requestId);
  if (historic) return jobProgress(historic);

  const pending = document.pendingFinalizations.find(
    (request) => request.requestId === requestId,
  );
  if (pending) return queuedProgress(pending);

  // Earlier persisted state documents used checkpoint.jobId as the externally
  // returned identifier. Preserve that explicit legacy identifier as uploaded;
  // future checkpoints also store requestId.
  const checkpoint = Object.values(document.checkpointsByVrcode).find(
    (candidate) =>
      candidate.requestId === requestId || candidate.jobId === requestId,
  );
  if (checkpoint) return checkpointProgress(requestId, checkpoint);

  return {
    requestId,
    vrcode: null,
    state: "missing",
    attempts: 0,
    maxAttempts: null,
    requestedAt: null,
    updatedAt: null,
    startedAt: null,
    completedAt: null,
    nextAttemptAt: null,
    failure: null,
  };
}

function queuedProgress(
  request: SendDataRawArchiveFinalizationRequest,
): SendDataRawArchiveFinalizationRequestProgress {
  return {
    requestId: request.requestId,
    vrcode: request.vrcode,
    state: "queued",
    attempts: 0,
    maxAttempts: null,
    requestedAt: request.requestedAt,
    updatedAt: request.requestedAt,
    startedAt: null,
    completedAt: null,
    nextAttemptAt: null,
    failure: null,
  };
}

function jobProgress(
  job: SendDataRawArchiveExportJob,
): SendDataRawArchiveFinalizationRequestProgress {
  return {
    requestId: job.requestId || job.jobId,
    vrcode: job.vrcode,
    state: stateForJob(job),
    attempts: job.attempts,
    maxAttempts: job.maxAttempts,
    requestedAt: job.createdAt,
    updatedAt: job.updatedAt,
    startedAt: job.startedAt,
    completedAt: job.completedAt,
    nextAttemptAt: job.nextAttemptAt,
    failure: job.lastFailure,
  };
}

function checkpointProgress(
  requestId: string,
  checkpoint: SendDataRawArchiveExportCheckpoint,
): SendDataRawArchiveFinalizationRequestProgress {
  return {
    requestId,
    vrcode: checkpoint.vrcode,
    state: "uploaded",
    attempts: 1,
    maxAttempts: null,
    requestedAt: checkpoint.completedAt,
    updatedAt: checkpoint.completedAt,
    startedAt: null,
    completedAt: checkpoint.completedAt,
    nextAttemptAt: null,
    failure: null,
  };
}

function stateForJob(
  job: SendDataRawArchiveExportJob,
): Exclude<SendDataRawArchiveFinalizationProgressState, "partial" | "missing"> {
  if (job.state === "uploaded") return "uploaded";
  if (job.state === "failed") return "failed";
  if (job.state === "retryable_failed") return "retrying";
  return job.state === "pending" ? "queued" : "processing";
}

function aggregateState(
  requests: SendDataRawArchiveFinalizationRequestProgress[],
): SendDataRawArchiveFinalizationProgressState {
  if (requests.length === 0 || requests.every((request) => request.state === "missing")) {
    return "missing";
  }
  const states = new Set(requests.map((request) => request.state));
  const completed = states.has("uploaded");
  const terminalProblem = states.has("failed") || states.has("missing");
  if (completed && terminalProblem) return "partial";
  if (completed && states.size === 1) return "uploaded";
  if (states.has("failed")) return "failed";
  if (states.has("missing")) return "missing";
  if (states.has("processing")) return "processing";
  if (states.has("retrying")) return "retrying";
  if (states.has("queued")) return "queued";
  return "missing";
}

function latestTimestamp(values: Array<string | null>): string | null {
  const timestamps = values.filter((value): value is string => typeof value === "string");
  return timestamps.sort().at(-1) || null;
}

function uniqueNonEmptyStrings(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

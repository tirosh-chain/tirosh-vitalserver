import type { SendDataRawArchiveExportWorkerPort } from "./ports/inbound/send-data-raw-archive-export-worker-port";
import type { SendDataRawArchiveExportWorkerRunOptions } from "./ports/inbound/send-data-raw-archive-export-worker-port";
import type {
  SendDataRawArchiveExportJob,
  SendDataRawArchiveExportJobStorePort,
  SendDataRawArchiveExportStateDocument,
  SendDataRawArchiveFinalizationRequest,
  SendDataRawArchiveFinalizationTrigger,
} from "./ports/outbound/send-data-raw-archive-export-job-store-port";
import type { SendDataRawArchiveRecoveryExecutorPort } from "./ports/outbound/send-data-raw-archive-recovery-executor-port";

"use strict";

const crypto = require("crypto");
const { decideSendDataRawArchiveFinalization } = require("../domain/send-data-raw-archive-finalization-policy");
const {
  metricsSnapshot,
  recordSendDataRawArchiveAutoExportDecision,
  recordSendDataRawArchiveAutoExportFailed,
  recordSendDataRawArchiveAutoExportStarted,
  recordSendDataRawArchiveAutoExportSucceeded,
} = require("../observability/metrics");

function createSendDataRawArchiveExportWorker({
  config,
  executor,
  jobStore,
  metrics,
}: {
  config: { rawArchive?: { autoExport?: Record<string, unknown>; path?: string } };
  executor: SendDataRawArchiveRecoveryExecutorPort;
  jobStore: SendDataRawArchiveExportJobStorePort;
  metrics: Record<string, unknown>;
}): SendDataRawArchiveExportWorkerPort {
  const settings = normalizeSettings(config && config.rawArchive ? config.rawArchive.autoExport : {});
  let timer: NodeJS.Timeout | null = null;
  let running = false;

  async function runOnce(options: SendDataRawArchiveExportWorkerRunOptions = {}) {
    if (!settings.enabled) {
      recordSendDataRawArchiveAutoExportDecision(metrics, {
        state: "disabled",
        finalizable: false,
        reasons: ["disabled"],
      });
      return { ok: true, state: "disabled", disabled: true };
    }
    if (running) {
      return { ok: false, state: "running", reason: "already_running", message: "raw archive export worker is already running" };
    }

    running = true;
    try {
      return await runExportTick({
        settings,
        executor,
        jobStore,
        metrics,
        trigger: options.trigger || "inactivity",
      });
    } finally {
      running = false;
    }
  }

  async function requestFinalization(input) {
    const vrcodes = normalizedVrcodes(input && input.vrcodes);
    if (vrcodes.length === 0) {
      return {
        ok: false,
        state: "rejected" as const,
        reason: "invalid_vrcodes",
        message: "raw archive finalization requires at least one non-empty vrcode",
      };
    }
    if (input.reason !== "lab_session_stopped" && input.reason !== "lab_recorder_stopped") {
      return {
        ok: false,
        state: "rejected" as const,
        reason: "invalid_reason",
        message: "raw archive finalization reason is invalid",
      };
    }

    const nowIso = new Date().toISOString();
    let state = jobStore.read();
    if (state.activeJob && state.activeJob.state === "failed") {
      return {
        ok: false,
        state: "rejected" as const,
        reason: "job_failed",
        message: "raw archive finalization is blocked by a terminal failed job",
      };
    }
    const snapshot = metricsSnapshot(metrics);
    const requestIds: string[] = [];
    let enqueuedCount = 0;
    const pending = [...state.pendingFinalizations];
    for (const vrcode of vrcodes) {
      const existing = pending.find((request) => request.vrcode === vrcode);
      if (existing) {
        requestIds.push(existing.requestId);
        continue;
      }
      const recorder = (snapshot.recorders || []).find((candidate) => candidate.vrcode === vrcode);
      if (!recorder || !recorder.rawArchive || !Number.isFinite(recorder.rawArchive.lastOffset)) {
        return {
          ok: false,
          state: "rejected" as const,
          reason: "recorder_archive_not_observed",
          message: `raw archive finalization requires an observed recorder archive vrcode=${vrcode}`,
        };
      }
      const checkpoint = state.checkpointsByVrcode[vrcode];
      if (checkpoint
        && checkpoint.archivePath === snapshot.rawArchive.path
        && checkpoint.endOffset === recorder.rawArchive.lastOffset) {
        requestIds.push(checkpoint.jobId);
        continue;
      }
      const request: SendDataRawArchiveFinalizationRequest = {
        requestId: crypto.randomUUID(),
        vrcode,
        reason: input.reason,
        requestedAt: nowIso,
      };
      pending.push(request);
      requestIds.push(request.requestId);
      enqueuedCount += 1;
    }
    state = writeState(jobStore, {
      ...state,
      updatedAt: nowIso,
      pendingFinalizations: pending,
    });
    for (let index = 0; index < enqueuedCount; index += 1) {
      const result = await runOnce({ trigger: "explicit" });
      if (result.state !== "uploaded") break;
    }
    return { ok: true, state: "accepted" as const, requestIds };
  }

  return {
    start() {
      if (!settings.enabled || timer) return;
      timer = setInterval(() => {
        runOnce().catch((error) => {
          recordSendDataRawArchiveAutoExportFailed(metrics, null, "worker_tick_failed", errorMessage(error));
        });
      }, settings.scanIntervalMs);
    },
    stop() {
      if (!timer) return;
      clearInterval(timer);
      timer = null;
    },
    runOnce,
    requestFinalization,
  };
}

async function runExportTick({ settings, executor, jobStore, metrics, trigger }) {
  const snapshot = metricsSnapshot(metrics);
  const archive = snapshot.rawArchive || {};
  const archivePath = archive.path || "";
  const now = new Date();
  const nowIso = now.toISOString();
  let state = jobStore.read();

  if (!archivePath || archive.status !== "ready") {
    recordSendDataRawArchiveAutoExportDecision(metrics, {
      state: "open",
      finalizable: false,
      reasons: ["raw_archive_unavailable"],
    });
    return { ok: true, state: "open" };
  }

  if (state.activeJob && state.activeJob.state === "retryable_failed") {
    const nextAttemptAt = state.activeJob.nextAttemptAt ? Date.parse(state.activeJob.nextAttemptAt) : NaN;
    if (Number.isFinite(nextAttemptAt) && nextAttemptAt > now.getTime()) {
      return { ok: true, state: "retryable_failed", jobId: state.activeJob.jobId };
    }
    return await executeJob({ settings, executor, jobStore, metrics, state, job: state.activeJob });
  }
  if (state.activeJob && state.activeJob.state === "failed") {
    return { ok: false, state: "failed", reason: "job_failed", message: "raw archive export job is terminal", jobId: state.activeJob.jobId };
  }
  if (state.activeJob) {
    return await executeJob({ settings, executor, jobStore, metrics, state, job: state.activeJob });
  }

  const candidates = candidateVrcodes(state, snapshot, trigger);
  let firstDecision: Record<string, unknown> | null = null;
  for (const candidate of candidates) {
    const recorder = (snapshot.recorders || []).find((value) => value.vrcode === candidate.vrcode);
    const recorderArchive = recorder && recorder.rawArchive ? recorder.rawArchive : {};
    const endOffset = Number.isFinite(recorderArchive.lastOffset) ? recorderArchive.lastOffset : 0;
    const observed = state.observedByVrcode[candidate.vrcode];
    const observedChanged = !observed
      || observed.archivePath !== archivePath
      || observed.endOffset !== endOffset;
    if (observedChanged) {
      state = writeState(jobStore, {
        ...state,
        updatedAt: nowIso,
        observedByVrcode: {
          ...state.observedByVrcode,
          [candidate.vrcode]: {
            vrcode: candidate.vrcode,
            archivePath,
            endOffset,
            observedAt: nowIso,
          },
        },
      });
    }
    const currentObserved = state.observedByVrcode[candidate.vrcode];
    const stableForMs = currentObserved
      && currentObserved.archivePath === archivePath
      && currentObserved.endOffset === endOffset
      ? now.getTime() - Date.parse(currentObserved.observedAt)
      : 0;
    const checkpoint = state.checkpointsByVrcode[candidate.vrcode];
    const startOffset = checkpoint && checkpoint.archivePath === archivePath
      ? checkpoint.endOffset
      : 0;
    const replay = recorder && recorder.replay ? recorder.replay : {};
    const spool = recorder && recorder.spool ? recorder.spool : {};
    const decision = decideSendDataRawArchiveFinalization({
      vrcode: candidate.vrcode,
      trigger: candidate.trigger,
      hasJoined: Boolean(recorder && (recorder.sendDataEventsObserved || 0) > 0),
      rawArchiveRecords: recorderArchive.persistedEvents || 0,
      activeConnections: recorder ? recorder.activeConnections || 0 : 0,
      lastRawArchivedAt: recorderArchive.lastArchivedAt || null,
      nowMs: now.getTime(),
      quietWindowMs: settings.quietWindowMs,
      archiveCursorStable: stableForMs >= settings.cursorStableMs,
      realtimeReplayDrained: (spool.pendingItems || 0) === 0
        && (replay.pendingItems || 0) === 0
        && (replay.inFlightItems || 0) === 0,
      alreadyExported: endOffset > 0 && startOffset === endOffset,
    });
    const decisionDocument = {
      ...decision,
      archivePath,
      archiveCursor: endOffset,
      cursorStableForMs: stableForMs,
    };
    recordSendDataRawArchiveAutoExportDecision(metrics, decisionDocument);
    firstDecision = firstDecision || decisionDocument;
    if (!decision.finalizable) continue;

    const job = createJob({
      archivePath,
      startOffset,
      endOffset,
      settings,
      nowIso,
      vrcode: candidate.vrcode,
      trigger: candidate.trigger,
      requestId: candidate.requestId,
    });
    state = writeState(jobStore, { ...state, updatedAt: nowIso, activeJob: job });
    return await executeJob({ settings, executor, jobStore, metrics, state, job });
  }

  return { ok: true, state: firstDecision ? String(firstDecision.state) : "not_observed" };
}

async function executeJob({ settings, executor, jobStore, metrics, state, job }) {
  const startedAt = new Date().toISOString();
  const runningJob = {
    ...job,
    state: "running" as const,
    attempts: job.attempts + 1,
    startedAt,
    updatedAt: startedAt,
    nextAttemptAt: null,
  };
  recordSendDataRawArchiveAutoExportStarted(metrics, runningJob);
  state = writeState(jobStore, { ...state, updatedAt: startedAt, activeJob: runningJob });

  const result = await executor.recover({
    rawArchivePath: runningJob.archivePath,
    outputDir: settings.outputDir,
    vitalserverUrl: settings.vitalserverUrl,
    endpoint: settings.uploadEndpoint,
    timeoutMs: settings.requestTimeoutMs,
    vrcode: runningJob.vrcode,
    startOffset: runningJob.startOffset,
    endOffset: runningJob.endOffset,
  });
  const completedAt = new Date().toISOString();

  if (result.ok) {
    const uploadedJob = {
      ...runningJob,
      state: "uploaded" as const,
      completedAt,
      updatedAt: completedAt,
      result: result.response,
    };
    const pendingFinalizations = state.pendingFinalizations.filter(
      (request) => request.requestId !== uploadedJob.requestId
    );
    writeState(jobStore, {
      ...state,
      updatedAt: completedAt,
      checkpointsByVrcode: {
        ...state.checkpointsByVrcode,
        [uploadedJob.vrcode]: {
          vrcode: uploadedJob.vrcode,
          archivePath: uploadedJob.archivePath,
          endOffset: uploadedJob.endOffset,
          jobId: uploadedJob.jobId,
          completedAt,
        },
      },
      pendingFinalizations,
      activeJob: null,
      history: [uploadedJob, ...(state.history || [])].slice(0, settings.historyLimit),
    });
    recordSendDataRawArchiveAutoExportSucceeded(metrics, uploadedJob, result.response);
    return { ok: true, state: "uploaded", jobId: uploadedJob.jobId };
  }

  const canRetry = runningJob.attempts < runningJob.maxAttempts;
  const failure = {
    reason: result.reason,
    message: result.message,
    occurredAt: completedAt,
  };
  const failedJob = {
    ...runningJob,
    state: canRetry ? "retryable_failed" as const : "failed" as const,
    updatedAt: completedAt,
    completedAt: canRetry ? null : completedAt,
    nextAttemptAt: canRetry ? new Date(Date.parse(completedAt) + settings.retryDelayMs).toISOString() : null,
    lastFailure: failure,
    result: result.response || null,
  };
  writeState(jobStore, { ...state, updatedAt: completedAt, activeJob: failedJob });
  recordSendDataRawArchiveAutoExportFailed(metrics, failedJob, failure.reason, failure.message);
  return {
    ok: false,
    state: failedJob.state,
    reason: failure.reason,
    message: failure.message,
    jobId: failedJob.jobId,
  };
}

function candidateVrcodes(state, snapshot, trigger) {
  const pending = state.pendingFinalizations.map((request) => ({
    vrcode: request.vrcode,
    trigger: "explicit" as SendDataRawArchiveFinalizationTrigger,
    requestId: request.requestId,
  }));
  const pendingVrcodes = new Set(pending.map((candidate) => candidate.vrcode));
  return [
    ...pending,
    ...(snapshot.recorders || [])
      .filter((recorder) => !pendingVrcodes.has(recorder.vrcode))
      .map((recorder) => ({
        vrcode: recorder.vrcode,
        trigger: trigger === "shutdown" ? "shutdown" : "inactivity" as SendDataRawArchiveFinalizationTrigger,
        requestId: null,
      })),
  ];
}

function createJob({ archivePath, startOffset, endOffset, settings, nowIso, vrcode, trigger, requestId }): SendDataRawArchiveExportJob {
  return {
    schemaVersion: 2,
    jobId: crypto.randomUUID(),
    requestId,
    trigger,
    vrcode,
    archivePath,
    startOffset,
    endOffset,
    state: "pending",
    attempts: 0,
    maxAttempts: settings.maxAttempts,
    createdAt: nowIso,
    updatedAt: nowIso,
    startedAt: null,
    completedAt: null,
    nextAttemptAt: null,
    lastFailure: null,
    result: null,
  };
}

function writeState(jobStore, document): SendDataRawArchiveExportStateDocument {
  jobStore.write(document);
  return document;
}

function normalizedVrcodes(value) {
  if (!Array.isArray(value)) return [];
  return Array.from(new Set(value.filter((item) => typeof item === "string" && item.trim()).map((item) => item.trim())));
}

function normalizeSettings(raw) {
  return {
    enabled: Boolean(raw && raw.enabled),
    quietWindowMs: positiveInteger(raw && raw.quietWindowMs, 300000),
    scanIntervalMs: positiveInteger(raw && raw.scanIntervalMs, 60000),
    cursorStableMs: positiveInteger(raw && raw.cursorStableMs, positiveInteger(raw && raw.scanIntervalMs, 60000)),
    retryDelayMs: positiveInteger(raw && raw.retryDelayMs, 60000),
    maxAttempts: positiveInteger(raw && raw.maxAttempts, 3),
    requestTimeoutMs: positiveInteger(raw && raw.requestTimeoutMs, 300000),
    outputDir: stringValue(raw && raw.outputDir, "/var/lib/vitalserver-recorder-ingress/recovery/vital-export"),
    vitalserverUrl: stringValue(raw && raw.vitalserverUrl, "http://app:80"),
    uploadEndpoint: stringValue(raw && raw.uploadEndpoint, "/upload"),
    historyLimit: positiveInteger(raw && raw.historyLimit, 20),
  };
}

function positiveInteger(value, fallback) {
  return Number.isFinite(value) && Number(value) > 0 ? Math.floor(Number(value)) : fallback;
}

function stringValue(value, fallback) {
  return typeof value === "string" && value ? value : fallback;
}

function errorMessage(error) {
  return error && error.message ? error.message : String(error);
}

module.exports = { createSendDataRawArchiveExportWorker };

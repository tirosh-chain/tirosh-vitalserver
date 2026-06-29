import type { SendDataRawArchiveExportWorkerPort } from "./ports/inbound/send-data-raw-archive-export-worker-port";
import type {
  SendDataRawArchiveExportJob,
  SendDataRawArchiveExportJobStorePort,
  SendDataRawArchiveExportStateDocument,
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

  async function runOnce() {
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
      return await runExportTick({ settings, executor, jobStore, metrics });
    } finally {
      running = false;
    }
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
  };
}

async function runExportTick({ settings, executor, jobStore, metrics }) {
  const snapshot = metricsSnapshot(metrics);
  const archive = snapshot.rawArchive || {};
  const archivePath = archive.path || "";
  const archiveCursor = Number.isFinite(archive.lastOffset) ? archive.lastOffset : 0;
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

  const observedChanged = !state.lastObserved
    || state.lastObserved.archivePath !== archivePath
    || state.lastObserved.archiveCursor !== archiveCursor;
  if (observedChanged) {
    state = writeState(jobStore, {
      ...state,
      updatedAt: nowIso,
      lastObserved: { archivePath, archiveCursor, observedAt: nowIso },
    });
  }

  const stableForMs = state.lastObserved && state.lastObserved.archivePath === archivePath
    && state.lastObserved.archiveCursor === archiveCursor
    ? now.getTime() - Date.parse(state.lastObserved.observedAt)
    : 0;
  const archiveCursorStable = stableForMs >= settings.cursorStableMs;
  const alreadyExported = Boolean(
    state.checkpoint
      && state.checkpoint.archivePath === archivePath
      && state.checkpoint.archiveCursor === archiveCursor
  );
  const replayDrained = (snapshot.spool.pendingItems || 0) === 0
    && (snapshot.replay.pendingItems || 0) === 0
    && (snapshot.replay.inFlightItems || 0) === 0;

  const decision = decideSendDataRawArchiveFinalization({
    vrcode: "raw_archive",
    hasJoined: (snapshot.recorders || []).some((recorder) => (recorder.sendDataEventsObserved || 0) > 0),
    rawArchiveRecords: archive.persistedEvents || 0,
    activeConnections: snapshot.activeRecorderConnections || 0,
    lastRawArchivedAt: archive.lastArchivedAt || null,
    nowMs: now.getTime(),
    quietWindowMs: settings.quietWindowMs,
    archiveCursorStable,
    realtimeReplayDrained: replayDrained,
    alreadyExported,
  });
  recordSendDataRawArchiveAutoExportDecision(metrics, {
    ...decision,
    archivePath,
    archiveCursor,
    cursorStableForMs: stableForMs,
  });

  if (state.activeJob && state.activeJob.state === "retryable_failed") {
    const nextAttemptAt = state.activeJob.nextAttemptAt ? Date.parse(state.activeJob.nextAttemptAt) : NaN;
    if (Number.isFinite(nextAttemptAt) && nextAttemptAt > now.getTime()) {
      return { ok: true, state: "retryable_failed", jobId: state.activeJob.jobId };
    }
  }

  if (state.activeJob && state.activeJob.state === "failed") {
    return { ok: false, state: "failed", reason: "job_failed", message: "raw archive export job is terminal", jobId: state.activeJob.jobId };
  }

  if (!decision.finalizable && !state.activeJob) {
    return { ok: true, state: decision.state };
  }

  const job = state.activeJob || createJob({ archivePath, archiveCursor, settings, nowIso });
  state = writeState(jobStore, { ...state, updatedAt: nowIso, activeJob: job });
  return await executeJob({ settings, executor, jobStore, metrics, state, job });
}

async function executeJob({ settings, executor, jobStore, metrics, state, job }) {
  const startedAt = new Date().toISOString();
  const runningJob = {
    ...job,
    state: "running",
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
  });
  const completedAt = new Date().toISOString();

  if (result.ok) {
    const uploadedJob = {
      ...runningJob,
      state: "uploaded",
      completedAt,
      updatedAt: completedAt,
      result: result.response,
    };
    writeState(jobStore, {
      ...state,
      updatedAt: completedAt,
      checkpoint: {
        archivePath: uploadedJob.archivePath,
        archiveCursor: uploadedJob.archiveCursor,
        jobId: uploadedJob.jobId,
        completedAt,
      },
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
    state: canRetry ? "retryable_failed" : "failed",
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

function createJob({ archivePath, archiveCursor, settings, nowIso }): SendDataRawArchiveExportJob {
  return {
    schemaVersion: 1,
    jobId: crypto.randomUUID(),
    archivePath,
    archiveCursor,
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

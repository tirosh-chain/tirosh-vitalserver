"use strict";

const { decideSendDataRealtimeCoverage } = require("../domain/send-data-realtime-coverage-policy");

function createMetrics() {
  return {
    startedAt: new Date().toISOString(),
    activeWebSockets: 0,
    activeRecorderConnections: 0,
    recorders: new Map(),
    httpRequests: 0,
    socketIoEventsSeen: 0,
    sendDataEventsObserved: 0,
    sendDataBytesObserved: 0,
    lastSendDataObservedAt: null,
    socketIoParseFailures: 0,
    auditWriteFailures: 0,
    auditFileWriteFailures: 0,
    auditStdoutWriteFailures: 0,
    failureLogWriteFailures: 0,
    redisIpWriteFailures: 0,
    redisIpVerifyFailures: 0,
    redisIpVerifyMismatches: 0,
    sendDataThroughput: defaultThroughputStatus(),
    sendDataRawArchive: defaultRawArchiveStatus(),
    sendDataSpool: defaultSpoolStatus(),
    sendDataReplay: defaultReplayStatus(),
  };
}

function metricsSnapshot(metrics) {
  return {
    startedAt: metrics.startedAt,
    uptimeSeconds: uptimeSeconds(metrics.startedAt),
    activeWebSockets: metrics.activeWebSockets,
    activeRecorderConnections: metrics.activeRecorderConnections,
    recorders: Array.from(metrics.recorders.entries())
      .map(([vrcode, recorder]) => ({
        vrcode,
        activeConnections: recorder.activeConnections,
        selectedIp: recorder.selectedIp,
        ipSource: recorder.ipSource,
        lastSeenAt: recorder.lastSeenAt,
        sendDataEventsObserved: recorder.sendDataEventsObserved || 0,
        sendDataBytesObserved: recorder.sendDataBytesObserved || 0,
        lastSendDataObservedAt: recorder.lastSendDataObservedAt || null,
        rawArchive: recorderRawArchiveSnapshot(recorder.rawArchive || defaultRecorderRawArchiveStatus()),
        redisIpSync: recorder.redisIpSync || null,
        spool: recorderSpoolSnapshot(recorder.spool || defaultRecorderSpoolStatus()),
        replay: recorderReplaySnapshot(recorder.replay || defaultRecorderReplayStatus()),
      }))
      .sort((left, right) => left.vrcode.localeCompare(right.vrcode)),
    httpRequests: metrics.httpRequests,
    socketIoEventsSeen: metrics.socketIoEventsSeen,
    sendDataEventsObserved: metrics.sendDataEventsObserved,
    sendDataBytesObserved: metrics.sendDataBytesObserved,
    lastSendDataObservedAt: metrics.lastSendDataObservedAt,
    socketIoParseFailures: metrics.socketIoParseFailures,
    auditWriteFailures: metrics.auditWriteFailures,
    auditFileWriteFailures: metrics.auditFileWriteFailures,
    auditStdoutWriteFailures: metrics.auditStdoutWriteFailures,
    failureLogWriteFailures: metrics.failureLogWriteFailures,
    redisIpWriteFailures: metrics.redisIpWriteFailures,
    redisIpVerifyFailures: metrics.redisIpVerifyFailures,
    redisIpVerifyMismatches: metrics.redisIpVerifyMismatches,
    throughput: throughputSnapshot(metrics.sendDataThroughput),
    rawArchive: rawArchiveSnapshot(metrics.sendDataRawArchive),
    spool: spoolSnapshot(metrics.sendDataSpool),
    replay: replaySnapshot(metrics.sendDataReplay),
    realtimeCoverage: realtimeCoverageSnapshot(metrics.recorders),
  };
}

function uptimeSeconds(startedAt) {
  const started = Date.parse(startedAt);
  if (!Number.isFinite(started)) return 0;
  return Math.max(0, Math.floor((Date.now() - started) / 1000));
}

function configureSendDataSpool(metrics, config) {
  metrics.sendDataSpool.mode = config.mode;
  metrics.sendDataSpool.storage = config.storage || "redis_list";
  metrics.sendDataSpool.status = config.enabled ? "ready" : "disabled";
  metrics.sendDataReplay.status = config.replay && config.replay.enabled ? "idle" : "disabled";
  const adaptive = replayAdaptiveConfig(config.replay);
  const currentMaxBytes = adaptive.enabled
    ? clamp(config.replay ? config.replay.maxBytesPerSecond : 0, adaptive.minBytesPerSecond, adaptive.maxBytesPerSecond)
    : (config.replay ? config.replay.maxBytesPerSecond : 0);
  metrics.sendDataReplay.maxBytesPerSecond = currentMaxBytes;
  metrics.sendDataReplay.configuredMaxBytesPerSecond = config.replay ? config.replay.maxBytesPerSecond : 0;
  metrics.sendDataReplay.adaptive = {
    enabled: adaptive.enabled,
    minBytesPerSecond: adaptive.minBytesPerSecond,
    maxBytesPerSecond: adaptive.maxBytesPerSecond,
    currentMaxBytesPerSecond: currentMaxBytes,
    currentItemsPerTick: adaptive.enabled
      ? adaptive.maxItemsPerTick
      : (config.replay ? config.replay.batchSize : 0),
    minItemsPerTick: adaptive.minItemsPerTick,
    maxItemsPerTick: adaptive.maxItemsPerTick,
    minConcurrency: adaptive.minConcurrency,
    maxConcurrency: adaptive.maxConcurrency,
    currentConcurrency: adaptive.enabled ? adaptive.maxConcurrency : 1,
    lastDecision: adaptive.enabled ? "initialized" : "disabled",
    lastReason: adaptive.enabled ? "configured" : "adaptive_disabled",
    lastChangedAt: null,
    memoryGuardStatus: "unavailable",
  };
}

function configureSendDataRawArchive(metrics, config) {
  metrics.sendDataRawArchive.status = config && config.enabled ? "ready" : "disabled";
  metrics.sendDataRawArchive.path = config && config.path ? config.path : null;
  metrics.sendDataRawArchive.autoExport = metrics.sendDataRawArchive.autoExport || defaultRawArchiveAutoExportStatus();
  metrics.sendDataRawArchive.autoExport.status = config && config.autoExport && config.autoExport.enabled
    ? "idle"
    : "disabled";
}

function sendDataSpoolState(metrics) {
  const spool = metrics.sendDataSpool || defaultSpoolStatus();
  return {
    pendingItems: spool.pendingItems || 0,
    pendingBytes: spool.pendingBytes || 0,
  };
}

function recordRecorderJoin(metrics, context, vrcode, selectedIp) {
  if (!vrcode) return;
  if (context.metrics_vrcode && context.metrics_vrcode !== vrcode) {
    recordRecorderDisconnect(metrics, context);
  }

  if (!context.metrics_vrcode) {
    metrics.activeRecorderConnections += 1;
  }

  const recorder = metrics.recorders.get(vrcode) || defaultRecorderStatus();
  if (!context.metrics_vrcode) {
    recorder.activeConnections += 1;
  }
  recorder.selectedIp = selectedIp || recorder.selectedIp;
  recorder.ipSource = (context.ip && context.ip.selected_source) || recorder.ipSource;
  recorder.lastSeenAt = new Date().toISOString();
  metrics.recorders.set(vrcode, recorder);
  context.metrics_vrcode = vrcode;
}

function recordRecorderIpSync(metrics, vrcode, fields) {
  if (!vrcode) return;
  const recorder = metrics.recorders.get(vrcode) || defaultRecorderStatus();
  const current = recorder.redisIpSync || {};
  recorder.redisIpSync = {
    status: fields.status || current.status || "unknown",
    redisKey: fields.redisKey || current.redisKey || `ip_${vrcode}`,
    selectedIp: fields.selectedIp || current.selectedIp || recorder.selectedIp || "",
    ipSource: fields.ipSource || current.ipSource || recorder.ipSource || "",
    redisValue: Object.prototype.hasOwnProperty.call(fields, "redisValue")
      ? fields.redisValue
      : current.redisValue || null,
    lastWriteAt: fields.lastWriteAt || current.lastWriteAt || null,
    lastVerifiedAt: fields.lastVerifiedAt || current.lastVerifiedAt || null,
    lastFailure: Object.prototype.hasOwnProperty.call(fields, "lastFailure")
      ? fields.lastFailure
      : current.lastFailure || null,
  };
  metrics.recorders.set(vrcode, recorder);
}

function recordSendDataObserved(metrics, vrcode, payloadSummary) {
  const observedAt = new Date().toISOString();
  const bytes = Number.isFinite(payloadSummary && payloadSummary.bytes)
    ? payloadSummary.bytes
    : 0;
  metrics.sendDataEventsObserved += 1;
  metrics.sendDataBytesObserved += bytes;
  recordThroughputSample(metrics.sendDataThroughput, "observed", bytes);
  metrics.lastSendDataObservedAt = observedAt;
  if (!vrcode) return;

  const recorder = metrics.recorders.get(vrcode) || defaultRecorderStatus();
  recorder.sendDataEventsObserved = (recorder.sendDataEventsObserved || 0) + 1;
  recorder.sendDataBytesObserved = (recorder.sendDataBytesObserved || 0) + bytes;
  recorder.lastSendDataObservedAt = observedAt;
  recorder.lastSeenAt = observedAt;
  metrics.recorders.set(vrcode, recorder);
}

function recordSendDataSpoolAccepted(metrics, vrcode, payloadBytes) {
  const observedAt = new Date().toISOString();
  updateSpool(metrics.sendDataSpool, (spool) => {
    spool.acceptedEvents += 1;
    spool.lastAcceptedAt = observedAt;
  });
  updateRecorderSpool(metrics, vrcode, (spool) => {
    spool.acceptedEvents += 1;
    spool.lastAcceptedAt = observedAt;
  });
}

function recordSendDataSpoolSpooled(metrics, vrcode, payloadBytes, depth) {
  const observedAt = new Date().toISOString();
  const bytes = Number.isFinite(payloadBytes) ? payloadBytes : 0;
  const hasExplicitDepth = Number.isFinite(depth);
  updateSpool(metrics.sendDataSpool, (spool) => {
    spool.status = spool.status === "disabled" ? "disabled" : "ready";
    spool.spooledEvents += 1;
    spool.pendingItems = hasExplicitDepth ? depth : spool.pendingItems + 1;
    spool.pendingBytes += bytes;
    spool.oldestPendingAt = spool.oldestPendingAt || observedAt;
    spool.lastSpooledAt = observedAt;
  });
  recordThroughputSample(metrics.sendDataThroughput, "spooled", bytes);
  updateReplay(metrics.sendDataReplay, (replay) => {
    if (replay.status !== "disabled") {
      replay.pendingItems = hasExplicitDepth ? depth : replay.pendingItems + 1;
    }
  });
  updateRecorderSpool(metrics, vrcode, (spool) => {
    spool.spooledEvents += 1;
    spool.pendingItems += 1;
    spool.pendingBytes += bytes;
    spool.oldestPendingAt = spool.oldestPendingAt || observedAt;
    spool.lastSpooledAt = observedAt;
  });
  updateRecorderReplay(metrics, vrcode, (replay) => {
    if (metrics.sendDataReplay.status !== "disabled") replay.pendingItems += 1;
  });
}

function recordSendDataSpoolRejected(metrics, vrcode, reason, message) {
  const failure = failureRecord(reason, message);
  updateSpool(metrics.sendDataSpool, (spool) => {
    spool.status = spool.status === "failed" ? "failed" : "degraded";
    spool.rejectedEvents += 1;
    spool.lastFailure = failure;
  });
  updateRecorderSpool(metrics, vrcode, (spool) => {
    spool.rejectedEvents += 1;
    spool.lastFailure = failure;
  });
}

function recordSendDataSpoolWriteFailed(metrics, vrcode, reason, message) {
  const failure = failureRecord(reason, message);
  updateSpool(metrics.sendDataSpool, (spool) => {
    spool.status = "failed";
    spool.writeFailures += 1;
    spool.lastFailure = failure;
  });
  updateRecorderSpool(metrics, vrcode, (spool) => {
    spool.writeFailures += 1;
    spool.lastFailure = failure;
  });
}

function recordSendDataRawArchived(metrics, item, result) {
  const archivedAt = new Date().toISOString();
  const bytes = Number.isFinite(item && item.payloadBytes) ? item.payloadBytes : 0;
  const archive = metrics.sendDataRawArchive || defaultRawArchiveStatus();
  archive.status = archive.status === "disabled" ? "disabled" : "ready";
  archive.persistedEvents += 1;
  archive.persistedBytes += bytes;
  archive.lastArchivedAt = archivedAt;
  archive.lastArchiveId = result && result.archiveId ? result.archiveId : archive.lastArchiveId;
  archive.lastOffset = Number.isFinite(result && result.endOffset) ? result.endOffset : archive.lastOffset;
  metrics.sendDataRawArchive = archive;
  const vrcode = item && item.vrcode;
  if (vrcode) {
    const recorder = metrics.recorders.get(vrcode) || defaultRecorderStatus();
    const recorderArchive = recorder.rawArchive || defaultRecorderRawArchiveStatus();
    recorderArchive.persistedEvents += 1;
    recorderArchive.persistedBytes += bytes;
    recorderArchive.lastArchivedAt = archivedAt;
    recorderArchive.lastArchiveId = result && result.archiveId ? result.archiveId : recorderArchive.lastArchiveId;
    recorderArchive.lastOffset = Number.isFinite(result && result.endOffset) ? result.endOffset : recorderArchive.lastOffset;
    recorder.rawArchive = recorderArchive;
    metrics.recorders.set(vrcode, recorder);
  }
}

function recordSendDataRawArchiveWriteFailed(metrics, reason, message) {
  const archive = metrics.sendDataRawArchive || defaultRawArchiveStatus();
  archive.status = "failed";
  archive.writeFailures += 1;
  archive.lastFailure = failureRecord(reason, message);
  metrics.sendDataRawArchive = archive;
}

function recordSendDataReplayClaimFailed(metrics, reason, message) {
  const failure = failureRecord(reason, message);
  updateReplay(metrics.sendDataReplay, (replay) => {
    replay.status = "failed";
    replay.lastFailure = failure;
  });
}

function recordSendDataReplayStarted(metrics, vrcode, item) {
  const bytes = Number.isFinite(item && item.payloadBytes) ? item.payloadBytes : 0;
  updateSpool(metrics.sendDataSpool, (spool) => {
    spool.pendingItems = Math.max(0, spool.pendingItems - 1);
    spool.pendingBytes = Math.max(0, spool.pendingBytes - bytes);
    if (spool.pendingItems === 0) {
      spool.pendingBytes = 0;
      spool.oldestPendingAt = null;
    }
  });
  updateRecorderSpool(metrics, vrcode, (spool) => {
    spool.pendingItems = Math.max(0, spool.pendingItems - 1);
    spool.pendingBytes = Math.max(0, spool.pendingBytes - bytes);
    if (spool.pendingItems === 0) {
      spool.pendingBytes = 0;
      spool.oldestPendingAt = null;
    }
  });
  updateReplay(metrics.sendDataReplay, (replay) => {
    replay.status = "replaying";
    replay.inFlightItems += 1;
    replay.pendingItems = Math.max(0, replay.pendingItems - 1);
  });
  updateRecorderReplay(metrics, vrcode, (replay) => {
    replay.inFlightItems += 1;
    replay.pendingItems = Math.max(0, replay.pendingItems - 1);
  });
}

function recordSendDataReplayQueueDrained(metrics) {
  updateSpool(metrics.sendDataSpool, (spool) => {
    spool.pendingItems = 0;
    spool.pendingBytes = 0;
    spool.oldestPendingAt = null;
  });
  updateReplay(metrics.sendDataReplay, (replay) => {
    replay.pendingItems = 0;
  });

  for (const [vrcode, recorder] of metrics.recorders.entries()) {
    recorder.spool = recorder.spool || defaultRecorderSpoolStatus();
    recorder.replay = recorder.replay || defaultRecorderReplayStatus();
    recorder.spool.pendingItems = 0;
    recorder.spool.pendingBytes = 0;
    recorder.spool.oldestPendingAt = null;
    recorder.replay.pendingItems = 0;
    metrics.recorders.set(vrcode, recorder);
  }
}

function recordSendDataReplaySucceeded(metrics, vrcode, item) {
  const replayedAt = new Date().toISOString();
  const bytes = Number.isFinite(item && item.payloadBytes) ? item.payloadBytes : 0;
  recordThroughputSample(metrics.sendDataThroughput, "replayed", bytes);
  updateReplay(metrics.sendDataReplay, (replay) => {
    replay.status = "idle";
    replay.inFlightItems = Math.max(0, replay.inFlightItems - 1);
    replay.replayedEvents += 1;
    replay.lastReplayAt = replayedAt;
    replay.replayLagSeconds = replayLagSeconds(item && item.receivedAt, replayedAt);
  });
  updateRecorderReplay(metrics, vrcode, (replay) => {
    replay.inFlightItems = Math.max(0, replay.inFlightItems - 1);
    replay.replayedEvents += 1;
    replay.lastReplayAt = replayedAt;
    replay.replayLagSeconds = replayLagSeconds(item && item.receivedAt, replayedAt);
  });
}

function recordSendDataReplayRetryableFailed(metrics, vrcode, item, failure) {
  updateReplay(metrics.sendDataReplay, (replay) => {
    replay.status = "degraded";
    replay.inFlightItems = Math.max(0, replay.inFlightItems - 1);
    replay.pendingItems += 1;
    replay.retryableFailures += 1;
    replay.lastFailure = failure;
    replay.replayLagSeconds = replayLagSeconds(item && item.receivedAt);
  });
  updateRecorderReplay(metrics, vrcode, (replay) => {
    replay.inFlightItems = Math.max(0, replay.inFlightItems - 1);
    replay.pendingItems += 1;
    replay.retryableFailures += 1;
    replay.lastFailure = failure;
    replay.replayLagSeconds = replayLagSeconds(item && item.receivedAt);
  });
}

function recordSendDataReplayDeadLettered(metrics, vrcode, item, failure) {
  updateReplay(metrics.sendDataReplay, (replay) => {
    replay.status = "degraded";
    replay.inFlightItems = Math.max(0, replay.inFlightItems - 1);
    replay.deadLetteredEvents += 1;
    replay.lastFailure = failure;
    replay.replayLagSeconds = replayLagSeconds(item && item.receivedAt);
  });
  updateRecorderReplay(metrics, vrcode, (replay) => {
    replay.inFlightItems = Math.max(0, replay.inFlightItems - 1);
    replay.deadLetteredEvents += 1;
    replay.lastFailure = failure;
    replay.replayLagSeconds = replayLagSeconds(item && item.receivedAt);
  });
}

function recordSendDataReplayRateDecision(metrics, decision) {
  updateReplay(metrics.sendDataReplay, (replay) => {
    replay.maxBytesPerSecond = decision.maxBytesPerSecond;
    replay.adaptive = replay.adaptive || defaultReplayAdaptiveStatus();
    replay.adaptive.currentMaxBytesPerSecond = decision.maxBytesPerSecond;
    replay.adaptive.currentItemsPerTick = decision.itemsPerTick;
    replay.adaptive.currentConcurrency = decision.concurrency;
    replay.adaptive.lastDecision = decision.action;
    replay.adaptive.lastReason = decision.reason;
    replay.adaptive.lastChangedAt = new Date().toISOString();
    replay.adaptive.memoryGuardStatus = decision.memoryGuardStatus;
  });
}

function sendDataReplayRateState(metrics) {
  const replay = metrics.sendDataReplay || defaultReplayStatus();
  return {
    configuredMaxBytesPerSecond: replay.configuredMaxBytesPerSecond || replay.maxBytesPerSecond || 0,
    currentMaxBytesPerSecond: replay.maxBytesPerSecond || 0,
    currentItemsPerTick: replay.adaptive ? replay.adaptive.currentItemsPerTick : 0,
    currentConcurrency: replay.adaptive ? replay.adaptive.currentConcurrency : 0,
    adaptive: replay.adaptive || defaultReplayAdaptiveStatus(),
  };
}

function recordRecorderDisconnect(metrics, context) {
  const vrcode = context.metrics_vrcode;
  if (!vrcode) return;

  metrics.activeRecorderConnections = Math.max(0, metrics.activeRecorderConnections - 1);
  const recorder = metrics.recorders.get(vrcode);
  if (recorder) {
    recorder.activeConnections = Math.max(0, recorder.activeConnections - 1);
    recorder.lastSeenAt = new Date().toISOString();
    metrics.recorders.set(vrcode, recorder);
  }
  context.metrics_vrcode = null;
}

function updateRecorderSpool(metrics, vrcode, apply) {
  if (!vrcode) return;
  const recorder = metrics.recorders.get(vrcode) || defaultRecorderStatus();
  recorder.spool = recorder.spool || defaultRecorderSpoolStatus();
  updateSpool(recorder.spool, apply);
  recorder.lastSeenAt = new Date().toISOString();
  metrics.recorders.set(vrcode, recorder);
}

function updateSpool(spool, apply) {
  apply(spool);
}

function updateRecorderReplay(metrics, vrcode, apply) {
  if (!vrcode) return;
  const recorder = metrics.recorders.get(vrcode) || defaultRecorderStatus();
  recorder.replay = recorder.replay || defaultRecorderReplayStatus();
  updateReplay(recorder.replay, apply);
  recorder.lastSeenAt = new Date().toISOString();
  metrics.recorders.set(vrcode, recorder);
}

function updateReplay(replay, apply) {
  apply(replay);
}

function recordThroughputSample(throughput, key, bytes) {
  const boundedBytes = Number.isFinite(bytes) ? Math.max(0, bytes) : 0;
  const samples = throughput[key] || [];
  samples.push({ observedAtMs: Date.now(), bytes: boundedBytes });
  throughput[key] = pruneThroughputSamples(samples, throughput.windowSeconds);
}

function throughputSnapshot(throughput) {
  const windowSeconds = throughput.windowSeconds || 10;
  const observed = bytesPerSecond(throughput.observed, windowSeconds);
  const spooled = bytesPerSecond(throughput.spooled, windowSeconds);
  const replayed = bytesPerSecond(throughput.replayed, windowSeconds);
  return {
    windowSeconds,
    observedBytesPerSecond: observed,
    spooledBytesPerSecond: spooled,
    replayedBytesPerSecond: replayed,
    queueGrowthBytesPerSecond: spooled - replayed,
  };
}

function bytesPerSecond(samples, windowSeconds) {
  const pruned = pruneThroughputSamples(samples || [], windowSeconds);
  const bytes = pruned.reduce((total, sample) => total + sample.bytes, 0);
  return bytes / Math.max(windowSeconds, 1);
}

function pruneThroughputSamples(samples, windowSeconds) {
  const cutoff = Date.now() - Math.max(windowSeconds, 1) * 1000;
  return samples.filter((sample) => sample.observedAtMs >= cutoff);
}

function spoolSnapshot(spool) {
  return {
    mode: spool.mode,
    status: spool.status,
    storage: spool.storage,
    acceptedEvents: spool.acceptedEvents,
    spooledEvents: spool.spooledEvents,
    skippedRealtimeEvents: spool.skippedRealtimeEvents,
    rejectedEvents: spool.rejectedEvents,
    writeFailures: spool.writeFailures,
    pendingItems: spool.pendingItems,
    pendingBytes: spool.pendingBytes,
    oldestPendingAgeSeconds: oldestPendingAgeSeconds(spool.oldestPendingAt),
    lastAcceptedAt: spool.lastAcceptedAt,
    lastSpooledAt: spool.lastSpooledAt,
    lastFailure: spool.lastFailure,
  };
}

function recorderSpoolSnapshot(spool) {
  return {
    acceptedEvents: spool.acceptedEvents,
    spooledEvents: spool.spooledEvents,
    skippedRealtimeEvents: spool.skippedRealtimeEvents,
    rejectedEvents: spool.rejectedEvents,
    writeFailures: spool.writeFailures,
    pendingItems: spool.pendingItems,
    pendingBytes: spool.pendingBytes,
    oldestPendingAgeSeconds: oldestPendingAgeSeconds(spool.oldestPendingAt),
    lastAcceptedAt: spool.lastAcceptedAt,
    lastSpooledAt: spool.lastSpooledAt,
    lastFailure: spool.lastFailure,
  };
}

function replaySnapshot(replay) {
  return {
    status: replay.status,
    pendingItems: replay.pendingItems,
    inFlightItems: replay.inFlightItems,
    replayedEvents: replay.replayedEvents,
    retryableFailures: replay.retryableFailures,
    deadLetteredEvents: replay.deadLetteredEvents,
    replayLagSeconds: replay.replayLagSeconds,
    maxBytesPerSecond: replay.maxBytesPerSecond,
    configuredMaxBytesPerSecond: replay.configuredMaxBytesPerSecond,
    adaptive: replay.adaptive,
    lastReplayAt: replay.lastReplayAt,
    lastFailure: replay.lastFailure,
  };
}

function rawArchiveSnapshot(archive) {
  return {
    status: archive.status,
    path: archive.path,
    persistedEvents: archive.persistedEvents,
    persistedBytes: archive.persistedBytes,
    writeFailures: archive.writeFailures,
    lastArchivedAt: archive.lastArchivedAt,
    lastArchiveId: archive.lastArchiveId,
    lastOffset: archive.lastOffset,
    lastFailure: archive.lastFailure,
    autoExport: archive.autoExport || defaultRawArchiveAutoExportStatus(),
  };
}

function recordSendDataRawArchiveAutoExportDecision(metrics, decision) {
  const archive = metrics.sendDataRawArchive || defaultRawArchiveStatus();
  const autoExport = archive.autoExport || defaultRawArchiveAutoExportStatus();
  autoExport.status = decision.state || autoExport.status;
  autoExport.finalizable = Boolean(decision.finalizable);
  autoExport.reasons = Array.isArray(decision.reasons) ? decision.reasons : [];
  autoExport.archivePath = decision.archivePath || autoExport.archivePath || null;
  autoExport.archiveCursor = Number.isFinite(decision.archiveCursor) ? decision.archiveCursor : autoExport.archiveCursor;
  autoExport.cursorStableForMs = Number.isFinite(decision.cursorStableForMs)
    ? decision.cursorStableForMs
    : autoExport.cursorStableForMs;
  autoExport.lastDecisionAt = new Date().toISOString();
  archive.autoExport = autoExport;
  metrics.sendDataRawArchive = archive;
}

function recordSendDataRawArchiveAutoExportStarted(metrics, job) {
  const archive = metrics.sendDataRawArchive || defaultRawArchiveStatus();
  const autoExport = archive.autoExport || defaultRawArchiveAutoExportStatus();
  autoExport.status = "running";
  autoExport.activeJob = rawArchiveAutoExportJobSnapshot(job);
  autoExport.lastDecisionAt = new Date().toISOString();
  archive.autoExport = autoExport;
  metrics.sendDataRawArchive = archive;
}

function recordSendDataRawArchiveAutoExportSucceeded(metrics, job, result) {
  const archive = metrics.sendDataRawArchive || defaultRawArchiveStatus();
  const autoExport = archive.autoExport || defaultRawArchiveAutoExportStatus();
  autoExport.status = "uploaded";
  autoExport.finalizable = false;
  autoExport.reasons = [];
  autoExport.activeJob = null;
  autoExport.uploadedJobs += 1;
  autoExport.lastResult = result || null;
  autoExport.lastDecisionAt = new Date().toISOString();
  archive.autoExport = autoExport;
  metrics.sendDataRawArchive = archive;
}

function recordSendDataRawArchiveAutoExportFailed(metrics, job, reason, message) {
  const archive = metrics.sendDataRawArchive || defaultRawArchiveStatus();
  const autoExport = archive.autoExport || defaultRawArchiveAutoExportStatus();
  autoExport.status = job && job.state ? job.state : "failed";
  autoExport.activeJob = job ? rawArchiveAutoExportJobSnapshot(job) : autoExport.activeJob;
  autoExport.failedJobs += 1;
  autoExport.lastFailure = failureRecord(reason, message);
  autoExport.lastDecisionAt = new Date().toISOString();
  archive.autoExport = autoExport;
  metrics.sendDataRawArchive = archive;
}

function rawArchiveAutoExportJobSnapshot(job) {
  return {
    jobId: job.jobId,
    requestId: job.requestId,
    trigger: job.trigger,
    vrcode: job.vrcode,
    archivePath: job.archivePath,
    startOffset: job.startOffset,
    endOffset: job.endOffset,
    state: job.state,
    attempts: job.attempts,
    maxAttempts: job.maxAttempts,
    createdAt: job.createdAt,
    updatedAt: job.updatedAt,
    startedAt: job.startedAt,
    completedAt: job.completedAt,
    nextAttemptAt: job.nextAttemptAt,
    lastFailure: job.lastFailure,
  };
}

function realtimeCoverageSnapshot(recorders) {
  const windowSeconds = 60;
  return decideSendDataRealtimeCoverage({
    recorders: Array.from(recorders.entries()).map(([vrcode, recorder]) => ({
      vrcode,
      activeConnections: recorder.activeConnections,
      sendDataEventsObserved: recorder.sendDataEventsObserved || 0,
      replayedEvents: recorder.replay && recorder.replay.replayedEvents ? recorder.replay.replayedEvents : 0,
      lastReplayAt: recorder.replay && recorder.replay.lastReplayAt ? recorder.replay.lastReplayAt : null,
    })),
    nowMs: Date.now(),
    windowSeconds,
  });
}

function recordSendDataRealtimeSkipped(metrics, result) {
  const skippedRealtimeItems = positiveInteger(result && result.skippedRealtimeItems, 0);
  const skippedRealtimeBytes = positiveInteger(result && result.skippedRealtimeBytes, 0);
  if (skippedRealtimeItems === 0) return;
  const skippedAt = new Date().toISOString();

  updateSpool(metrics.sendDataSpool, (spool) => {
    spool.skippedRealtimeEvents += skippedRealtimeItems;
    spool.pendingItems = Math.max(0, spool.pendingItems - skippedRealtimeItems);
    spool.pendingBytes = Math.max(0, spool.pendingBytes - skippedRealtimeBytes);
    if (spool.pendingItems === 0) {
      spool.pendingBytes = 0;
      spool.oldestPendingAt = null;
    } else {
      spool.oldestPendingAt = skippedAt;
    }
  });
  updateReplay(metrics.sendDataReplay, (replay) => {
    replay.pendingItems = Math.max(0, replay.pendingItems - skippedRealtimeItems);
  });

  const byRecorder = result && result.skippedRealtimeByRecorder && typeof result.skippedRealtimeByRecorder === "object"
    ? result.skippedRealtimeByRecorder
    : {};
  for (const [vrcode, skipped] of Object.entries(byRecorder)) {
    const skippedRecord = skipped as { items?: number; bytes?: number };
    const recorderSkippedItems = positiveInteger(skippedRecord && skippedRecord.items, 0);
    const recorderSkippedBytes = positiveInteger(skippedRecord && skippedRecord.bytes, 0);
    updateRecorderSpool(metrics, vrcode, (spool) => {
      spool.skippedRealtimeEvents += recorderSkippedItems;
      spool.pendingItems = Math.max(0, spool.pendingItems - recorderSkippedItems);
      spool.pendingBytes = Math.max(0, spool.pendingBytes - recorderSkippedBytes);
      if (spool.pendingItems === 0) {
        spool.pendingBytes = 0;
        spool.oldestPendingAt = null;
      } else {
        spool.oldestPendingAt = skippedAt;
      }
    });
    updateRecorderReplay(metrics, vrcode, (replay) => {
      replay.pendingItems = Math.max(0, replay.pendingItems - recorderSkippedItems);
    });
  }
}

function recorderReplaySnapshot(replay) {
  return {
    pendingItems: replay.pendingItems,
    inFlightItems: replay.inFlightItems,
    replayedEvents: replay.replayedEvents,
    retryableFailures: replay.retryableFailures,
    deadLetteredEvents: replay.deadLetteredEvents,
    replayLagSeconds: replay.replayLagSeconds,
    lastReplayAt: replay.lastReplayAt,
    lastFailure: replay.lastFailure,
  };
}

function recorderRawArchiveSnapshot(archive) {
  return {
    persistedEvents: archive.persistedEvents,
    persistedBytes: archive.persistedBytes,
    lastArchivedAt: archive.lastArchivedAt,
    lastArchiveId: archive.lastArchiveId,
    lastOffset: archive.lastOffset,
  };
}

function oldestPendingAgeSeconds(oldestPendingAt) {
  if (!oldestPendingAt) return null;
  const oldest = Date.parse(oldestPendingAt);
  if (!Number.isFinite(oldest)) return null;
  return Math.max(0, Math.floor((Date.now() - oldest) / 1000));
}

function replayLagSeconds(receivedAt, replayedAt = new Date().toISOString()) {
  if (!receivedAt) return null;
  const received = Date.parse(receivedAt);
  const replayed = Date.parse(replayedAt);
  if (!Number.isFinite(received) || !Number.isFinite(replayed)) return null;
  return Math.max(0, Math.floor((replayed - received) / 1000));
}

function failureRecord(reason, message) {
  return {
    reason,
    message,
    occurredAt: new Date().toISOString(),
  };
}

function defaultRecorderStatus() {
  return {
    activeConnections: 0,
    selectedIp: "",
    ipSource: "",
    lastSeenAt: "",
    sendDataEventsObserved: 0,
    sendDataBytesObserved: 0,
    lastSendDataObservedAt: null,
    rawArchive: defaultRecorderRawArchiveStatus(),
    redisIpSync: null,
    spool: defaultRecorderSpoolStatus(),
    replay: defaultRecorderReplayStatus(),
  };
}

function defaultRecorderRawArchiveStatus() {
  return {
    persistedEvents: 0,
    persistedBytes: 0,
    lastArchivedAt: null,
    lastArchiveId: null,
    lastOffset: null,
  };
}

function defaultSpoolStatus() {
  return {
    mode: "passthrough",
    status: "disabled",
    storage: "redis_list",
    acceptedEvents: 0,
    spooledEvents: 0,
    skippedRealtimeEvents: 0,
    rejectedEvents: 0,
    writeFailures: 0,
    pendingItems: 0,
    pendingBytes: 0,
    oldestPendingAt: null,
    lastAcceptedAt: null,
    lastSpooledAt: null,
    lastFailure: null,
  };
}

function defaultRawArchiveStatus() {
  return {
    status: "disabled",
    path: null,
    persistedEvents: 0,
    persistedBytes: 0,
    writeFailures: 0,
    lastArchivedAt: null,
    lastArchiveId: null,
    lastOffset: null,
    lastFailure: null,
    autoExport: defaultRawArchiveAutoExportStatus(),
  };
}

function defaultRawArchiveAutoExportStatus() {
  return {
    status: "disabled",
    finalizable: false,
    reasons: [],
    archivePath: null,
    archiveCursor: null,
    cursorStableForMs: null,
    lastDecisionAt: null,
    activeJob: null,
    uploadedJobs: 0,
    failedJobs: 0,
    lastResult: null,
    lastFailure: null,
  };
}

function defaultThroughputStatus() {
  return {
    windowSeconds: 10,
    observed: [],
    spooled: [],
    replayed: [],
  };
}

function defaultReplayStatus() {
  return {
    status: "disabled",
    pendingItems: 0,
    inFlightItems: 0,
    replayedEvents: 0,
    retryableFailures: 0,
    deadLetteredEvents: 0,
    replayLagSeconds: null,
    maxBytesPerSecond: 0,
    configuredMaxBytesPerSecond: 0,
    adaptive: defaultReplayAdaptiveStatus(),
    lastReplayAt: null,
    lastFailure: null,
  };
}

function defaultReplayAdaptiveStatus() {
  return {
    enabled: false,
    minBytesPerSecond: 0,
    maxBytesPerSecond: 0,
    currentMaxBytesPerSecond: 0,
    minItemsPerTick: 0,
    maxItemsPerTick: 0,
    currentItemsPerTick: 0,
    minConcurrency: 0,
    maxConcurrency: 0,
    currentConcurrency: 0,
    lastDecision: "disabled",
    lastReason: "adaptive_disabled",
    lastChangedAt: null,
    memoryGuardStatus: "unavailable",
  };
}

function replayAdaptiveConfig(replayConfig) {
  const configuredRate = replayConfig ? replayConfig.maxBytesPerSecond : 0;
  const adaptive = (replayConfig && replayConfig.adaptive) || {};
  const enabled = Boolean(adaptive.enabled);
  const minBytesPerSecond = positiveInteger(adaptive.minBytesPerSecond, 1);
  const maxBytesPerSecond = Math.max(
    minBytesPerSecond,
    positiveInteger(adaptive.maxBytesPerSecond, configuredRate || minBytesPerSecond)
  );
  const minItemsPerTick = positiveInteger(adaptive.minItemsPerTick, 50);
  const maxItemsPerTick = Math.max(minItemsPerTick, positiveInteger(adaptive.maxItemsPerTick, 1000));
  const minConcurrency = positiveInteger(adaptive.minConcurrency, 1);
  const maxConcurrency = Math.max(minConcurrency, positiveInteger(adaptive.maxConcurrency, 8));
  return {
    enabled,
    minBytesPerSecond,
    maxBytesPerSecond,
    minItemsPerTick,
    maxItemsPerTick,
    minConcurrency,
    maxConcurrency,
  };
}

function positiveInteger(value, fallback) {
  return Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

function clamp(value, min, max) {
  const number = Number.isFinite(value) ? value : min;
  return Math.min(max, Math.max(min, Math.floor(number)));
}

function defaultRecorderSpoolStatus() {
  return {
    acceptedEvents: 0,
    spooledEvents: 0,
    skippedRealtimeEvents: 0,
    rejectedEvents: 0,
    writeFailures: 0,
    pendingItems: 0,
    pendingBytes: 0,
    oldestPendingAt: null,
    lastAcceptedAt: null,
    lastSpooledAt: null,
    lastFailure: null,
  };
}

function defaultRecorderReplayStatus() {
  return {
    pendingItems: 0,
    inFlightItems: 0,
    replayedEvents: 0,
    retryableFailures: 0,
    deadLetteredEvents: 0,
    replayLagSeconds: null,
    lastReplayAt: null,
    lastFailure: null,
  };
}

module.exports = {
  configureSendDataRawArchive,
  configureSendDataSpool,
  createMetrics,
  metricsSnapshot,
  recordSendDataRawArchived,
  recordSendDataRawArchiveWriteFailed,
  recordSendDataRawArchiveAutoExportDecision,
  recordSendDataRawArchiveAutoExportFailed,
  recordSendDataRawArchiveAutoExportStarted,
  recordSendDataRawArchiveAutoExportSucceeded,
  recordSendDataSpoolAccepted,
  recordSendDataRealtimeSkipped,
  recordSendDataSpoolRejected,
  recordSendDataSpoolSpooled,
  recordSendDataSpoolWriteFailed,
  recordSendDataReplayClaimFailed,
  recordSendDataReplayDeadLettered,
  recordSendDataReplayQueueDrained,
  recordSendDataReplayRetryableFailed,
  recordSendDataReplayRateDecision,
  recordSendDataReplayStarted,
  recordSendDataReplaySucceeded,
  recordRecorderJoin,
  recordRecorderIpSync,
  recordSendDataObserved,
  recordRecorderDisconnect,
  sendDataReplayRateState,
  sendDataSpoolState,
};

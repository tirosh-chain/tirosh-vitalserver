"use strict";

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
    redisIpWriteFailures: 0,
    redisIpVerifyFailures: 0,
    redisIpVerifyMismatches: 0,
    sendDataThroughput: defaultThroughputStatus(),
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
    redisIpWriteFailures: metrics.redisIpWriteFailures,
    redisIpVerifyFailures: metrics.redisIpVerifyFailures,
    redisIpVerifyMismatches: metrics.redisIpVerifyMismatches,
    throughput: throughputSnapshot(metrics.sendDataThroughput),
    spool: spoolSnapshot(metrics.sendDataSpool),
    replay: replaySnapshot(metrics.sendDataReplay),
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
    lastDecision: adaptive.enabled ? "initialized" : "disabled",
    lastReason: adaptive.enabled ? "configured" : "adaptive_disabled",
    lastChangedAt: null,
    memoryGuardStatus: "unavailable",
  };
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
  updateSpool(metrics.sendDataSpool, (spool) => {
    spool.status = spool.status === "disabled" ? "disabled" : "ready";
    spool.spooledEvents += 1;
    spool.pendingItems = Number.isFinite(depth) ? depth : spool.pendingItems + 1;
    spool.pendingBytes += bytes;
    spool.oldestPendingAt = spool.oldestPendingAt || observedAt;
    spool.lastSpooledAt = observedAt;
  });
  recordThroughputSample(metrics.sendDataThroughput, "spooled", bytes);
  updateReplay(metrics.sendDataReplay, (replay) => {
    if (replay.status !== "disabled") replay.pendingItems += 1;
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
    if (spool.pendingItems === 0) spool.oldestPendingAt = null;
  });
  updateRecorderSpool(metrics, vrcode, (spool) => {
    spool.pendingItems = Math.max(0, spool.pendingItems - 1);
    spool.pendingBytes = Math.max(0, spool.pendingBytes - bytes);
    if (spool.pendingItems === 0) spool.oldestPendingAt = null;
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
    replay.adaptive.lastDecision = decision.action;
    replay.adaptive.lastReason = decision.reason;
    replay.adaptive.lastChangedAt = new Date().toISOString();
  });
}

function sendDataReplayRateState(metrics) {
  const replay = metrics.sendDataReplay || defaultReplayStatus();
  return {
    configuredMaxBytesPerSecond: replay.configuredMaxBytesPerSecond || replay.maxBytesPerSecond || 0,
    currentMaxBytesPerSecond: replay.maxBytesPerSecond || 0,
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
    redisIpSync: null,
    spool: defaultRecorderSpoolStatus(),
    replay: defaultRecorderReplayStatus(),
  };
}

function defaultSpoolStatus() {
  return {
    mode: "passthrough",
    status: "disabled",
    storage: "redis_list",
    acceptedEvents: 0,
    spooledEvents: 0,
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
  return {
    enabled,
    minBytesPerSecond,
    maxBytesPerSecond,
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
  configureSendDataSpool,
  createMetrics,
  metricsSnapshot,
  recordSendDataSpoolAccepted,
  recordSendDataSpoolRejected,
  recordSendDataSpoolSpooled,
  recordSendDataSpoolWriteFailed,
  recordSendDataReplayClaimFailed,
  recordSendDataReplayDeadLettered,
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

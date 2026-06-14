"use strict";

function createMetrics() {
  return {
    startedAt: new Date().toISOString(),
    activeWebSockets: 0,
    activeRecorderConnections: 0,
    recorders: new Map(),
    httpRequests: 0,
    socketIoEventsSeen: 0,
    socketIoParseFailures: 0,
    auditWriteFailures: 0,
    auditFileWriteFailures: 0,
    auditStdoutWriteFailures: 0,
    redisIpWriteFailures: 0,
    redisIpVerifyFailures: 0,
    redisIpVerifyMismatches: 0,
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
        redisIpSync: recorder.redisIpSync || null,
      }))
      .sort((left, right) => left.vrcode.localeCompare(right.vrcode)),
    httpRequests: metrics.httpRequests,
    socketIoEventsSeen: metrics.socketIoEventsSeen,
    socketIoParseFailures: metrics.socketIoParseFailures,
    auditWriteFailures: metrics.auditWriteFailures,
    auditFileWriteFailures: metrics.auditFileWriteFailures,
    auditStdoutWriteFailures: metrics.auditStdoutWriteFailures,
    redisIpWriteFailures: metrics.redisIpWriteFailures,
    redisIpVerifyFailures: metrics.redisIpVerifyFailures,
    redisIpVerifyMismatches: metrics.redisIpVerifyMismatches,
  };
}

function uptimeSeconds(startedAt) {
  const started = Date.parse(startedAt);
  if (!Number.isFinite(started)) return 0;
  return Math.max(0, Math.floor((Date.now() - started) / 1000));
}

function recordRecorderJoin(metrics, context, vrcode, selectedIp) {
  if (!vrcode) return;
  if (context.metrics_vrcode && context.metrics_vrcode !== vrcode) {
    recordRecorderDisconnect(metrics, context);
  }

  if (!context.metrics_vrcode) {
    metrics.activeRecorderConnections += 1;
  }

  const recorder = metrics.recorders.get(vrcode) || {
    activeConnections: 0,
    selectedIp: "",
    ipSource: "",
    lastSeenAt: "",
    redisIpSync: null,
  };
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
  const recorder = metrics.recorders.get(vrcode) || {
    activeConnections: 0,
    selectedIp: "",
    ipSource: "",
    lastSeenAt: "",
    redisIpSync: null,
  };
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

module.exports = {
  createMetrics,
  metricsSnapshot,
  recordRecorderJoin,
  recordRecorderIpSync,
  recordRecorderDisconnect,
};

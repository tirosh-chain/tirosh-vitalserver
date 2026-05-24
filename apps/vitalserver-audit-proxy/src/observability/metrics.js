"use strict";

function createMetrics() {
  return {
    activeWebSockets: 0,
    httpRequests: 0,
    socketIoEventsSeen: 0,
    socketIoParseFailures: 0,
    auditWriteFailures: 0,
    auditFileWriteFailures: 0,
    redisIpWriteFailures: 0,
  };
}

function metricsSnapshot(metrics) {
  return {
    activeWebSockets: metrics.activeWebSockets,
    httpRequests: metrics.httpRequests,
    socketIoEventsSeen: metrics.socketIoEventsSeen,
    socketIoParseFailures: metrics.socketIoParseFailures,
    auditWriteFailures: metrics.auditWriteFailures,
    auditFileWriteFailures: metrics.auditFileWriteFailures,
    redisIpWriteFailures: metrics.redisIpWriteFailures,
  };
}

module.exports = { createMetrics, metricsSnapshot };

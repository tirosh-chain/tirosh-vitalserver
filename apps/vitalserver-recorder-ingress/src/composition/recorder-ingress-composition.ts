"use strict";

const { createRecorderIngressHttpServer } = require("../adapters/inbound/http/proxy-server");
const { createClientIpSelector } = require("../adapters/inbound/http/client-ip");
const { createAuditLogWriter } = require("../adapters/outbound/file/audit-log-writer");
const { createAuditStdoutWriter } = require("../adapters/outbound/process/audit-stdout-writer");
const { createRuntimeStateMemoryGuardReader } = require("../adapters/outbound/file/runtime-state-memory-guard-reader");
const { createRedisAuditEventStore } = require("../adapters/outbound/redis/audit-event-store");
const { createRedisClient } = require("../adapters/outbound/redis/client");
const { createRedisSendDataSpoolStore } = require("../adapters/outbound/redis/send-data-spool-store");
const { createVrIdentityStore } = require("../adapters/outbound/redis/vr-identity-store");
const { createSocketIoSendDataReplayTarget } = require("../adapters/outbound/socketio/send-data-replay-target");
const { createAuditRecorder } = require("../application/audit-recorder");
const { createSendDataIngressService } = require("../application/send-data-ingress-service");
const { createSendDataReplayWorker } = require("../application/send-data-replay-worker");
const { createSocketIoAuditService } = require("../application/socketio-audit-service");
const { configureSendDataSpool, createMetrics } = require("../observability/metrics");

function createRecorderIngressServer(config) {
  const metrics = createMetrics();
  configureSendDataSpool(metrics, config.spool);

  const sendDataRedis = createRedisClient(config.redis);
  const auditRedis = createRedisClient(config.redis);
  const identityRedis = createRedisClient(config.redis);
  const auditLog = createAuditLogWriter(config.audit.log, metrics);
  const auditStdout = createAuditStdoutWriter(config.audit.stdout, metrics);
  const redisAudit = createRedisAuditEventStore(config.audit, auditRedis, metrics);
  const audit = createAuditRecorder(config.audit, [auditLog, auditStdout, redisAudit]);
  const vrIdentityStore = createVrIdentityStore(identityRedis, metrics);
  const sendDataSpoolStore = createRedisSendDataSpoolStore(config.spool, sendDataRedis);
  const sendDataIngress = createSendDataIngressService({
    config,
    metrics,
    spoolStore: sendDataSpoolStore,
  });
  const sendDataReplayWorker = createSendDataReplayWorker({
    config: config.spool,
    metrics,
    memoryGuard: createRuntimeStateMemoryGuardReader(config.memoryGuard),
    spoolStore: sendDataSpoolStore,
    replayTarget: createSocketIoSendDataReplayTarget(config),
  });
  const clientIp = createClientIpSelector(config.clientIp);
  const socketIoAudit = createSocketIoAuditService({ audit, vrIdentityStore, metrics, config, sendDataIngress });

  return createRecorderIngressHttpServer({
    audit,
    clientIp,
    config,
    metrics,
    sendDataReplayWorker,
    socketIoAudit,
  });
}

module.exports = { createRecorderIngressServer };

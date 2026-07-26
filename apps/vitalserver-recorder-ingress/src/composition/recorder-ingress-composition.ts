"use strict";

const { createRecorderIngressHttpServer } = require("../adapters/inbound/http/proxy-server");
const { createClientIpSelector } = require("../adapters/inbound/http/client-ip");
const { createAuditLogWriter } = require("../adapters/outbound/file/audit-log-writer");
const { createAuditStdoutWriter } = require("../adapters/outbound/process/audit-stdout-writer");
const { createSendDataFailureLogWriter } = require("../adapters/outbound/file/send-data-failure-log-writer");
const { createSendDataRawArchiveExportJobStore } = require("../adapters/outbound/file/send-data-raw-archive-export-job-store");
const { createSendDataRawArchiveWriter } = require("../adapters/outbound/file/send-data-raw-archive-writer");
const { createNativeVitalUploadRegistry } = require("../adapters/outbound/file/native-vital-upload-registry");
const { createRecorderObservabilityRepository } = require("../adapters/outbound/postgres/recorder-observability-repository");
const { createRecorderObservabilitySchemaRegistry } = require("../adapters/outbound/schema/recorder-observability-schema-registry");
const { createRawArchiveExporter } = require("../adapters/outbound/http/raw-archive-recovery-executor");
const { createVitalServerFileIndex } = require("../adapters/outbound/http/vitalserver-file-index");
const { createRedisAuditEventStore } = require("../adapters/outbound/redis/audit-event-store");
const { createRedisClient } = require("../adapters/outbound/redis/client");
const { createRedisSendDataSpoolStore } = require("../adapters/outbound/redis/send-data-spool-store");
const { createVrIdentityStore } = require("../adapters/outbound/redis/vr-identity-store");
const { createSocketIoSendDataReplayTarget } = require("../adapters/outbound/socketio/send-data-replay-target");
const { createAuditRecorder } = require("../application/audit-recorder");
const { createSendDataIngressService } = require("../application/send-data-ingress-service");
const { createSendDataRawArchiveExportWorker } = require("../application/send-data-raw-archive-export-worker");
const { createSendDataReplayWorker } = require("../application/send-data-replay-worker");
const { createNativeVitalUploadService } = require("../application/native-vital-upload-service");
const { createRecorderObservabilityIngressService } = require("../application/recorder-observability-ingress-service");
const { createRecorderObservabilityProjector } = require("../application/recorder-observability-projector");
const { createSocketIoAuditService } = require("../application/socketio-audit-service");
const { configureSendDataRawArchive, configureSendDataSpool, createMetrics } = require("../observability/metrics");

function createRecorderIngressServer(config) {
  const metrics = createMetrics();
  configureSendDataSpool(metrics, config.spool);
  configureSendDataRawArchive(metrics, config.rawArchive);

  const sendDataRedis = createRedisClient(config.redis);
  const auditRedis = createRedisClient(config.redis);
  const identityRedis = createRedisClient(config.redis);
  const auditLog = createAuditLogWriter(config.audit.log, metrics);
  const auditStdout = createAuditStdoutWriter(config.audit.stdout, metrics);
  const redisAudit = createRedisAuditEventStore(config.audit, auditRedis, metrics);
  const sendDataFailureLog = createSendDataFailureLogWriter(config.failureLog, metrics);
  const sendDataRawArchive = createSendDataRawArchiveWriter(config.rawArchive);
  const sendDataRawArchiveExportJobStore = createSendDataRawArchiveExportJobStore(config);
  const sendDataRawArchiveExporter = createRawArchiveExporter(config);
  const nativeVitalUploadRegistry = createNativeVitalUploadRegistry(
    config.nativeVitalUploads
  );
  const nativeVitalUploads = createNativeVitalUploadService({
    registry: nativeVitalUploadRegistry,
    vitalServerIndex: createVitalServerFileIndex(
      config.nativeVitalUploads.vitalServerIndex
    ),
    reconciliation: config.nativeVitalUploads.reconciliation,
  });
  const recorderObservabilityRepository = config.observability.enabled
    ? createRecorderObservabilityRepository({
      ...config.observability.database,
      freshnessToleranceMultiplier:
        config.observability.freshnessToleranceMultiplier,
      freshnessAllowanceSeconds:
        config.observability.freshnessAllowanceSeconds,
      firstReportGraceSeconds:
        config.observability.firstReportGraceSeconds,
    })
    : undefined;
  const recorderObservability = recorderObservabilityRepository
    ? createRecorderObservabilityIngressService({
      repository: recorderObservabilityRepository,
      schemas: createRecorderObservabilitySchemaRegistry(),
    })
    : undefined;
  const recorderObservabilityProjector = recorderObservabilityRepository
    ? createRecorderObservabilityProjector({
      repository: recorderObservabilityRepository,
      ...config.observability.projector,
    })
    : undefined;
  const audit = createAuditRecorder(config.audit, [auditLog, auditStdout, redisAudit]);
  const vrIdentityStore = createVrIdentityStore(identityRedis, metrics);
  const sendDataSpoolStore = createRedisSendDataSpoolStore(config.spool, sendDataRedis);
  const sendDataIngress = createSendDataIngressService({
    config,
    failureSink: sendDataFailureLog,
    metrics,
    rawArchive: sendDataRawArchive,
    spoolStore: sendDataSpoolStore,
  });
  const sendDataReplayWorker = createSendDataReplayWorker({
    config: config.spool,
    failureSink: sendDataFailureLog,
    metrics,
    memoryGuard: undefined,
    spoolStore: sendDataSpoolStore,
    replayTarget: createSocketIoSendDataReplayTarget(config),
  });
  const sendDataRawArchiveExportWorker = createSendDataRawArchiveExportWorker({
    config,
    exporter: sendDataRawArchiveExporter,
    jobStore: sendDataRawArchiveExportJobStore,
    metrics,
  });
  const clientIp = createClientIpSelector(config.clientIp);
  const socketIoAudit = createSocketIoAuditService({ audit, vrIdentityStore, metrics, config, sendDataIngress });

  return createRecorderIngressHttpServer({
    audit,
    clientIp,
    config,
    metrics,
    nativeVitalUploads,
    recorderObservability,
    recorderObservabilityProjector,
    recorderObservabilityRepository,
    sendDataRawArchiveExportWorker,
    sendDataReplayWorker,
    socketIoAudit,
  });
}

module.exports = { createRecorderIngressServer };

import { z } from "zod";

import { runtimeEventTypeValues } from "@/domain/runtime-control/contracts/runtimeEventTypes";

const nullableString = z.string().nullable().optional();
const nullableNumber = z.number().nullable().optional();
const nullableBoolean = z.boolean().nullable().optional();
const unknownRecord = z.record(z.string(), z.unknown());
const resourceUsageSchema = unknownRecord.nullable();
const knownRuntimeStateSchema = z.enum([
  "installing",
  "initializing",
  "updating",
  "recovering",
  "healthy",
  "degraded",
  "critical"
]);
const knownVMStateSchema = z.enum([
    "not-installed",
    "stopped",
    "starting",
    "running",
    "stale",
    "unreachable",
    "failed"
  ]);
const runtimeStateSchema = z.union([knownRuntimeStateSchema, z.string()]);
const vmStateSchema = z.union([knownVMStateSchema, z.string()]).nullable();
const runtimeEventTypeSchema = z.union([z.enum(runtimeEventTypeValues), z.string()]);
const recorderStatusSchema = z.enum([
  "online",
  "stale",
  "offline",
  "notObserved",
  "unknown"
]);
const bedStatusSchema = z.enum([
  "online",
  "stale",
  "offline",
  "notObserved",
  "unknown"
]);
const relationshipEventTypeSchema = z.enum([
  "handoff",
  "duplicateAssignment",
  "unlinkedBed",
  "unlinkedRecorder",
  "staleLink"
]);
const relationshipSeveritySchema = z.enum(["info", "warning", "critical"]);
const anomalySeveritySchema = z.enum(["info", "warning", "critical"]);
const vitalDBAnomalyKindSchema = z.enum([
  "offline",
  "duplicate-ip",
  "backend-unavailable",
  "stale-recorder",
  "observer-unhealthy"
]);
const networkModeSchema = z.enum(["shared", "bridged"]);
const recorderIngressSendDataModeSchema = z.enum([
  "passthrough",
  "mirror_spool",
  "spool_only",
  "spool_and_replay"
]);
const redisRelayScopeSchema = z.enum([
  "waveform_trend_only",
  "vital_reconstruction"
]);
const runtimeRecorderIngressSettingsSchema = z
  .object({
    sendDataMaxPendingItems: z.number().int(),
    sendDataMaxPendingMiB: z.number().int(),
    sendDataMaxPayloadMiB: z.number().int(),
    sendDataReplayedMaxItems: z.number().int(),
    sendDataRealtimeMaxPendingItems: z.number().int(),
    sendDataReplayIntervalMs: z.number().int(),
    sendDataReplayMaxAttempts: z.number().int(),
    sendDataReplayTargetTimeoutMs: z.number().int(),
    sendDataReplayAdaptiveMinConcurrency: z.number().int(),
    sendDataReplayAdaptiveMaxConcurrency: z.number().int(),
    rawArchiveEnabled: z.boolean(),
    rawArchiveMaxFileMiB: z.number().int(),
    rawArchiveMaxFiles: z.number().int(),
    rawArchiveAutoExportEnabled: z.boolean(),
    rawArchiveAutoExportQuietSeconds: z.number().int(),
    rawArchiveAutoExportScanIntervalSeconds: z.number().int(),
    rawArchiveAutoExportCursorStableSeconds: z.number().int(),
    rawArchiveAutoExportRetryDelaySeconds: z.number().int(),
    rawArchiveAutoExportMaxAttempts: z.number().int(),
    rawArchiveAutoExportRequestTimeoutSeconds: z.number().int()
  })
  .passthrough();
const recorderIngressMemoryGuardStatusSchema = z.enum([
  "healthy",
  "warm",
  "hot",
  "critical",
  "missing",
  "stale",
  "invalid",
  "failed",
  "unavailable",
  "disabled"
]);
const testKitStateSchema = z.enum([
  "disabled",
  "stopped",
  "starting",
  "running",
  "paused",
  "stopping",
  "failed"
]);
const vitalRecorderSummarySourceSchema = z.enum([
  "vitalDBObservation",
  "unavailable"
]);
const vitalDBObservationReadStateSchema = z.enum([
  "loaded",
  "unavailable",
  "failed"
]);

export const runtimeCommandResponseSchema = z
  .object({
    result: z
      .object({
        exitCode: z.number().optional(),
        stdout: z.string().optional(),
        stderr: z.string().optional()
      })
      .passthrough()
      .optional()
  })
  .passthrough();

export const runtimeCapabilitiesSchema = z
  .object({
    canInstallRuntime: z.boolean(),
    canUninstallRuntime: z.boolean(),
    canApplyBundle: z.boolean(),
    canRollback: z.boolean(),
    canEditVMResources: z.boolean(),
    canEditNetworkExposure: z.boolean(),
    canResetAdminPassword: z.boolean(),
    canOpenLocalFiles: z.boolean(),
    canStreamLogs: z.boolean(),
    canControlRuntimeServices: z.boolean(),
    canExportLogs: z.boolean(),
    canViewReleaseMetadata: z.boolean(),
    canUseTestTools: z.boolean()
  })
  .passthrough();

export const runtimeSettingsSchema = z
  .object({
    readIssues: z
      .array(
        z
          .object({
            source: z.string(),
            message: z.string()
          })
          .passthrough()
      ),
    cpuCount: z.number().int(),
    memoryGiB: z.number().int(),
    diskGiB: z.number().int(),
    minimumDiskGiB: z.number().int(),
    networkMode: networkModeSchema,
    bridgedInterface: z.string().nullable(),
    proxyPort: z.number().int(),
    runtimeControlPort: z.number().int(),
    vitalFilesDirectory: z.string(),
    vitalServerURL: z.string(),
    remoteConsoleURL: z.string(),
    publicHost: z.string(),
    publicPort: z.number().int(),
    recorderIngressSendDataMode: recorderIngressSendDataModeSchema,
    recorderIngressSendDataReplayBatchSize: z.number().int(),
    recorderIngressSendDataReplayMaxMiBPerSecond: z.number().int(),
    recorderIngress: runtimeRecorderIngressSettingsSchema,
    containerMemoryLimitsEnabled: z.boolean(),
    vitalServerContainerMemoryLimitMiB: z.number().int(),
    recorderIngressContainerMemoryLimitMiB: z.number().int(),
    redisContainerMemoryLimitMiB: z.number().int(),
    adminPassword: z.string(),
    changeAdminPassword: z.boolean(),
    startOnBoot: z.boolean(),
    startOnBootConfigurable: z.boolean(),
    autoRecoveryEnabled: z.boolean(),
    preventSystemSleep: z.boolean(),
    automaticBackupEnabled: z.boolean(),
    backupScheduleTimes: z.string().array(),
    backupRetentionCount: z.number().int(),
    logArchiveRetentionDays: z.number().int(),
    logArchiveMaximumGiB: z.number().int(),
    redisRelay: z
      .object({
        enabled: z.boolean(),
        target: z
          .object({
            url: z.string(),
            username: z.string(),
            password: z.string(),
            clearPassword: z.boolean(),
            passwordConfigured: z.boolean(),
            tls: z.boolean()
          })
          .passthrough(),
        scope: redisRelayScopeSchema,
        includeRecorderNetworkContext: z.boolean(),
        intervalSeconds: z.number(),
        scanCount: z.number().int()
      })
      .passthrough(),
    restartAfterSave: z.boolean()
  })
  .passthrough();

const runtimeDataDirectoryStatsSchema = z
  .object({
    fileCount: z.number().optional(),
    sizeBytes: z.number().optional()
  })
  .passthrough();

const runtimeDomainErrorSchema = z
  .object({
    code: z.string().optional(),
    category: z
      .enum([
        "installation",
        "vmLifecycle",
        "hostProxy",
        "hostService",
        "guestNetworking",
        "guestAgent",
        "guestBootstrap",
        "guestStorage",
        "container",
        "vitalDB",
        "auxiliaryUI",
        "hostResources",
        "configuration",
        "observability",
        "unknown"
      ])
      .optional(),
    severity: z.enum(["warning", "critical"]).optional(),
    recoveryAction: z
      .enum([
        "installRuntime",
        "restartVMService",
        "restartProxyService",
        "restartWatchdogService",
        "waitForGuest",
        "restartGuestAgent",
        "repairGuestBootstrap",
        "restartContainerServices",
        "repairProxyConfiguration",
        "freeProxyPort",
        "inspectVitalDBObservation",
        "backupAndRecreateVM",
        "fixConfiguration",
        "freeHostResources",
        "inspectLogs"
      ])
      .optional()
  })
  .passthrough();

const runtimeRecorderConnectionObservationSchema = z
  .object({
    vrcode: z.string(),
    activeConnections: z.number(),
    selectedIp: nullableString,
    lastSeenAt: nullableString
  })
  .passthrough();

const runtimeRecorderIngressThroughputStatusSchema = z
  .object({
    windowSeconds: nullableNumber,
    observedBytesPerSecond: nullableNumber,
    spooledBytesPerSecond: nullableNumber,
    replayedBytesPerSecond: nullableNumber,
    queueGrowthBytesPerSecond: nullableNumber
  })
  .passthrough();

const runtimeRecorderIngressFailureObservationSchema = z
  .object({
    reason: nullableString,
    message: nullableString,
    occurredAt: nullableString
  })
  .passthrough();

const runtimeRecorderIngressRawArchiveAutoExportJobSchema = z
  .object({
    jobId: nullableString,
    archivePath: nullableString,
    archiveCursor: nullableNumber,
    state: nullableString,
    attempts: nullableNumber,
    maxAttempts: nullableNumber,
    createdAt: nullableString,
    updatedAt: nullableString,
    startedAt: nullableString,
    completedAt: nullableString,
    nextAttemptAt: nullableString,
    lastFailure: runtimeRecorderIngressFailureObservationSchema.nullable().optional()
  })
  .passthrough();

const runtimeRecorderIngressRawArchiveAutoExportStatusSchema = z
  .object({
    status: nullableString,
    finalizable: nullableBoolean,
    reasons: z.array(z.string()).optional(),
    archivePath: nullableString,
    archiveCursor: nullableNumber,
    cursorStableForMs: nullableNumber,
    lastDecisionAt: nullableString,
    activeJob: runtimeRecorderIngressRawArchiveAutoExportJobSchema.nullable().optional(),
    uploadedJobs: nullableNumber,
    failedJobs: nullableNumber,
    lastResult: z.record(z.string(), z.unknown()).nullable().optional(),
    lastFailure: runtimeRecorderIngressFailureObservationSchema.nullable().optional()
  })
  .passthrough();

const runtimeRecorderIngressRawArchiveStatusSchema = z
  .object({
    status: nullableString,
    path: nullableString,
    persistedEvents: nullableNumber,
    persistedBytes: nullableNumber,
    writeFailures: nullableNumber,
    lastArchivedAt: nullableString,
    lastArchiveId: nullableString,
    lastOffset: nullableNumber,
    lastFailure: runtimeRecorderIngressFailureObservationSchema.nullable().optional(),
    autoExport: runtimeRecorderIngressRawArchiveAutoExportStatusSchema
      .nullable()
      .optional()
  })
  .passthrough();

const runtimeRecorderIngressSpoolStatusSchema = z
  .object({
    mode: nullableString,
    status: nullableString,
    storage: nullableString,
    acceptedEvents: nullableNumber,
    spooledEvents: nullableNumber,
    rejectedEvents: nullableNumber,
    writeFailures: nullableNumber,
    pendingItems: nullableNumber,
    pendingBytes: nullableNumber,
    oldestPendingAgeSeconds: nullableNumber,
    lastAcceptedAt: nullableString,
    lastSpooledAt: nullableString,
    lastFailure: runtimeRecorderIngressFailureObservationSchema.nullable().optional()
  })
  .passthrough();

const runtimeRecorderIngressReplayAdaptiveStatusSchema = z
  .object({
    enabled: nullableBoolean,
    minBytesPerSecond: nullableNumber,
    maxBytesPerSecond: nullableNumber,
    currentMaxBytesPerSecond: nullableNumber,
    minItemsPerTick: nullableNumber,
    maxItemsPerTick: nullableNumber,
    currentItemsPerTick: nullableNumber,
    minConcurrency: nullableNumber,
    maxConcurrency: nullableNumber,
    currentConcurrency: nullableNumber,
    lastDecision: nullableString,
    lastReason: nullableString,
    lastChangedAt: nullableString,
    memoryGuardStatus: recorderIngressMemoryGuardStatusSchema.nullable().optional()
  })
  .passthrough();

const runtimeRecorderIngressReplayStatusSchema = z
  .object({
    status: nullableString,
    pendingItems: nullableNumber,
    inFlightItems: nullableNumber,
    replayedEvents: nullableNumber,
    retryableFailures: nullableNumber,
    deadLetteredEvents: nullableNumber,
    replayLagSeconds: nullableNumber,
    maxBytesPerSecond: nullableNumber,
    configuredMaxBytesPerSecond: nullableNumber,
    adaptive: runtimeRecorderIngressReplayAdaptiveStatusSchema.nullable().optional(),
    lastReplayAt: nullableString,
    lastFailure: runtimeRecorderIngressFailureObservationSchema.nullable().optional()
  })
  .passthrough();

const runtimeRecorderIngressStatusDocumentSchema = z
  .object({
    startedAt: nullableString,
    uptimeSeconds: nullableNumber,
    activeWebSockets: z.number(),
    activeRecorderConnections: z.number(),
    recorders: z.array(runtimeRecorderConnectionObservationSchema),
    httpRequests: z.number(),
    socketIoEventsSeen: z.number(),
    socketIoParseFailures: z.number(),
    auditWriteFailures: z.number(),
    auditFileWriteFailures: z.number(),
    auditStdoutWriteFailures: z.number(),
    redisIpWriteFailures: z.number(),
    redisIpVerifyFailures: z.number().optional(),
    redisIpVerifyMismatches: z.number().optional(),
    throughput: runtimeRecorderIngressThroughputStatusSchema.nullable().optional(),
    rawArchive: runtimeRecorderIngressRawArchiveStatusSchema.nullable().optional(),
    spool: runtimeRecorderIngressSpoolStatusSchema.nullable().optional(),
    replay: runtimeRecorderIngressReplayStatusSchema.nullable().optional()
  })
  .passthrough();

const runtimeContainerServiceObservationSchema = z
  .object({
    service: z.string(),
    name: nullableString,
    state: nullableString,
    health: nullableString,
    exitCode: nullableNumber,
    memoryUsedBytes: nullableNumber,
    memoryLimitBytes: nullableNumber,
    startedAt: nullableString,
    uptimeSeconds: nullableNumber
  })
  .passthrough();

const runtimeRecorderIngressStatusReadStateSchema = z.enum([
  "notRead",
  "loaded",
  "skippedMissingProxyPort",
  "commandFailed",
  "emptyResponse",
  "outputInvalid",
  "invalidResponse",
  "readFailed"
]);

const runtimeFileMetadataReadStateSchema = z.enum([
  "notRead",
  "loaded",
  "readFailed"
]);

const runtimeContainerServicesReadStateSchema = z.enum([
  "loaded",
  "missing",
  "invalid",
  "stale",
  "read-failed"
]);

const runtimeContainerObservationSchema = z
  .object({
    recorderIngressHTTP: z.string(),
    recorderIngressStatus: runtimeRecorderIngressStatusDocumentSchema.nullable().optional(),
    recorderIngressStatusReadState: runtimeRecorderIngressStatusReadStateSchema,
    recorderIngressStatusReadError: nullableString,
    runtimeStateUpdatedAt: nullableString,
    runtimeStateFileUpdatedAt: nullableString,
    runtimeStateFileMetadataReadState: runtimeFileMetadataReadStateSchema,
    runtimeStateFileMetadataError: nullableString,
    containerLogsPresent: z.boolean(),
    containerLogsBytes: nullableNumber,
    containerLogsUpdatedAt: nullableString,
    containerLogsMetadataError: nullableString,
    composeServices: z.array(runtimeContainerServiceObservationSchema),
    composeServicesReadState: runtimeContainerServicesReadStateSchema,
    composeServicesReadError: nullableString
  })
  .passthrough();

const vitalDBRecorderActivityBucketSchema = z
  .object({
    bucketStartedAt: z.string(),
    bucketSeconds: z.number(),
    messageCount: z.number(),
    byteCount: z.number(),
    roomCount: z.number()
  })
  .passthrough();

const vitalDBRecorderActivityObservationSchema = z
  .object({
    windowSeconds: z.number(),
    messageCount: z.number(),
    byteCount: z.number(),
    roomCount: z.number(),
    firstSeenAt: nullableString,
    lastSeenAt: nullableString,
    messagesPerSecond: z.number(),
    bytesPerSecond: z.number(),
    buckets: z.array(vitalDBRecorderActivityBucketSchema)
  })
  .passthrough();

const vitalDBRecorderObservationSchema = z
  .object({
    vrcode: z.string(),
    ip: nullableString,
    lastSeenAt: nullableString,
    version: nullableString,
    info: nullableString,
    config: nullableString,
    online: z.boolean(),
    stale: z.boolean(),
    activity: vitalDBRecorderActivityObservationSchema.nullable().optional()
  })
  .passthrough();

const vitalDBBedObservationSchema = z
  .object({
    bedID: z.string(),
    name: nullableString,
    vrcode: nullableString,
    lastSeenAt: nullableString,
    patientConnected: nullableBoolean,
    online: z.boolean()
  })
  .passthrough();

const vitalDBAnomalyObservationSchema = z
  .object({
    id: z.string(),
    kind: vitalDBAnomalyKindSchema,
    severity: anomalySeveritySchema,
    observedAt: z.string(),
    subject: z.string(),
    message: z.string()
  })
  .passthrough();

const vitalDBObservationReadIssueSchema = z
  .object({
    source: z.string(),
    message: z.string()
  })
  .passthrough();

export const vitalDBObservationSchema = z
  .object({
    schemaVersion: z.number(),
    source: z.string(),
    observedAt: z.string(),
    ready: z.boolean(),
    recorderOnlineThresholdSeconds: z.number(),
    recorders: z.array(vitalDBRecorderObservationSchema),
    beds: z.array(vitalDBBedObservationSchema),
    devices: z.array(unknownRecord),
    filters: z.array(unknownRecord),
    proxyConnections: z.array(unknownRecord),
    anomalies: z.array(vitalDBAnomalyObservationSchema),
    readIssues: z.array(vitalDBObservationReadIssueSchema)
  })
  .passthrough();

const runtimeVitalDBObservationSnapshotSchema = z
  .object({
    state: vitalDBObservationReadStateSchema,
    observation: vitalDBObservationSchema.nullable().optional(),
    readError: nullableString
  })
  .passthrough()
  .superRefine((snapshot, context) => {
    if (snapshot.state === "loaded" && snapshot.observation == null) {
      context.addIssue({
        code: "custom",
        path: ["observation"],
        message: "loaded VitalDB observation snapshots must include observation"
      });
    }
    if (snapshot.state === "failed" && isBlank(snapshot.readError)) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: "failed VitalDB observation snapshots must include readError"
      });
    }
  });

export const runtimeStatusSchema = z
  .object({
    runtimeInstalled: z.boolean().optional(),
    vmServiceLoaded: z.boolean().optional(),
    proxyServiceLoaded: z.boolean().optional(),
    guestLogSyncServiceLoaded: z.boolean().optional(),
    sleepPreventionServiceLoaded: nullableBoolean,
    watchdogServiceLoaded: z.boolean().optional(),
    runtimeState: runtimeStateSchema.optional(),
    operation: nullableString,
    statusMessage: nullableString,
    statusDocumentError: nullableString,
    updatedAt: nullableString,
    startedAt: nullableString,
    runtimeVersion: nullableString,
    vmState: vmStateSchema.optional(),
    vmErrors: z.array(z.string()).nullable().optional(),
    latestBackup: nullableString,
    vmIP: nullableString,
    guestHTTP: nullableString,
    hostProxyHTTP: nullableString,
    runtimeControlHTTP: nullableString,
    runtimeControlStartedAt: nullableString,
    redisUIHTTP: nullableString,
    swaggerUIHTTP: nullableString,
    cpuUsagePercent: nullableNumber,
    memory: resourceUsageSchema.optional(),
    systemDisk: resourceUsageSchema.optional(),
    dataStorage: resourceUsageSchema.optional(),
    guestRuntimeStateError: nullableString,
    dataDirectoryStats: runtimeDataDirectoryStatsSchema.nullable().optional(),
    dataDirectoryStatsError: nullableString,
    proxyPort: z.number().optional(),
    failureReasons: z.array(z.string()).optional(),
    progress: unknownRecord.nullable().optional(),
    containerObservation: runtimeContainerObservationSchema.nullable().optional(),
    vitalDBObservation: vitalDBObservationSchema.nullable().optional()
  })
  .passthrough();

const runtimeVitalRecorderSummarySchema = z
  .object({
    source: vitalRecorderSummarySourceSchema,
    activeConnections: z.number().optional(),
    knownRecorders: z.number().optional(),
    onlineRecorders: z.number().optional(),
    staleRecorders: z.number().optional(),
    knownBeds: z.number().optional(),
    recorderAnomalies: z.number().optional(),
    observedAt: nullableString,
    latestRecorder: z
      .object({
        vrcode: z.string(),
        ip: nullableString,
        lastSeenAt: nullableString,
        source: vitalRecorderSummarySourceSchema
      })
      .passthrough()
      .nullable()
      .optional()
  })
  .passthrough()
  .superRefine((summary, context) => {
    if (summary.source !== "vitalDBObservation") {
      return;
    }

    for (const field of [
      "knownRecorders",
      "onlineRecorders",
      "staleRecorders",
      "knownBeds",
      "recorderAnomalies",
      "observedAt"
    ] as const) {
      if (summary[field] == null) {
        context.addIssue({
          code: "custom",
          path: [field],
          message: "VitalDB-backed recorder summaries must include observed metrics"
        });
      }
    }
  });

export const runtimeOverviewSchema = z
  .object({
    status: runtimeStatusSchema,
    settings: runtimeSettingsSchema,
    release: unknownRecord,
    install: unknownRecord,
    vitalDBObservation: vitalDBObservationSchema.nullable().optional(),
    vitalDBObservationSnapshot: runtimeVitalDBObservationSnapshotSchema,
    vitalRecorder: runtimeVitalRecorderSummarySchema
  })
  .passthrough();

export const runtimeBackupSchema = z
  .object({
    path: z.string().optional(),
    sizeBytes: nullableNumber
  })
  .passthrough();

export const runtimeEventDocumentSchema = z
  .object({
    schemaVersion: z.number(),
    id: z.string(),
    source: z.string(),
    eventType: runtimeEventTypeSchema,
    timestamp: z.string(),
    product: z.string(),
    status: runtimeStateSchema.optional(),
    previousStatus: nullableString,
    operation: z.string().optional(),
    message: z.string(),
    runtimeVersion: z.string(),
    vmState: vmStateSchema.optional(),
    vmErrors: z.array(z.string()).nullable().optional(),
    failureReasons: z.array(z.string()),
    domainErrors: z.array(runtimeDomainErrorSchema).nullable().optional(),
    containerObservation: runtimeContainerObservationSchema.nullable().optional(),
    progress: unknownRecord.nullable().optional(),
    vitalDBObservation: vitalDBObservationSchema.nullable().optional()
  })
  .passthrough();

export const runtimeEventHistorySchema = z
  .object({
    events: z.array(runtimeEventDocumentSchema),
    nextCursor: nullableString,
    matchingCount: nullableNumber
  })
  .passthrough();

const recorderActivityBucketSchema = z
  .object({
    bucketStartedAt: z.string(),
    bucketSeconds: z.number(),
    messageCount: z.number(),
    byteCount: z.number(),
    roomCount: z.number()
  })
  .passthrough();

const recorderActivityPointSchema = z
  .object({
    observedAt: z.string(),
    windowSeconds: z.number(),
    messageCount: z.number(),
    byteCount: z.number(),
    roomCount: z.number(),
    messagesPerSecond: z.number(),
    bytesPerSecond: z.number(),
    buckets: z.array(recorderActivityBucketSchema)
  })
  .passthrough();

const vitalDBRecorderRecordSchema = z
  .object({
    vrcode: z.string(),
    status: recorderStatusSchema,
    lastIP: nullableString,
    version: nullableString,
    bedID: nullableString,
    bedName: nullableString,
    patientConnected: nullableBoolean,
    firstSeenAt: nullableString,
    lastSeenAt: nullableString,
    observationCount: z.number(),
    duplicateObservationCount: z.number(),
    currentAnomalyCount: z.number(),
    latestAnomalyKind: vitalDBAnomalyKindSchema.nullable().optional(),
    latestAnomalySeverity: anomalySeveritySchema.nullable().optional(),
    latestAnomalyMessage: nullableString.optional(),
    latestAnomalyObservedAt: nullableString.optional(),
    presentInLatestObservation: z.boolean(),
    activityTimeline: z.array(recorderActivityPointSchema).optional()
  })
  .passthrough();

const vitalDBBedRecordSchema = z
  .object({
    bedID: z.string(),
    name: nullableString,
    vrcode: nullableString,
    linkedRecorderStatus: recorderStatusSchema.nullable().optional(),
    linkedRecorderIP: nullableString.optional(),
    linkedRecorderLastSeenAt: nullableString.optional(),
    status: bedStatusSchema,
    patientConnected: nullableBoolean,
    firstSeenAt: nullableString,
    lastSeenAt: nullableString,
    observationCount: z.number(),
    duplicateObservationCount: z.number(),
    currentAnomalyCount: z.number(),
    latestAnomalyKind: vitalDBAnomalyKindSchema.nullable().optional(),
    latestAnomalySeverity: anomalySeveritySchema.nullable().optional(),
    latestAnomalyMessage: nullableString.optional(),
    latestAnomalyObservedAt: nullableString.optional()
  })
  .passthrough();

const vitalDBRecorderHistorySummarySchema = z
  .object({
    knownRecorders: z.number(),
    currentRecorders: z.number(),
    onlineRecorders: z.number(),
    staleRecorders: z.number(),
    recorderAnomalies: z.number(),
    knownBeds: z.number(),
    onlineBeds: z.number(),
    staleBeds: z.number(),
    bedAssignments: z.number(),
    bedAnomalies: z.number()
  })
  .passthrough();

const recorderActivityHistorySourceSchema = z.enum([
  "sqliteProjection",
  "unavailable",
  "notProvided"
]);

const recorderActivityHistorySchema = z
  .object({
    source: recorderActivityHistorySourceSchema,
    bucketCount: z.number(),
    earliestBucketStartedAt: nullableString,
    latestBucketStartedAt: nullableString,
    readError: nullableString
  })
  .passthrough();

export const vitalDBRecordersSchema = z
  .object({
    updatedAt: nullableString,
    recorders: z.array(vitalDBRecorderRecordSchema),
    beds: z.array(vitalDBBedRecordSchema),
    summary: vitalDBRecorderHistorySummarySchema,
    activityHistory: recorderActivityHistorySchema,
    readError: nullableString
  })
  .passthrough();

export const vitalDBBedsSchema = z.array(vitalDBBedRecordSchema);

const vitalDBRelationshipAssignmentSchema = z
  .object({
    assignmentID: z.string(),
    bedID: z.string(),
    bedName: nullableString,
    vrcode: z.string(),
    startedAt: z.string(),
    endedAt: nullableString,
    lastSeenAt: nullableString,
    lastObservedAt: z.string(),
    status: bedStatusSchema,
    patientConnected: nullableBoolean,
    observationCount: z.number()
  })
  .passthrough();

const vitalDBRelationshipEventSchema = z
  .object({
    eventID: z.string(),
    observedAt: z.string(),
    eventType: relationshipEventTypeSchema,
    severity: relationshipSeveritySchema,
    bedID: nullableString,
    bedName: nullableString,
    vrcode: nullableString,
    previousVrcode: nullableString,
    previousBedID: nullableString,
    message: z.string()
  })
  .passthrough();

export const vitalDBRelationshipsSchema = z
  .object({
    state: z.enum(["loaded", "partiallyLoaded", "readFailed"]),
    assignments: z.array(vitalDBRelationshipAssignmentSchema),
    events: z.array(vitalDBRelationshipEventSchema),
    readError: nullableString
  })
  .passthrough();

export const runtimeLogTextResponseSchema = z
  .object({
    text: z.string()
  })
  .passthrough();

export const runtimeLogExportResultSchema = z
  .object({
    destination: z.string()
  })
  .passthrough();

export const runtimeUpdateBundleSummaryResponseSchema = z
  .object({
    summary: z.string()
  })
  .passthrough();

function isBlank(value: string | null | undefined): boolean {
  return value == null || value.trim().length === 0;
}

const runtimeTestKitBedSchema = z
  .object({
    roomName: z.string(),
    bedId: z.string()
  })
  .passthrough();

const runtimeTestKitCleanupErrorSchema = z
  .object({
    vrcode: z.string(),
    targetUrl: z.string(),
    error: z.string()
  })
  .passthrough();

const runtimeTestKitRecorderSchema = z
  .object({
    vrcode: z.string(),
    baseUrl: z.string(),
    localIp: nullableString,
    connected: z.boolean(),
    joinSent: z.boolean(),
    joinedAt: nullableNumber,
    lastReconnectAt: nullableNumber,
    lastSendDataAt: nullableNumber,
    messagesSent: z.number(),
    bytesSent: z.number()
  })
  .passthrough();

const runtimeTestKitSessionVitalArtifactSchema = z
  .object({
    path: z.string(),
    filename: z.string(),
    sizeBytes: z.number(),
    createdAt: z.number(),
    format: z.string(),
    retentionPolicy: z.string()
  })
  .passthrough();

const runtimeTestKitSessionVitalUploadResultSchema = z
  .object({
    statusCode: z.number(),
    ok: z.boolean(),
    elapsedSeconds: z.number(),
    uploadedAt: z.number(),
    responseText: z.string(),
    error: nullableString
  })
  .passthrough();

const runtimeTestKitSessionVitalStateSchema = z
  .object({
    exportStatus: z.string(),
    uploadStatus: z.string(),
    exportError: nullableString,
    uploadError: nullableString,
    artifact: runtimeTestKitSessionVitalArtifactSchema.nullable(),
    uploadResult: runtimeTestKitSessionVitalUploadResultSchema.nullable()
  })
  .passthrough();

const runtimeTestKitRecorderSourceSchema = z
  .object({
    type: z.literal("vitalFile"),
    path: z.string(),
    scenario: z.enum([
      "basic_monitor",
      "periop_full",
      "bloodbag",
      "root_sedation",
      "full_real"
    ]),
    startOffsetSeconds: z.number(),
    durationSeconds: z.number()
  })
  .passthrough();

export const runtimeTestKitSessionSchema = z
  .object({
    id: z.string(),
    state: z.string(),
    targetUrl: z.string(),
    recordersRequested: z.number(),
    bedsRequested: z.number(),
    bedRoomNames: z.array(z.string()),
    vrcode: nullableString,
    version: z.string(),
    intervalSeconds: z.number(),
    durationSeconds: nullableNumber,
    maxMessages: nullableNumber,
    shiftTime: z.boolean(),
    generateFrames: z.boolean(),
    source: runtimeTestKitRecorderSourceSchema.nullable().optional(),
    realSampleKey: nullableString.optional(),
    scenario: nullableString,
    defaultScenario: z.string(),
    createdAt: nullableNumber,
    startedAt: nullableNumber,
    stoppedAt: nullableNumber,
    messagesSent: z.number(),
    bytesSent: z.number(),
    lastError: nullableString,
    cleanupErrors: z.array(runtimeTestKitCleanupErrorSchema),
    vital: runtimeTestKitSessionVitalStateSchema,
    recorders: z.array(runtimeTestKitRecorderSchema)
  })
  .passthrough();

export const runtimeTestKitStatusSchema = z
  .object({
    enabled: z.boolean(),
    state: testKitStateSchema,
    serviceName: nullableString,
    apiBaseURL: nullableString,
    recorderTargetURL: nullableString,
    startedAt: nullableString,
    activeSession: runtimeTestKitSessionSchema.nullable().optional(),
    sessions: z.array(runtimeTestKitSessionSchema),
    beds: z.array(runtimeTestKitBedSchema),
    lastError: nullableString
  })
  .passthrough();

export const runtimeTestKitBedListSchema = z.array(runtimeTestKitBedSchema);

export const runtimeTestKitSessionOrNullSchema =
  runtimeTestKitSessionSchema.nullable();

export const runtimeTestKitRecorderDeletionSchema = z
  .object({
    vrcode: z.string(),
    targetUrl: z.string(),
    deleted: z.boolean(),
    error: nullableString
  })
  .passthrough();

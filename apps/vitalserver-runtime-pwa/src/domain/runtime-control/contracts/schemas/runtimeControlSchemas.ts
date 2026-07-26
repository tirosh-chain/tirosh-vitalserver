import { z } from "zod";

import { runtimeEventTypeValues } from "@/domain/runtime-control/contracts/runtimeEventTypes";

const nullableString = z.string().nullable().optional();
const requiredNullableString = z.string().nullable();
const nullableNumber = z.number().nullable().optional();
const nullableBoolean = z.boolean().nullable().optional();
const requiredNullableBoolean = z.boolean().nullable();
const unknownRecord = z.record(z.string(), z.unknown());
const requiredNullableRecord = unknownRecord.nullable();
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
const platformServiceRoleValues = [
  "runtime-provider",
  "public-proxy",
  "log-sync",
  "sleep-prevention",
  "watchdog"
] as const;
const runtimeStateSchema = z.union([knownRuntimeStateSchema, z.string()]);
const vmStateSchema = z.union([knownVMStateSchema, z.string()]).nullable();
const runtimeEventTypeSchema = z.enum(runtimeEventTypeValues);
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
const vitalDBRecordVisibilitySchema = z.enum(["visible", "hidden"]);
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
  "observe_only",
  "mirror_spool",
  "spool_only",
  "spool_and_replay"
]);
const redisRelayScopeSchema = z.enum([
  "waveform_trend_only",
  "vital_reconstruction"
]);
const runtimeRedisRelayBatchSchema = z
  .object({
    scanned: z.number().int(),
    copied: z.number().int(),
    published: z.number().int(),
    unchanged: z.number().int(),
    duplicates: z.number().int(),
    skipped: z.number().int(),
    denied: z.number().int(),
    missing: z.number().int(),
    errors: z.number().int()
  })
  .passthrough();
const runtimeRedisRelayStatusSchema = z
  .object({
    schemaVersion: z.number().int(),
    observedAt: z.string(),
    enabled: z.boolean(),
    state: z.string(),
    scope: requiredNullableString,
    targetUrl: requiredNullableString,
    targetUsernameConfigured: z.boolean(),
    targetPasswordConfigured: z.boolean(),
    settingsFingerprint: requiredNullableString,
    batches: z.number().int(),
    totals: runtimeRedisRelayBatchSchema,
    lastBatch: runtimeRedisRelayBatchSchema.nullable(),
    lastSuccessAt: requiredNullableString,
    lastErrorAt: requiredNullableString,
    lastError: requiredNullableString
  })
  .passthrough();
export const runtimeRedisRelayStatusReadResultSchema = z
  .object({
    readState: z.enum(["notRead", "loaded", "invalidResponse", "readFailed"]),
    document: runtimeRedisRelayStatusSchema.nullable(),
    readError: z.string().nullable()
  })
  .strict()
  .superRefine((read, context) => {
    if (read.readState === "loaded") {
      if (read.document === null) {
        context.addIssue({
          code: "custom",
          path: ["document"],
          message: "loaded Redis Relay status reads must include document"
        });
      }
      if (read.readError !== null && read.readError.trim() !== "") {
        context.addIssue({
          code: "custom",
          path: ["readError"],
          message: "loaded Redis Relay status reads must not include readError"
        });
      }
    }
    if (
      (read.readState === "invalidResponse" || read.readState === "readFailed") &&
      (read.readError === null || read.readError.trim() === "")
    ) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: `${read.readState} Redis Relay status reads must include readError`
      });
    }
  });
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

export const runtimeRedisRelaySettingsReadSchema = z.object({
  state: z.enum(["loaded", "unavailable", "failed"]),
  settings: z
    .object({
      enabled: z.boolean(),
      target: z.object({
        url: z.string(),
        username: z.string(),
        passwordConfigured: z.boolean(),
        tls: z.boolean()
      }),
      scope: redisRelayScopeSchema,
      includeRecorderNetworkContext: z.boolean(),
      intervalSeconds: z.number().min(0.1),
      scanCount: z.number().int().min(1)
    })
    .nullable(),
  readError: z.string().nullable()
});
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
const vitalDBObservationReadStateSchema = z.enum([
  "loaded",
  "unavailable",
  "failed"
]);
const vitalRecorderHistoryStateSchema = z.enum([
  "loaded",
  "partiallyLoaded",
  "readFailed"
]);
const runtimeOperationResourceReadStateSchema = z.enum([
  "loaded",
  "unavailable",
  "failed",
  "stale"
]);
const runtimeGuestControlServiceStatusSchema = z
  .object({
    service: z.string(),
    state: z.string(),
    health: z.string(),
    observedAt: z.string(),
    container: nullableString,
    exitCode: nullableNumber,
    memory: resourceUsageSchema.optional()
  })
  .passthrough();
const runtimeGuestServiceSpecSchema = z
  .object({
    state: z.string(),
    desiredState: nullableString,
    updatedAt: nullableString
  })
  .passthrough();
const runtimeGuestServiceStatusReadSchema = z
  .object({
    state: z.string(),
    observedState: nullableString,
    observedAt: nullableString,
    serviceStatus: runtimeGuestControlServiceStatusSchema.nullable().optional(),
    readError: z
      .object({
        kind: z.string(),
        message: z.string(),
        evidencePath: nullableString
      })
      .passthrough()
      .nullable()
      .optional()
  })
  .passthrough();
const runtimeGuestServiceConditionSchema = z
  .object({
    type: z.string(),
    status: z.string(),
    reason: z.string(),
    message: z.string(),
    observedAt: z.string()
  })
  .passthrough();
export const runtimeGuestServiceResourceSchema = z
  .object({
    service: z.string(),
    spec: runtimeGuestServiceSpecSchema,
    status: runtimeGuestServiceStatusReadSchema,
    conditions: z.array(runtimeGuestServiceConditionSchema),
    lastOperationId: nullableString
  })
  .passthrough();
const runtimeProbeErrorSchema = z
  .object({
    source: z.string(),
    message: z.string()
  })
  .passthrough();
export const runtimeGuestControlStackStatusSchema = z
  .object({
    state: z.string(),
    observedAt: z.string(),
    services: z.array(runtimeGuestControlServiceStatusSchema),
    cpuUsagePercent: nullableNumber,
    memory: resourceUsageSchema.optional(),
    systemDisk: resourceUsageSchema.optional(),
    vitalFilesDisk: resourceUsageSchema.optional(),
    probeErrors: z.array(runtimeProbeErrorSchema)
  })
  .passthrough();
export const runtimeGuestControlServiceOperationSchema = z
  .object({
    operationId: z.string(),
    service: z.string(),
    command: z.enum([
      "start",
      "stop",
      "restart",
      "reconcile",
      "lab-create-session",
      "lab-start-session",
      "lab-stop-session",
      "lab-finish-session",
      "lab-replay-vital-file",
      "lab-upload-vital-file",
      "lab-create-beds",
      "lab-delete-beds",
      "lab-reset-beds",
      "lab-create-recorders",
      "lab-delete-recorders",
      "lab-reset-recorders",
      "postgres-backup",
      "postgres-restore",
      "redis-backup",
      "redis-restore",
      "repair-datastore",
      "activate-update",
      "prepare-update-shutdown",
      "request-guest-poweroff",
      "apply-settings",
      "apply-admin-password",
      "apply-redis-relay-settings"
    ]),
    state: z.enum([
      "accepted",
      "running",
      "completed",
      "failed",
      "cancelled",
      "interrupted"
    ]),
    createdAt: z.string(),
    updatedAt: z.string(),
    failure: z
      .object({
        kind: z.string(),
        message: z.string(),
        evidencePath: nullableString
      })
      .passthrough()
      .nullable()
      .optional(),
    result: z.record(z.string(), z.unknown()).nullable().optional()
  })
  .passthrough();

const runtimeProviderLifecycleDocumentSchema = z
  .object({
    schemaVersion: z.number().int(),
    // Provider lifecycle vocabulary is owner-extensible. The PWA displays the
    // explicit value and must not turn a newer platform value into a contract
    // failure.
    state: z.string(),
    operation: z.string().nullable(),
    operationID: z.string().nullable(),
    bootID: z.string().nullable(),
    startedAt: z.string(),
    updatedAt: z.string(),
    deadlineAt: z.string().nullable(),
    terminalReason: z.string().nullable(),
    message: z.string().nullable()
  })
  .strict();

const runtimeProviderResourceStateSchema = z
  .object({
    state: z.enum(["loaded", "missing", "unavailable", "failed"]),
    document: runtimeProviderLifecycleDocumentSchema.nullable(),
    readError: z.string().nullable()
  })
  .strict()
  .superRefine((resource, context) => {
    if (resource.state === "loaded" && resource.document === null) {
      context.addIssue({
        code: "custom",
        path: ["document"],
        message: "loaded Runtime Provider resources must include their lifecycle document"
      });
    }
    if (resource.state !== "loaded" && resource.document !== null) {
      context.addIssue({
        code: "custom",
        path: ["document"],
        message: "unloaded Runtime Provider resources must not include a lifecycle document"
      });
    }
  });

export const runtimeProviderCommandResponseSchema = z
  .object({
    operationId: z.string(),
    action: z.enum(["start", "stop", "restart"]),
    state: z.enum(["completed", "failed"]),
    provider: runtimeProviderResourceStateSchema,
    failure: z
      .object({
        kind: z.string(),
        message: z.string()
      })
      .strict()
      .nullable()
  })
  .strict()
  .superRefine((command, context) => {
    if (command.state === "completed" && command.failure !== null) {
      context.addIssue({
        code: "custom",
        path: ["failure"],
        message: "completed Runtime Provider commands must not include failure"
      });
    }
    if (command.state === "failed" && command.failure === null) {
      context.addIssue({
        code: "custom",
        path: ["failure"],
        message: "failed Runtime Provider commands must include failure"
      });
    }
  });

export const runtimeCommandResponseSchema = z
  .object({
    result: z
      .object({
        exitCode: z.number(),
        stdout: z.string(),
        stderr: z.string(),
        outputIssues: z.array(
          z
            .object({
              stream: z.enum(["stdout", "stderr"]),
              message: z.string()
            })
            .passthrough()
        ),
        executionIssue: z
          .object({
            kind: z.enum(["processLaunchFailed", "outputFilePreparationFailed"]),
            message: z.string()
          })
          .passthrough()
          .nullable()
      })
      .passthrough()
  })
  .passthrough();

export const platformCapabilitiesSchema = z
  .object({
    canInstallRuntime: z.boolean(),
    canUninstallRuntime: z.boolean(),
    canApplyBundle: z.boolean(),
    canRollback: z.boolean(),
    canRollbackRelease: z.boolean(),
    canEditRuntimeProviderResources: z.boolean(),
    canEditNetworkExposure: z.boolean(),
    canResetAdminPassword: z.boolean(),
    canOpenLocalFiles: z.boolean(),
    canStreamLogs: z.boolean(),
    canControlRuntimeServices: z.boolean(),
    canExportLogs: z.boolean(),
    canViewReleaseMetadata: z.boolean()
  })
  .passthrough();

export const runtimeCapabilitiesSchema = z
  .object({
    schemaVersion: z.number().int(),
    capabilities: z.array(z.string())
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

export const runtimeProductSettingsSchema = z
  .object({
    automaticBackupEnabled: z.boolean(),
    backupRetentionCount: z.number().int().positive(),
    backupScheduleTimes: z.array(z.string()),
    containerMemoryLimitsEnabled: z.boolean(),
    publicHost: z.string(),
    publicPort: z.number().int().min(1).max(65535),
    recorderIngress: runtimeRecorderIngressSettingsSchema,
    recorderIngressContainerMemoryLimitMiB: z.number().int().positive(),
    recorderIngressSendDataMode: recorderIngressSendDataModeSchema,
    recorderIngressSendDataReplayBatchSize: z.number().int().positive(),
    recorderIngressSendDataReplayMaxMiBPerSecond: z.number().int().positive(),
    redisContainerMemoryLimitMiB: z.number().int().positive(),
    remoteConsoleURL: z.string(),
    vitalServerContainerMemoryLimitMiB: z.number().int().positive(),
    vitalServerURL: z.string()
  })
  .passthrough();

export const runtimeProductSettingsReadSchema = z
  .object({
    state: z.enum(["loaded", "unavailable", "failed"]),
    settings: runtimeProductSettingsSchema.nullable(),
    readError: requiredNullableString
  })
  .superRefine((read, context) => {
    if (read.state === "loaded" && read.settings == null) {
      context.addIssue({
        code: "custom",
        path: ["settings"],
        message: "loaded runtime settings reads must include settings"
      });
    }
    if (read.state !== "loaded" && isBlank(read.readError)) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: `${read.state} runtime settings reads must include readError`
      });
    }
  });

const runtimeSettingsReadIssueSchema = z
  .object({
    source: z.string(),
    message: z.string()
  })
  .strict();

export const runtimePlatformSettingsSchema = z
  .object({
    cpuCount: z.number().int().positive(),
    memoryGiB: z.number().int().positive(),
    diskGiB: z.number().int().positive(),
    minimumDiskGiB: z.number().int().positive(),
    networkMode: networkModeSchema,
    bridgedInterface: z.string().nullable(),
    proxyPort: z.number().int().min(1).max(65535),
    runtimeControlPort: z.number().int().min(1).max(65535),
    vitalFilesDirectory: z.string().min(1),
    vitalServerURL: z.string(),
    remoteConsoleURL: z.string(),
    publicHost: z.string(),
    publicPort: z.number().int().min(1).max(65535),
    recorderIngressSendDataMode: recorderIngressSendDataModeSchema,
    recorderIngressSendDataReplayBatchSize: z.number().int().positive(),
    recorderIngressSendDataReplayMaxMiBPerSecond: z.number().int().positive(),
    recorderIngress: runtimeRecorderIngressSettingsSchema,
    containerMemoryLimitsEnabled: z.boolean(),
    vitalServerContainerMemoryLimitMiB: z.number().int().positive(),
    recorderIngressContainerMemoryLimitMiB: z.number().int().positive(),
    redisContainerMemoryLimitMiB: z.number().int().positive(),
    startOnBoot: z.boolean(),
    startOnBootConfigurable: z.boolean(),
    autoRecoveryEnabled: z.boolean(),
    preventSystemSleep: z.boolean(),
    automaticBackupEnabled: z.boolean(),
    backupScheduleTimes: z.array(z.string()),
    backupRetentionCount: z.number().int().positive(),
    logArchiveRetentionDays: z.number().int().positive(),
    logArchiveMaximumGiB: z.number().int().positive(),
    restartAfterSave: z.boolean(),
    appliedVMSettings: z
      .object({
        cpuCount: z.number().int().positive(),
        memoryGiB: z.number().int().positive(),
        networkMode: networkModeSchema,
        bridgedInterface: z.string().nullable(),
        vitalFilesDirectory: z.string().min(1)
      })
      .strict()
      .nullable()
  })
  .strict();

export const runtimePlatformSettingsReadSchema = z
  .object({
    state: z.enum(["loaded", "unavailable", "failed"]),
    settings: runtimePlatformSettingsSchema.nullable(),
    readIssues: z.array(runtimeSettingsReadIssueSchema),
    readError: requiredNullableString
  })
  .strict()
  .superRefine((read, context) => {
    if (read.state === "loaded" && read.settings == null) {
      context.addIssue({
        code: "custom",
        path: ["settings"],
        message: "loaded platform settings reads must include settings"
      });
    }
    if (read.state !== "loaded" && isBlank(read.readError)) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: `${read.state} platform settings reads must include readError`
      });
    }
  });

const runtimeDataDirectoryStatsSchema = z
  .object({
    fileCount: z.number().optional(),
    sizeBytes: z.number().optional()
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
    requestId: nullableString,
    trigger: nullableString,
    origin: nullableString,
    vrcode: nullableString,
    archivePath: nullableString,
    startOffset: nullableNumber,
    endOffset: nullableNumber,
    state: nullableString,
    publishState: nullableString,
    artifactIds: z.array(z.string()).optional(),
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
    exportedJobs: nullableNumber,
    failedJobs: nullableNumber,
    lastExportResult: z.record(z.string(), z.unknown()).nullable().optional(),
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
    redisIpVerifyFailures: z.number(),
    redisIpVerifyMismatches: z.number(),
    throughput: runtimeRecorderIngressThroughputStatusSchema.nullable().optional(),
    rawArchive: runtimeRecorderIngressRawArchiveStatusSchema.nullable().optional(),
    spool: runtimeRecorderIngressSpoolStatusSchema.nullable().optional(),
    replay: runtimeRecorderIngressReplayStatusSchema.nullable().optional()
  })
  .passthrough();

const runtimeRecorderIngressStatusReadStateSchema = z.enum([
  "notRead",
  "loaded",
  "commandFailed",
  "emptyResponse",
  "outputInvalid",
  "invalidResponse",
  "readFailed"
]);

const runtimeRecorderIngressStatusReadResultSchema = z
  .object({
    readState: runtimeRecorderIngressStatusReadStateSchema,
    httpStatus: z.string(),
    document: runtimeRecorderIngressStatusDocumentSchema.nullable(),
    readError: requiredNullableString
  })
  .passthrough()
  .superRefine((read, context) => {
    if (read.readState === "loaded") {
      if (read.document == null) {
        context.addIssue({
          code: "custom",
          path: ["document"],
          message: "loaded recorder ingress status reads must include document"
        });
      }
      if (!isBlank(read.readError)) {
        context.addIssue({
          code: "custom",
          path: ["readError"],
          message: "loaded recorder ingress status reads must not include readError"
        });
      }
    }

    if (
      read.readState === "commandFailed" ||
      read.readState === "emptyResponse" ||
      read.readState === "outputInvalid" ||
      read.readState === "invalidResponse" ||
      read.readState === "readFailed"
    ) {
      if (isBlank(read.readError)) {
        context.addIssue({
          code: "custom",
          path: ["readError"],
          message: `${read.readState} recorder ingress status reads must include readError`
        });
      }
    }
  });

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
    visibility: vitalDBRecordVisibilitySchema.optional(),
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
    online: z.boolean(),
    visibility: vitalDBRecordVisibilitySchema.optional()
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

export const runtimeVitalDBObservationSnapshotSchema = z
  .object({
    state: vitalDBObservationReadStateSchema,
    observation: vitalDBObservationSchema.nullable(),
    readError: requiredNullableString
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

export const platformStateSchema = z
  .object({
    runtimeInstallationState: z.string(),
    services: z.array(
      z
        .object({
          role: z.enum(platformServiceRoleValues),
          state: z.enum([
            "running",
            "stopped",
            "not-installed",
            "unavailable",
            "read-failed",
            "permission-denied",
            "failed"
          ]),
          readError: requiredNullableString
        })
        .passthrough()
        .superRefine((service, context) => {
          if (
            ["unavailable", "read-failed", "permission-denied", "failed"].includes(service.state) &&
            isBlank(service.readError)
          ) {
            context.addIssue({
              code: "custom",
              path: ["readError"],
              message: "failed Platform service state must include readError"
            });
          }
        })
    ),
    platformHealth: runtimeStateSchema.optional(),
    readIssues: z
      .array(
        z.object({ source: z.string(), message: z.string() }).passthrough()
      )
      .optional(),
    installedVersion: nullableString,
    runtimeProviderState: vmStateSchema.optional(),
    runtimeProviderErrors: z.array(z.string()).nullable().optional(),
    latestBackup: nullableString,
    runtimeEndpoint: nullableString,
    runtimeControllerHTTP: nullableString,
    publicProxyHTTP: nullableString,
    platformAPIHTTP: nullableString,
    platformAPIStartedAt: nullableString,
    dataStorage: resourceUsageSchema.optional(),
    dataStorageError: nullableString,
    dataDirectoryStats: runtimeDataDirectoryStatsSchema.nullable().optional(),
    dataDirectoryStatsError: nullableString,
    publicProxyPort: z.number().optional(),
    publicProxyPortReadState: z.string().nullable().optional(),
    healthIssues: z.array(z.string()).optional()
  })
  .passthrough()
  .superRefine((status, context) => {
    const serviceRoles = new Set<string>();
    for (const [index, service] of status.services.entries()) {
      if (serviceRoles.has(service.role)) {
        context.addIssue({
          code: "custom",
          path: ["services", index, "role"],
          message: `Platform service role must be reported exactly once: ${service.role}`
        });
      }
      serviceRoles.add(service.role);
    }
    for (const role of platformServiceRoleValues) {
      if (!serviceRoles.has(role)) {
        context.addIssue({
          code: "custom",
          path: ["services"],
          message: `Platform service role is required: ${role}`
        });
      }
    }
    for (const field of [
      "redisRelayStatus",
      "guestServicesReadState",
      "guestServices",
      "guestServiceStatuses",
      "guestServiceResources",
      "guestServiceResourceReadIssues",
      "guestStackProbeErrors",
      "guestServicesReadError",
      "cpuUsagePercent",
      "memory",
      "vitalServerMemory",
      "recorderIngressMemory",
      "redisMemory",
      "systemDisk",
      "runtimeInstalled",
      "vmServiceLoaded",
      "proxyServiceLoaded",
      "guestLogSyncServiceLoaded",
      "sleepPreventionServiceLoaded",
      "watchdogServiceLoaded",
      "vmServiceState",
      "proxyServiceState",
      "guestLogSyncServiceState",
      "sleepPreventionServiceState",
      "watchdogServiceState",
      "runtimeState",
      "runtimeVersion",
      "vmState",
      "vmErrors",
      "guestAddressRead",
      "vmIP",
      "guestHTTP",
      "hostProxyHTTP",
      "runtimeControlHTTP",
      "runtimeControlStartedAt",
      "redisUIHTTP",
      "swaggerUIHTTP",
      "proxyPort",
      "failureReasons"
    ] as const) {
      if (Object.prototype.hasOwnProperty.call(status, field)) {
        context.addIssue({
          code: "custom",
          path: [field],
          message:
            field === "redisRelayStatus"
              ? "Redis Relay status must be read from its Runtime owner resource"
              : `${field} belongs to a Runtime owner resource, not PlatformState`
        });
      }
    }
  });

const runtimeInstallOperationStateSchema = z
  .object({
    state: runtimeOperationResourceReadStateSchema,
    document: requiredNullableRecord,
    readError: requiredNullableString
  })
  .passthrough()
  .superRefine((install, context) => {
    if (install.state === "loaded" && install.document == null) {
      context.addIssue({
        code: "custom",
        path: ["document"],
        message: "loaded install operation state must include document"
      });
    }
    if (install.state === "failed" && isBlank(install.readError)) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: "failed install operation state must include readError"
      });
    }
  });

const runtimeOperationLeaseStateSchema = z
  .object({
    state: runtimeOperationResourceReadStateSchema,
    document: requiredNullableRecord,
    readError: requiredNullableString,
    staleReason: requiredNullableString
  })
  .passthrough()
  .superRefine((lease, context) => {
    if ((lease.state === "loaded" || lease.state === "stale") && lease.document == null) {
      context.addIssue({
        code: "custom",
        path: ["document"],
        message: `${lease.state} operation lease state must include document`
      });
    }
    if (lease.state === "failed" && isBlank(lease.readError)) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: "failed operation lease state must include readError"
      });
    }
    if (lease.state === "stale" && isBlank(lease.staleReason)) {
      context.addIssue({
        code: "custom",
        path: ["staleReason"],
        message: "stale operation lease state must include staleReason"
      });
    }
  });

export const platformOperationStateSchema = z
  .object({
    activeOperation: requiredNullableString,
    install: runtimeInstallOperationStateSchema,
    lease: runtimeOperationLeaseStateSchema
  })
  .passthrough();

export const platformWorkflowOperationSchema = z
  .object({
    schemaVersion: z.literal(1),
    operationId: z.string().min(1),
    kind: z.enum([
      "update-verify",
      "update-apply",
      "rollback",
      "uninstall",
      "support-export"
    ]),
    state: z.enum(["accepted", "running", "completed", "failed"]),
    startedAt: z.string().min(1),
    updatedAt: z.string().min(1),
    release: z
      .object({
        platformVersion: z.string().min(1),
        runtimeBundleVersion: z.string().min(1)
      })
      .nullable(),
    artifact: z
      .object({
        path: z.string().min(1),
        sha256: z.string().regex(/^[0-9a-f]{64}$/),
        sizeBytes: z.number().int().nonnegative()
      })
      .nullable(),
    failure: z
      .object({ kind: z.string().min(1), message: z.string().min(1) })
      .nullable()
  })
  .strict()
  .superRefine((operation, context) => {
    if (operation.state === "failed" && operation.failure === null) {
      context.addIssue({
        code: "custom",
        path: ["failure"],
        message: "failed Platform workflow must include failure evidence"
      });
    }
    if (operation.state !== "failed" && operation.failure !== null) {
      context.addIssue({
        code: "custom",
        path: ["failure"],
        message: "non-failed Platform workflow must not include failure evidence"
      });
    }
    if (
      operation.kind === "support-export" &&
      operation.state === "completed" &&
      operation.artifact === null
    ) {
      context.addIssue({
        code: "custom",
        path: ["artifact"],
        message: "completed support export must include artifact evidence"
      });
    }
    if (
      operation.artifact !== null &&
      (operation.kind !== "support-export" || operation.state !== "completed")
    ) {
      context.addIssue({
        code: "custom",
        path: ["artifact"],
        message: "artifact evidence is only valid for a completed support export"
      });
    }
  });

export const platformWorkflowResourceSchema = z
  .object({
    state: z.enum(["loaded", "missing", "unavailable", "failed"]),
    operation: platformWorkflowOperationSchema.nullable(),
    readError: z.string().nullable()
  })
  .strict()
  .superRefine((resource, context) => {
    if (resource.state === "loaded" && resource.operation === null) {
      context.addIssue({ code: "custom", path: ["operation"], message: "loaded workflow resource must include operation" });
    }
    if ((resource.state === "unavailable" || resource.state === "failed") && isBlank(resource.readError)) {
      context.addIssue({ code: "custom", path: ["readError"], message: `${resource.state} workflow resource must include readError` });
    }
  });

export const runtimeBackupSchema = z
  .object({
    path: z.string().optional(),
    sizeBytes: nullableNumber
  })
  .passthrough();

export const runtimeEventDocumentSchema = z
  .object({
    schemaVersion: z.literal(1),
    id: z.string(),
    source: z.string(),
    eventType: runtimeEventTypeSchema,
    timestamp: z.string(),
    operationId: z.string(),
    operationService: z.string(),
    operationCommand: z.string(),
    operationState: z.enum([
      "accepted",
      "running",
      "completed",
      "failed",
      "cancelled",
      "interrupted"
    ]),
    message: z.string(),
    failure: z
      .object({
        kind: z.string(),
        message: z.string()
      })
      .nullable()
  })
  .strict();

export const runtimeEventHistorySchema = z
  .object({
    events: z.array(runtimeEventDocumentSchema),
    nextCursor: requiredNullableString,
    matchingCount: z.number().int().nonnegative().nullable()
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

const recorderRedisIPSyncStatusSchema = z.enum([
  "unknown",
  "unavailable",
  "disabled",
  "pending",
  "written",
  "correcting",
  "corrected",
  "verified",
  "mismatch",
  "write_failed",
  "verify_failed"
]);

const recorderRedisIPSyncObservationSchema = z
  .object({
    status: recorderRedisIPSyncStatusSchema,
    redisKey: requiredNullableString,
    selectedIp: requiredNullableString,
    ipSource: requiredNullableString,
    redisValue: requiredNullableString,
    lastWriteAt: requiredNullableString,
    lastVerifiedAt: requiredNullableString,
    lastFailure: requiredNullableString
  })
  .passthrough();

const recorderObservabilitySchema = z
  .object({
    state: z.enum(["loaded", "notReported", "unavailable"]),
    vrcode: z.string(),
    supportState: z.enum(["supported", "unsupported", "unknown"]),
    supportSource: requiredNullableString,
    reportState: z.enum([
      "notEvaluated",
      "awaitingFirstReport",
      "current",
      "stale",
      "missing",
      "readFailed"
    ]),
    profileState: requiredNullableString.optional(),
    collectionState: requiredNullableString.optional(),
    latestObservationReceivedAt: requiredNullableString.optional(),
    lastBootStartedAt: requiredNullableString.optional(),
    readIssueCount: z.number().int().nonnegative().nullable().optional(),
    operationalHealthState: z
      .enum(["healthy", "warning", "critical", "unknown"])
      .optional(),
    operationalIssueCount: z.number().int().nonnegative().optional(),
    expectedSince: requiredNullableString.optional(),
    recorderVersion: requiredNullableString.optional(),
    producerVersion: requiredNullableString.optional(),
    protocolVersion: requiredNullableString.optional(),
    readError: requiredNullableString.optional()
  })
  .passthrough();

const vitalDBRecorderRecordSchema = z
  .object({
    vrcode: z.string(),
    status: recorderStatusSchema,
    lastIP: requiredNullableString,
    version: requiredNullableString,
    bedID: requiredNullableString,
    bedName: requiredNullableString,
    patientConnected: requiredNullableBoolean,
    firstSeenAt: requiredNullableString,
    lastSeenAt: requiredNullableString,
    observationCount: z.number(),
    duplicateObservationCount: z.number(),
    currentAnomalyCount: z.number(),
    latestAnomalyKind: vitalDBAnomalyKindSchema.nullable(),
    latestAnomalySeverity: anomalySeveritySchema.nullable(),
    latestAnomalyMessage: requiredNullableString,
    latestAnomalyObservedAt: requiredNullableString,
    presentInLatestObservation: z.boolean(),
    visibility: vitalDBRecordVisibilitySchema,
    activityTimeline: z.array(recorderActivityPointSchema).nullable(),
    redisIPSync: recorderRedisIPSyncObservationSchema.nullable(),
    observability: recorderObservabilitySchema.optional()
  })
  .passthrough();

const vitalDBBedRecordSchema = z
  .object({
    bedID: z.string(),
    name: requiredNullableString,
    vrcode: requiredNullableString,
    linkedRecorderStatus: recorderStatusSchema.nullable(),
    linkedRecorderIP: requiredNullableString,
    linkedRecorderLastSeenAt: requiredNullableString,
    status: bedStatusSchema,
    patientConnected: requiredNullableBoolean,
    firstSeenAt: requiredNullableString,
    lastSeenAt: requiredNullableString,
    observationCount: z.number(),
    duplicateObservationCount: z.number(),
    currentAnomalyCount: z.number(),
    latestAnomalyKind: vitalDBAnomalyKindSchema.nullable(),
    latestAnomalySeverity: anomalySeveritySchema.nullable(),
    latestAnomalyMessage: requiredNullableString,
    latestAnomalyObservedAt: requiredNullableString,
    visibility: vitalDBRecordVisibilitySchema
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

const vitalDBBedHistorySummarySchema = z
  .object({
    knownBeds: z.number(),
    onlineBeds: z.number(),
    staleBeds: z.number(),
    bedAssignments: z.number(),
    bedAnomalies: z.number()
  })
  .passthrough();

const recorderActivityHistorySourceSchema = z.enum([
  "readModelProjection",
  "unavailable",
  "notProvided"
]);

const recorderActivityHistorySchema = z
  .object({
    source: recorderActivityHistorySourceSchema,
    bucketCount: z.number(),
    earliestBucketStartedAt: requiredNullableString,
    latestBucketStartedAt: requiredNullableString,
    readError: requiredNullableString
  })
  .passthrough();

export const vitalDBRecordersSchema = z
  .object({
    state: vitalRecorderHistoryStateSchema,
    updatedAt: requiredNullableString,
    recorders: z.array(vitalDBRecorderRecordSchema),
    beds: z.array(vitalDBBedRecordSchema),
    summary: vitalDBRecorderHistorySummarySchema,
    activityHistory: recorderActivityHistorySchema,
    recorderIngressStatusRead: runtimeRecorderIngressStatusReadResultSchema.nullable(),
    readError: requiredNullableString
  })
  .passthrough();

const recorderActivityWindowQuerySchema = z
  .object({
    vrcode: z.string(),
    bucketSeconds: z.union([z.literal(60), z.literal(300)]),
    period: z.enum(["lastHour", "last4Hours", "last8Hours", "last12Hours", "all"]),
    pageIndex: z.number().int().nullable().optional()
  })
  .strict();

const recorderActivityWindowPageSchema = z
  .object({
    index: z.number().int(),
    count: z.number().int(),
    windowSeconds: z.number(),
    windowStartedAt: requiredNullableString,
    windowEndedAt: requiredNullableString,
    firstBucketStartedAt: requiredNullableString,
    latestBucketStartedAt: requiredNullableString
  })
  .strict();

export const recorderActivityWindowSchema = z
  .object({
    state: z.enum(["loaded", "empty", "invalidRequest", "readFailed"]),
    query: recorderActivityWindowQuerySchema,
    page: recorderActivityWindowPageSchema,
    buckets: z.array(
      z
        .object({
          bucketStartedAt: z.string(),
          bucketSeconds: z.number(),
          messageCount: z.number(),
          byteCount: z.number(),
          roomCount: z.number()
        })
        .strict()
    ),
    latestSampleAt: requiredNullableString,
    readError: requiredNullableString
  })
  .strict()
  .superRefine((window, context) => {
    if ((window.state === "invalidRequest" || window.state === "readFailed") && isBlank(window.readError)) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: `${window.state} activity windows must include readError`
      });
    }
  });

const recorderVitalFileHistoryStateSchema = z.enum([
  "loaded",
  "partiallyLoaded",
  "readFailed"
]);

const recorderVitalFileSourceReadSchema = z
  .object({
    state: recorderVitalFileHistoryStateSchema,
    readError: requiredNullableString
  })
  .strict();

const recorderVitalFileAttributionSchema = z
  .object({
    state: z.enum([
      "recorderDeclared",
      "bedAssignmentResolved",
      "recoveryReceipt"
    ]),
    assignmentID: requiredNullableString,
    resolvedAt: z.string(),
    readError: requiredNullableString
  })
  .strict();

const recorderVitalFileFailureSchema = z
  .object({
    stage: z.string(),
    code: z.string(),
    message: z.string(),
    failedAt: z.string()
  })
  .strict();

const recorderVitalFileSchema = z
  .object({
    fileID: z.string(),
    origin: z.enum(["nativeRecorderUpload", "coldPathRecovery"]),
    vrcode: z.string(),
    bedName: requiredNullableString,
    filename: z.string(),
    sizeBytes: z.number().int().nonnegative(),
    status: z.enum([
      "receiving",
      "reconciling",
      "indexed",
      "failed",
      "notRequested",
      "publishRequested",
      "publishing",
      "published",
      "unknownLegacy"
    ]),
    receivedAt: z.string(),
    recordingStartedAt: requiredNullableString,
    recordingEndedAt: requiredNullableString,
    uploadedAt: requiredNullableString,
    attribution: recorderVitalFileAttributionSchema,
    failure: recorderVitalFileFailureSchema.nullable()
  })
  .strict();

export const recorderVitalFileHistorySchema = z
  .object({
    state: recorderVitalFileHistoryStateSchema,
    vrcode: z.string(),
    files: z.array(recorderVitalFileSchema),
    unattributedCount: z.number().int().nonnegative(),
    sources: z
      .object({
        nativeUpload: recorderVitalFileSourceReadSchema,
        coldPathRecovery: recorderVitalFileSourceReadSchema
      })
      .strict(),
    readError: requiredNullableString
  })
  .strict();

const recorderObservabilityReadingSchema = z
  .object({
    state: z.enum(["ok", "missing", "invalid", "failed", "unsupported"]),
    value: z.union([
      z.null(),
      z.boolean(),
      z.number(),
      z.string(),
      z.array(z.unknown()),
      z.record(z.string(), z.unknown())
    ]),
    detail: requiredNullableString,
    observedAt: requiredNullableString
  })
  .strict();

export const recorderObservabilityDetailSchema = z
  .object({
    state: z.enum(["loaded", "notReported", "unavailable"]),
    vrcode: z.string(),
    support: z
      .object({
        state: z.enum(["supported", "unsupported", "unknown"]),
        source: requiredNullableString,
        expectedSince: requiredNullableString,
        recorderVersion: requiredNullableString,
        producerVersion: requiredNullableString,
        protocolVersion: requiredNullableString
      })
      .strict(),
    report: z
      .object({
        state: z.enum([
          "notEvaluated",
          "awaitingFirstReport",
          "current",
          "stale",
          "missing",
          "readFailed"
        ]),
        receivedAt: requiredNullableString,
        deviceObservedAt: requiredNullableString,
        collectionState: requiredNullableString,
        readIssueCount: z.number().int().nonnegative()
      })
      .strict(),
    profile: z
      .object({
        state: z.enum(["associated", "unassociated", "missing", "invalid"]),
        receivedAt: requiredNullableString,
        deviceObservedAt: requiredNullableString,
        deviceId: requiredNullableString,
        bootId: requiredNullableString,
        software: z.record(z.string(), recorderObservabilityReadingSchema),
        collection: z
          .object({
            powerIntervalSeconds: z.number().int().nullable(),
            telemetryIntervalSeconds: z.number().int().nullable(),
            observationIntervalSeconds: z.number().int().nullable()
          })
          .strict()
          .nullable(),
        capabilities: z.record(
          z.string(),
          z
            .object({
              state: z.string(),
              source: requiredNullableString,
              detail: requiredNullableString
            })
            .strict()
        )
      })
      .strict(),
    boot: z
      .object({
        state: z.enum(["notReported", "started", "shutdownClean", "nonOrderable"]),
        orderingState: z.enum(["ordered", "nonOrderable", "unknown"]),
        bootId: requiredNullableString,
        startedAt: requiredNullableString,
        cleanShutdownAt: requiredNullableString
      })
      .strict(),
    evidenceHealth: z
      .object({
        state: z.enum([
          "notReported",
          "healthy",
          "degraded",
          "failed",
          "stale",
          "unsupported",
          "invalid"
        ]),
        checkedAt: requiredNullableString,
        checkCount: z.number().int().nonnegative(),
        detail: requiredNullableString
      })
      .strict(),
    incidentState: z
      .object({
        state: z.enum(["notReported", "reported", "invalid"]),
        policyVersion: requiredNullableString,
        bootLoopState: z
          .enum(["none", "warning", "critical", "unknown"])
          .nullable(),
        repeatedUndervoltageState: z
          .enum(["none", "warning", "critical", "unknown"])
          .nullable(),
        evidenceState: z
          .enum(["healthy", "degraded", "failed", "stale", "unsupported"])
          .nullable(),
        consecutiveUnexpectedBoots: z.number().int().nonnegative().nullable(),
        undervoltageBootsConsidered: z.number().int().nonnegative().nullable()
      })
      .strict(),
    operationalHealth: z
      .object({
        state: z.enum(["healthy", "warning", "critical", "unknown"]),
        evaluatedAt: requiredNullableString,
        issueCount: z.number().int().nonnegative(),
        issues: z.array(
          z
            .object({
              code: z.string(),
              category: z.enum([
                "boot",
                "power",
                "storage",
                "service",
                "time",
                "temperature",
                "memory",
                "evidence"
              ]),
              severity: z.enum(["warning", "critical"]),
              title: z.string(),
              detail: z.string(),
              field: z.string()
            })
            .strict()
        )
      })
      .strict()
      .superRefine((health, context) => {
        if (health.issueCount !== health.issues.length) {
          context.addIssue({
            code: "custom",
            path: ["issueCount"],
            message: "operational health issueCount must match issues"
          });
        }
      }),
    readings: z
      .object({
        temperatureCelsius: recorderObservabilityReadingSchema,
        memoryAvailableBytes: recorderObservabilityReadingSchema,
        memoryTotalBytes: recorderObservabilityReadingSchema,
        rootUsedPercent: recorderObservabilityReadingSchema,
        dataUsedPercent: recorderObservabilityReadingSchema,
        recorderActiveState: recorderObservabilityReadingSchema,
        publisherActiveState: recorderObservabilityReadingSchema,
        publisherBufferBytes: recorderObservabilityReadingSchema,
        publisherBufferLimitBytes: recorderObservabilityReadingSchema,
        networkInterfaces: z.array(
          z
            .object({
              name: z.string(),
              operState: recorderObservabilityReadingSchema,
              carrier: recorderObservabilityReadingSchema,
              rxErrors: recorderObservabilityReadingSchema,
              txErrors: recorderObservabilityReadingSchema
            })
            .strict()
        )
      })
      .strict(),
    readIssues: z.array(
      z
        .object({
          field: z.string(),
          state: z.string(),
          detail: z.string()
        })
        .strict()
    ),
    readError: requiredNullableString
  })
  .strict()
  .superRefine((detail, context) => {
    if (detail.state === "unavailable" && isBlank(detail.readError)) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: "unavailable Recorder observability detail must include readError"
      });
    }
    if (detail.state !== "unavailable" && detail.readError !== null) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: "successful Recorder observability detail cannot include readError"
      });
    }
  });

const recorderObservabilityMetricBucketSchema = z
  .object({
    average: z.number().nullable(),
    stateCounts: z.record(z.string(), z.number().int().nonnegative())
  })
  .strict();

export const recorderObservabilityTimelineSchema = z
  .object({
    state: z.enum(["loaded", "notReported", "unsupported", "unavailable"]),
    vrcode: z.string(),
    supportState: z.enum(["supported", "unsupported", "unknown"]).nullable(),
    timeBasis: z.literal("receivedAt"),
    query: z
      .object({
        from: z.string(),
        until: z.string(),
        bucketSeconds: z.union([z.literal(300), z.literal(900), z.literal(3600)])
      })
      .strict()
      .nullable(),
    buckets: z.array(
      z
        .object({
          bucketStartedAt: z.string(),
          sampleCount: z.number().int().nonnegative(),
          metrics: z.record(z.string(), recorderObservabilityMetricBucketSchema)
        })
        .strict()
    ),
    readError: requiredNullableString
  })
  .strict()
  .superRefine((timeline, context) => {
    if (timeline.state === "unavailable" && isBlank(timeline.readError)) {
      context.addIssue({ code: "custom", path: ["readError"], message: "required" });
    }
    if (timeline.state !== "unavailable" && timeline.query === null) {
      context.addIssue({ code: "custom", path: ["query"], message: "required" });
    }
  });

export const recorderObservabilityIncidentsSchema = z
  .object({
    state: z.enum(["loaded", "unavailable"]),
    vrcode: z.string(),
    timeBasis: z.literal("receivedAt"),
    incidents: z.array(
      z
        .object({
          recordId: z.string(),
          eventId: z.string(),
          incidentId: z.string(),
          category: z.enum(["kernel", "boot", "power", "evidence"]),
          code: z.string(),
          severity: z.enum(["warning", "critical"]),
          state: z.enum(["active", "recovering", "historical"]),
          bootId: requiredNullableString,
          occurredAt: requiredNullableString,
          receivedAt: z.string(),
          timeState: requiredNullableString,
          summary: z.string(),
          evidence: z.array(
            z
              .object({
                field: z.string(),
                state: z.string(),
                detail: requiredNullableString
              })
              .strict()
          ),
          source: z.enum(["kernelIncident", "bootEvent", "observation"]),
          capturedAt: requiredNullableString,
          captureTimeState: requiredNullableString,
          incidentType: z.enum([
            "panic",
            "oops",
            "watchdog",
            "lockup",
            "unknown",
            "boot-loop",
            "repeated-undervoltage",
            "ledger-continuity"
          ]),
          incidentBootId: requiredNullableString,
          messageExcerpt: requiredNullableString,
          truncated: z.boolean()
        })
        .strict()
    ),
    nextCursor: requiredNullableString,
    readError: requiredNullableString
  })
  .strict()
  .superRefine((incidents, context) => {
    if (incidents.state === "unavailable" && isBlank(incidents.readError)) {
      context.addIssue({ code: "custom", path: ["readError"], message: "required" });
    }
  });

export const runtimeReleaseInfoSchema = z
  .object({
    helperVersion: z.string().optional(),
    minimumUpdaterVersion: z.string().optional(),
    vitalServerVersion: z.string().optional(),
    services: z
      .array(
        z.object({
          name: z.string().optional(),
          image: z.string().optional(),
          version: z.string().optional()
        }).strict()
      )
      .optional()
  })
  .strict();

export const runtimeInstallInfoSchema = z
  .object({
    appBundlePath: z.string().optional(),
    packageIdentifier: z.string().optional(),
    runtimeHomePath: z.string().optional(),
    backupsPath: z.string().optional(),
    redisBackupsPath: z.string().optional(),
    runtimeDataBackupsPath: z.string().optional()
  })
  .strict();

export const vitalDBBedsSchema = z
  .object({
    state: vitalRecorderHistoryStateSchema,
    updatedAt: requiredNullableString,
    beds: z.array(vitalDBBedRecordSchema),
    summary: vitalDBBedHistorySummarySchema,
    readError: requiredNullableString
  })
  .passthrough();

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
    eventTotalCount: z.number().int().nonnegative(),
    eventLimit: z.number().int().positive(),
    readError: requiredNullableString
  })
  .passthrough()
  .superRefine((history, context) => {
    if (
      history.events.length > history.eventLimit ||
      history.events.length > history.eventTotalCount
    ) {
      context.addIssue({
        code: "custom",
        path: ["events"],
        message: "relationship event page metadata is invalid"
      });
    }
    if (history.state === "partiallyLoaded" && isBlank(history.readError)) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: "partially loaded VitalDB relationship history must include readError"
      });
    }
    if (history.state === "readFailed" && isBlank(history.readError)) {
      context.addIssue({
        code: "custom",
        path: ["readError"],
        message: "failed VitalDB relationship history must include readError"
      });
    }
  });

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

const runtimeLabReadStateSchema = z.enum(["loaded", "unavailable", "failed"]);

const runtimeLabSessionStateSchema = z.enum([
  "accepted",
  "running",
  "stopping",
  "stopped",
  "finished",
  "failed",
  "unavailable"
]);

const runtimeLabArchiveFinalizationStateSchema = z.enum([
  "queued",
  "processing",
  "retrying",
  "exported",
  "published",
  "failed",
  "partial",
  "missing",
  "unavailable"
]);

const runtimeLabArchiveFinalizationSchema = z
  .object({
    state: runtimeLabArchiveFinalizationStateSchema,
    updatedAt: requiredNullableString,
    readError: requiredNullableString
  })
  .strict();

const runtimeLabSessionFailureSchema = z
  .object({
    stage: z.string().min(1),
    code: z.string().min(1),
    message: z.string().min(1),
    failedAt: z.string().min(1)
  })
  .strict();

const runtimeLabRecorderSendStateSchema = z.enum([
  "notAttempted",
  "skipped",
  "sent",
  "failed"
]);

const runtimeLabScenarioSchema = z
  .object({
    scenarioId: z.string(),
    name: z.string(),
    category: z.string(),
    description: nullableString
  })
  .passthrough();

const runtimeLabSessionSchema = z
  .object({
    sessionId: z.string(),
    state: runtimeLabSessionStateSchema,
    scenarioId: z.string(),
    name: nullableString,
    recorderCount: z.number(),
    targetURL: z.string().nullable(),
    failure: runtimeLabSessionFailureSchema.optional(),
    archiveFinalization: runtimeLabArchiveFinalizationSchema.nullable().optional(),
    createdAt: nullableString,
    updatedAt: nullableString
  })
  .passthrough();

const runtimeLabBedSchema = z
  .object({
    bedId: z.string(),
    sessionId: z.string(),
    name: z.string(),
    state: runtimeLabSessionStateSchema,
    createdAt: nullableString,
    updatedAt: nullableString
  })
  .passthrough();

const runtimeLabRecorderSchema = z
  .object({
    recorderId: z.string(),
    sessionId: z.string(),
    bedId: z.string(),
    vrcode: z.string(),
    state: runtimeLabSessionStateSchema,
    createdAt: nullableString,
    updatedAt: nullableString,
    messagesSent: z.number(),
    lastSendState: runtimeLabRecorderSendStateSchema,
    lastSendAt: nullableString,
    lastSendError: nullableString
  })
  .passthrough();

const runtimeLabVitalFileSchema = z
  .object({
    displayName: z.string(),
    relativePath: z.string(),
    guestPath: z.string(),
    sizeBytes: z.number(),
    modifiedAt: nullableString
  })
  .passthrough();

export const runtimeLabScenarioListSchema = z
  .object({
    state: runtimeLabReadStateSchema,
    scenarios: z.array(runtimeLabScenarioSchema),
    readError: nullableString
  })
  .passthrough();

export const runtimeLabBedListSchema = z
  .object({
    state: runtimeLabReadStateSchema,
    beds: z.array(runtimeLabBedSchema),
    readError: nullableString
  })
  .passthrough();

export const runtimeLabRecorderListSchema = z
  .object({
    state: runtimeLabReadStateSchema,
    recorders: z.array(runtimeLabRecorderSchema),
    readError: nullableString
  })
  .passthrough();

export const runtimeLabRecorderResponseSchema = z
  .object({
    state: runtimeLabReadStateSchema,
    recorder: runtimeLabRecorderSchema.nullable().optional(),
    operationId: nullableString,
    labOperationId: nullableString,
    readError: nullableString
  })
  .passthrough();

export const runtimeLabSessionListSchema = z
  .object({
    state: runtimeLabReadStateSchema,
    sessions: z.array(runtimeLabSessionSchema),
    readError: nullableString
  })
  .passthrough();

export const runtimeLabVitalFileListSchema = z
  .object({
    state: runtimeLabReadStateSchema,
    vitalFiles: z.array(runtimeLabVitalFileSchema),
    readError: nullableString
  })
  .passthrough();

export const runtimeLabSessionResponseSchema = z
  .object({
    state: runtimeLabReadStateSchema,
    session: runtimeLabSessionSchema.nullable().optional(),
    operationId: nullableString,
    labOperationId: nullableString,
    readError: nullableString
  })
  .passthrough();

export const runtimeLabVitalFileUploadResponseSchema = z
  .object({
    state: z.enum(["completed", "partial", "failed"]),
    files: z.array(
      z.object({
        fileName: z.string(),
        relativePath: z.string(),
        sizeBytes: z.number().int().nonnegative()
      })
      .strict()
    ),
    failedFiles: z.array(
      z.object({
        fileName: z.string(),
        reason: z.string()
      })
      .strict()
    )
  })
  .strict();

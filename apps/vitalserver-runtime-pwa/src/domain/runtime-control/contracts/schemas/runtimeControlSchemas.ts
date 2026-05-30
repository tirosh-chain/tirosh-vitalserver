import { z } from "zod";

const nullableString = z.string().nullable().optional();
const nullableNumber = z.number().nullable().optional();
const nullableBoolean = z.boolean().nullable().optional();
const unknownRecord = z.record(z.string(), z.unknown());
const resourceUsageSchema = unknownRecord.nullable();
const runtimeStateSchema = z.enum([
  "installing",
  "updating",
  "recovering",
  "healthy",
  "degraded",
  "critical"
]);
const vmStateSchema = z
  .enum([
    "not-installed",
    "stopped",
    "starting",
    "running",
    "stale",
    "unreachable",
    "failed"
  ])
  .nullable();
const runtimeEventTypeSchema = z.enum([
  "status-changed",
  "progress-updated",
  "health-observed",
  "recovery-triggered",
  "recovery-completed",
  "recovery-suppressed",
  "domain-error-observed",
  "vm-error-observed",
  "container-observed",
  "audit-proxy-observed",
  "vitaldb-observed",
  "vitaldb-observer-unhealthy",
  "vitaldb-anomaly-detected",
  "watchdog-skipped",
  "recovery-planned",
  "service-restart-dispatched",
  "observability-store-failed",
  "runtime-status-observed",
  "guest-state-observed",
  "runtime-command-started",
  "runtime-command-completed",
  "runtime-command-failed"
]);
const recorderStatusSchema = z.enum(["online", "stale", "offline", "unknown"]);
const bedStatusSchema = z.enum(["online", "stale", "offline", "unknown"]);
const anomalySeveritySchema = z.enum(["info", "warning", "critical"]);
const vitalDBAnomalyKindSchema = z.enum([
  "offline",
  "duplicate-ip",
  "backend-unavailable",
  "stale-recorder",
  "observer-unhealthy"
]);
const networkModeSchema = z.enum(["shared", "bridged"]);
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
  "auditProxy",
  "unavailable"
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
    canInstallRuntime: z.boolean().optional(),
    canUninstallRuntime: z.boolean().optional(),
    canApplyBundle: z.boolean().optional(),
    canRollback: z.boolean().optional(),
    canEditVMResources: z.boolean().optional(),
    canEditNetworkExposure: z.boolean().optional(),
    canResetAdminPassword: z.boolean().optional(),
    canOpenLocalFiles: z.boolean().optional(),
    canStreamLogs: z.boolean().optional(),
    canControlRuntimeServices: z.boolean().optional(),
    canExportLogs: z.boolean().optional(),
    canViewReleaseMetadata: z.boolean().optional(),
    canUseTestTools: z.boolean().optional()
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
      )
      .optional(),
    cpuCount: z.number().optional(),
    memoryGiB: z.number().optional(),
    diskGiB: z.number().optional(),
    minimumDiskGiB: z.number().optional(),
    networkMode: networkModeSchema.optional(),
    bridgedInterface: z.string().optional(),
    proxyPort: z.number().optional(),
    runtimeControlPort: z.number().optional(),
    vitalFilesDirectory: z.string().optional(),
    publicHost: z.string().optional(),
    publicPort: z.number().optional(),
    adminPassword: z.string().optional(),
    changeAdminPassword: z.boolean().optional(),
    startOnBoot: z.boolean().optional(),
    startOnBootConfigurable: z.boolean().optional(),
    autoRecoveryEnabled: z.boolean().optional(),
    preventSystemSleep: z.boolean().optional(),
    redisBackupRetentionCount: z.number().optional(),
    restartAfterSave: z.boolean().optional()
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

const runtimeContainerObservationSchema = z
  .object({
    auditProxyHTTP: z.string().optional(),
    auditProxyStatus: unknownRecord.nullable().optional(),
    runtimeStateUpdatedAt: nullableString,
    runtimeStateFileUpdatedAt: nullableString,
    containerLogsPresent: z.boolean().optional(),
    containerLogsBytes: nullableNumber,
    containerLogsUpdatedAt: nullableString,
    composeServices: z.array(unknownRecord).optional()
  })
  .passthrough();

const vitalDBRecorderActivityObservationSchema = z
  .object({
    windowSeconds: z.number().optional(),
    messageCount: z.number().optional(),
    byteCount: z.number().optional(),
    roomCount: z.number().optional(),
    firstSeenAt: nullableString,
    lastSeenAt: nullableString,
    messagesPerSecond: z.number().optional(),
    bytesPerSecond: z.number().optional()
  })
  .passthrough();

const vitalDBRecorderObservationSchema = z
  .object({
    vrcode: z.string().optional(),
    ip: nullableString,
    lastSeenAt: nullableString,
    version: nullableString,
    info: nullableString,
    config: nullableString,
    online: z.boolean().optional(),
    stale: z.boolean().optional(),
    activity: vitalDBRecorderActivityObservationSchema.nullable().optional()
  })
  .passthrough();

const vitalDBBedObservationSchema = z
  .object({
    bedID: z.string().optional(),
    name: nullableString,
    vrcode: nullableString,
    lastSeenAt: nullableString,
    patientConnected: nullableBoolean,
    online: z.boolean().optional()
  })
  .passthrough();

const vitalDBAnomalyObservationSchema = z
  .object({
    id: z.string().optional(),
    kind: vitalDBAnomalyKindSchema.optional(),
    severity: anomalySeveritySchema.optional(),
    observedAt: z.string().optional(),
    subject: z.string().optional(),
    message: z.string().optional()
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
    anomalies: z.array(vitalDBAnomalyObservationSchema)
  })
  .passthrough();

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
    source: vitalRecorderSummarySourceSchema.optional(),
    activeConnections: z.number().optional(),
    knownRecorders: z.number().optional(),
    onlineRecorders: z.number().optional(),
    staleRecorders: z.number().optional(),
    knownBeds: z.number().optional(),
    recorderAnomalies: z.number().optional(),
    observedAt: nullableString,
    latestRecorder: z
      .object({
        vrcode: z.string().optional(),
        ip: nullableString,
        lastSeenAt: nullableString,
        source: vitalRecorderSummarySourceSchema.optional()
      })
      .passthrough()
      .nullable()
      .optional()
  })
  .passthrough();

export const runtimeOverviewSchema = z
  .object({
    status: runtimeStatusSchema.optional(),
    settings: runtimeSettingsSchema.optional(),
    release: unknownRecord.optional(),
    install: unknownRecord.optional(),
    vitalDBObservation: vitalDBObservationSchema.nullable().optional(),
    vitalRecorder: runtimeVitalRecorderSummarySchema.optional()
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
    schemaVersion: z.number().optional(),
    id: z.string().optional(),
    source: z.string().optional(),
    eventType: runtimeEventTypeSchema.optional(),
    timestamp: z.string().optional(),
    product: z.string().optional(),
    status: runtimeStateSchema.optional(),
    previousStatus: nullableString,
    operation: z.string().optional(),
    message: z.string().optional(),
    runtimeVersion: z.string().optional(),
    vmState: vmStateSchema.optional(),
    vmErrors: z.array(z.string()).nullable().optional(),
    failureReasons: z.array(z.string()).optional(),
    domainErrors: z.array(runtimeDomainErrorSchema).nullable().optional(),
    containerObservation: runtimeContainerObservationSchema.nullable().optional(),
    progress: unknownRecord.nullable().optional(),
    vitalDBObservation: vitalDBObservationSchema.nullable().optional()
  })
  .passthrough();

export const runtimeEventHistorySchema = z
  .object({
    events: z.array(runtimeEventDocumentSchema).optional(),
    nextCursor: nullableString,
    matchingCount: nullableNumber
  })
  .passthrough();

const recorderActivityBucketSchema = z
  .object({
    bucketStartedAt: z.string().optional(),
    bucketSeconds: z.number().optional(),
    messageCount: z.number().optional(),
    byteCount: z.number().optional(),
    roomCount: z.number().optional()
  })
  .passthrough();

const recorderActivityPointSchema = z
  .object({
    observedAt: z.string().optional(),
    windowSeconds: z.number().optional(),
    messageCount: z.number().optional(),
    byteCount: z.number().optional(),
    roomCount: z.number().optional(),
    messagesPerSecond: z.number().optional(),
    bytesPerSecond: z.number().optional(),
    buckets: z.array(recorderActivityBucketSchema).optional()
  })
  .passthrough();

const vitalDBRecorderRecordSchema = z
  .object({
    vrcode: z.string().optional(),
    status: recorderStatusSchema.optional(),
    lastIP: nullableString,
    version: nullableString,
    bedID: nullableString,
    bedName: nullableString,
    patientConnected: nullableBoolean,
    firstSeenAt: nullableString,
    lastSeenAt: nullableString,
    observationCount: z.number().optional(),
    currentAnomalyCount: z.number().optional(),
    latestAnomalySeverity: anomalySeveritySchema.nullable().optional(),
    presentInLatestObservation: z.boolean().optional(),
    activityTimeline: z.array(recorderActivityPointSchema).optional()
  })
  .passthrough();

const vitalDBBedRecordSchema = z
  .object({
    bedID: z.string().optional(),
    name: nullableString,
    vrcode: nullableString,
    status: bedStatusSchema.optional(),
    patientConnected: nullableBoolean,
    firstSeenAt: nullableString,
    lastSeenAt: nullableString,
    observationCount: z.number().optional(),
    currentAnomalyCount: z.number().optional(),
    latestAnomalySeverity: anomalySeveritySchema.nullable().optional()
  })
  .passthrough();

export const vitalDBRecordersSchema = z
  .object({
    updatedAt: nullableString,
    recorders: z.array(vitalDBRecorderRecordSchema).optional(),
    beds: z.array(vitalDBBedRecordSchema).optional()
  })
  .passthrough();

export const vitalDBBedsSchema = z.array(vitalDBBedRecordSchema);

export const runtimeLogTextResponseSchema = z
  .object({
    text: z.string().optional()
  })
  .passthrough();

export const runtimeLogExportResultSchema = z
  .object({
    destination: z.string().optional()
  })
  .passthrough();

export const runtimeUpdateBundleSummaryResponseSchema = z
  .object({
    summary: z.string().optional()
  })
  .passthrough();

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
    scenario: nullableString,
    defaultScenario: z.string(),
    createdAt: nullableNumber,
    startedAt: nullableNumber,
    stoppedAt: nullableNumber,
    messagesSent: z.number(),
    bytesSent: z.number(),
    lastError: nullableString,
    cleanupErrors: z.array(runtimeTestKitCleanupErrorSchema),
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

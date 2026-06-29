import type { RuntimeSettings } from "@/domain/runtime-control/contracts/runtimeControlTypes";

const RECORDER_INGRESS_INTERNAL_REPLAY_BATCH_SIZE = 1000;

export type RuntimeSettingsDraft = {
  cpuCount: string;
  memoryGiB: string;
  diskGiB: string;
  proxyPort: string;
  runtimeControlPort: string;
  vitalFilesDirectory: string;
  publicHost: string;
  publicPort: string;
  recorderIngressLoadControlEnabled: boolean;
  recorderIngressSendDataReplayMaxMiBPerSecond: string;
  recorderIngressSendDataMaxPendingItems: string;
  recorderIngressSendDataMaxPendingMiB: string;
  recorderIngressSendDataMaxPayloadMiB: string;
  recorderIngressSendDataReplayedMaxItems: string;
  recorderIngressSendDataRealtimeMaxPendingItems: string;
  recorderIngressSendDataReplayIntervalMs: string;
  recorderIngressSendDataReplayMaxAttempts: string;
  recorderIngressSendDataReplayTargetTimeoutMs: string;
  recorderIngressSendDataReplayAdaptiveMinConcurrency: string;
  recorderIngressSendDataReplayAdaptiveMaxConcurrency: string;
  recorderIngressRawArchiveEnabled: boolean;
  recorderIngressRawArchiveMaxFileMiB: string;
  recorderIngressRawArchiveMaxFiles: string;
  recorderIngressRawArchiveAutoExportEnabled: boolean;
  recorderIngressRawArchiveAutoExportQuietSeconds: string;
  recorderIngressRawArchiveAutoExportScanIntervalSeconds: string;
  recorderIngressRawArchiveAutoExportCursorStableSeconds: string;
  recorderIngressRawArchiveAutoExportRetryDelaySeconds: string;
  recorderIngressRawArchiveAutoExportMaxAttempts: string;
  recorderIngressRawArchiveAutoExportRequestTimeoutSeconds: string;
  containerMemoryLimitsEnabled: boolean;
  vitalServerContainerMemoryLimitMiB: string;
  recorderIngressContainerMemoryLimitMiB: string;
  redisContainerMemoryLimitMiB: string;
  automaticBackupEnabled: boolean;
  backupScheduleTimes: string;
  backupRetentionCount: string;
  logArchiveRetentionDays: string;
  logArchiveMaximumGiB: string;
  redisRelayEnabled: boolean;
  redisRelayTargetURL: string;
  redisRelayUsername: string;
  redisRelayPassword: string;
  redisRelayClearPassword: boolean;
  redisRelayPasswordConfigured: boolean;
  redisRelayTLS: boolean;
  redisRelayScope: RuntimeSettings["redisRelay"]["scope"];
  redisRelayIncludeRecorderNetworkContext: boolean;
  startOnBoot: boolean;
  autoRecoveryEnabled: boolean;
  preventSystemSleep: boolean;
  restartAfterSave: boolean;
};

export const emptyRuntimeSettingsDraft: RuntimeSettingsDraft = {
  cpuCount: "",
  memoryGiB: "",
  diskGiB: "",
  proxyPort: "",
  runtimeControlPort: "",
  vitalFilesDirectory: "",
  publicHost: "",
  publicPort: "",
  recorderIngressLoadControlEnabled: true,
  recorderIngressSendDataReplayMaxMiBPerSecond: "",
  recorderIngressSendDataMaxPendingItems: "",
  recorderIngressSendDataMaxPendingMiB: "",
  recorderIngressSendDataMaxPayloadMiB: "",
  recorderIngressSendDataReplayedMaxItems: "",
  recorderIngressSendDataRealtimeMaxPendingItems: "",
  recorderIngressSendDataReplayIntervalMs: "",
  recorderIngressSendDataReplayMaxAttempts: "",
  recorderIngressSendDataReplayTargetTimeoutMs: "",
  recorderIngressSendDataReplayAdaptiveMinConcurrency: "",
  recorderIngressSendDataReplayAdaptiveMaxConcurrency: "",
  recorderIngressRawArchiveEnabled: true,
  recorderIngressRawArchiveMaxFileMiB: "",
  recorderIngressRawArchiveMaxFiles: "",
  recorderIngressRawArchiveAutoExportEnabled: true,
  recorderIngressRawArchiveAutoExportQuietSeconds: "",
  recorderIngressRawArchiveAutoExportScanIntervalSeconds: "",
  recorderIngressRawArchiveAutoExportCursorStableSeconds: "",
  recorderIngressRawArchiveAutoExportRetryDelaySeconds: "",
  recorderIngressRawArchiveAutoExportMaxAttempts: "",
  recorderIngressRawArchiveAutoExportRequestTimeoutSeconds: "",
  containerMemoryLimitsEnabled: true,
  vitalServerContainerMemoryLimitMiB: "",
  recorderIngressContainerMemoryLimitMiB: "",
  redisContainerMemoryLimitMiB: "",
  automaticBackupEnabled: false,
  backupScheduleTimes: "",
  backupRetentionCount: "",
  logArchiveRetentionDays: "",
  logArchiveMaximumGiB: "",
  redisRelayEnabled: false,
  redisRelayTargetURL: "",
  redisRelayUsername: "",
  redisRelayPassword: "",
  redisRelayClearPassword: false,
  redisRelayPasswordConfigured: false,
  redisRelayTLS: false,
  redisRelayScope: "vital_reconstruction",
  redisRelayIncludeRecorderNetworkContext: false,
  startOnBoot: false,
  autoRecoveryEnabled: false,
  preventSystemSleep: false,
  restartAfterSave: false
};

export function runtimeSettingsToDraft(
  settings: RuntimeSettings
): RuntimeSettingsDraft {
  return {
    cpuCount: formatNumber(settings.cpuCount),
    memoryGiB: formatNumber(settings.memoryGiB),
    diskGiB: formatNumber(settings.diskGiB),
    proxyPort: formatNumber(settings.proxyPort),
    runtimeControlPort: formatNumber(settings.runtimeControlPort),
    vitalFilesDirectory: settings.vitalFilesDirectory,
    publicHost: settings.publicHost,
    publicPort: formatNumber(settings.publicPort),
    recorderIngressLoadControlEnabled:
      settings.recorderIngressSendDataMode !== "passthrough",
    recorderIngressSendDataReplayMaxMiBPerSecond: formatNumber(
      settings.recorderIngressSendDataReplayMaxMiBPerSecond
    ),
    recorderIngressSendDataMaxPendingItems: formatNumber(
      settings.recorderIngress.sendDataMaxPendingItems
    ),
    recorderIngressSendDataMaxPendingMiB: formatNumber(
      settings.recorderIngress.sendDataMaxPendingMiB
    ),
    recorderIngressSendDataMaxPayloadMiB: formatNumber(
      settings.recorderIngress.sendDataMaxPayloadMiB
    ),
    recorderIngressSendDataReplayedMaxItems: formatNumber(
      settings.recorderIngress.sendDataReplayedMaxItems
    ),
    recorderIngressSendDataRealtimeMaxPendingItems: formatNumber(
      settings.recorderIngress.sendDataRealtimeMaxPendingItems
    ),
    recorderIngressSendDataReplayIntervalMs: formatNumber(
      settings.recorderIngress.sendDataReplayIntervalMs
    ),
    recorderIngressSendDataReplayMaxAttempts: formatNumber(
      settings.recorderIngress.sendDataReplayMaxAttempts
    ),
    recorderIngressSendDataReplayTargetTimeoutMs: formatNumber(
      settings.recorderIngress.sendDataReplayTargetTimeoutMs
    ),
    recorderIngressSendDataReplayAdaptiveMinConcurrency: formatNumber(
      settings.recorderIngress.sendDataReplayAdaptiveMinConcurrency
    ),
    recorderIngressSendDataReplayAdaptiveMaxConcurrency: formatNumber(
      settings.recorderIngress.sendDataReplayAdaptiveMaxConcurrency
    ),
    recorderIngressRawArchiveEnabled:
      settings.recorderIngress.rawArchiveEnabled,
    recorderIngressRawArchiveMaxFileMiB: formatNumber(
      settings.recorderIngress.rawArchiveMaxFileMiB
    ),
    recorderIngressRawArchiveMaxFiles: formatNumber(
      settings.recorderIngress.rawArchiveMaxFiles
    ),
    recorderIngressRawArchiveAutoExportEnabled:
      settings.recorderIngress.rawArchiveAutoExportEnabled,
    recorderIngressRawArchiveAutoExportQuietSeconds: formatNumber(
      settings.recorderIngress.rawArchiveAutoExportQuietSeconds
    ),
    recorderIngressRawArchiveAutoExportScanIntervalSeconds: formatNumber(
      settings.recorderIngress.rawArchiveAutoExportScanIntervalSeconds
    ),
    recorderIngressRawArchiveAutoExportCursorStableSeconds: formatNumber(
      settings.recorderIngress.rawArchiveAutoExportCursorStableSeconds
    ),
    recorderIngressRawArchiveAutoExportRetryDelaySeconds: formatNumber(
      settings.recorderIngress.rawArchiveAutoExportRetryDelaySeconds
    ),
    recorderIngressRawArchiveAutoExportMaxAttempts: formatNumber(
      settings.recorderIngress.rawArchiveAutoExportMaxAttempts
    ),
    recorderIngressRawArchiveAutoExportRequestTimeoutSeconds: formatNumber(
      settings.recorderIngress.rawArchiveAutoExportRequestTimeoutSeconds
    ),
    containerMemoryLimitsEnabled: settings.containerMemoryLimitsEnabled,
    vitalServerContainerMemoryLimitMiB: formatNumber(
      settings.vitalServerContainerMemoryLimitMiB
    ),
    recorderIngressContainerMemoryLimitMiB: formatNumber(
      settings.recorderIngressContainerMemoryLimitMiB
    ),
    redisContainerMemoryLimitMiB: formatNumber(
      settings.redisContainerMemoryLimitMiB
    ),
    automaticBackupEnabled: settings.automaticBackupEnabled,
    backupScheduleTimes: settings.backupScheduleTimes.join(", "),
    backupRetentionCount: formatNumber(settings.backupRetentionCount),
    logArchiveRetentionDays: formatNumber(settings.logArchiveRetentionDays),
    logArchiveMaximumGiB: formatNumber(settings.logArchiveMaximumGiB),
    redisRelayEnabled: settings.redisRelay.enabled,
    redisRelayTargetURL: settings.redisRelay.target.url,
    redisRelayUsername: settings.redisRelay.target.username,
    redisRelayPassword: "",
    redisRelayClearPassword: false,
    redisRelayPasswordConfigured: settings.redisRelay.target.passwordConfigured,
    redisRelayTLS: settings.redisRelay.target.tls,
    redisRelayScope: settings.redisRelay.scope,
    redisRelayIncludeRecorderNetworkContext:
      settings.redisRelay.includeRecorderNetworkContext,
    startOnBoot: settings.startOnBoot,
    autoRecoveryEnabled: settings.autoRecoveryEnabled,
    preventSystemSleep: settings.preventSystemSleep,
    restartAfterSave: settings.restartAfterSave
  };
}

export function draftToRuntimeSettings(
  draft: RuntimeSettingsDraft,
  current: RuntimeSettings,
  customAdvertisedURL: boolean
): RuntimeSettings {
  const proxyPort = requiredNumber(draft.proxyPort);
  return {
    ...current,
    cpuCount: requiredNumber(draft.cpuCount),
    memoryGiB: requiredNumber(draft.memoryGiB),
    diskGiB: requiredNumber(draft.diskGiB),
    minimumDiskGiB: current.minimumDiskGiB,
    networkMode: current.networkMode,
    bridgedInterface: current.bridgedInterface,
    proxyPort,
    runtimeControlPort: requiredNumber(draft.runtimeControlPort),
    vitalFilesDirectory: draft.vitalFilesDirectory.trim(),
    publicHost: customAdvertisedURL ? draft.publicHost.trim() : "",
    publicPort: customAdvertisedURL ? requiredNumber(draft.publicPort) : proxyPort,
    recorderIngressSendDataMode: draft.recorderIngressLoadControlEnabled
      ? "spool_and_replay"
      : "passthrough",
    recorderIngressSendDataReplayBatchSize: Math.max(
      current.recorderIngressSendDataReplayBatchSize,
      RECORDER_INGRESS_INTERNAL_REPLAY_BATCH_SIZE
    ),
    recorderIngressSendDataReplayMaxMiBPerSecond: requiredNumber(
      draft.recorderIngressSendDataReplayMaxMiBPerSecond
    ),
    recorderIngress: {
      ...current.recorderIngress,
      sendDataMaxPendingItems: requiredNumber(
        draft.recorderIngressSendDataMaxPendingItems
      ),
      sendDataMaxPendingMiB: requiredNumber(
        draft.recorderIngressSendDataMaxPendingMiB
      ),
      sendDataMaxPayloadMiB: requiredNumber(
        draft.recorderIngressSendDataMaxPayloadMiB
      ),
      sendDataReplayedMaxItems: requiredNumber(
        draft.recorderIngressSendDataReplayedMaxItems
      ),
      sendDataRealtimeMaxPendingItems: requiredNumber(
        draft.recorderIngressSendDataRealtimeMaxPendingItems
      ),
      sendDataReplayIntervalMs: requiredNumber(
        draft.recorderIngressSendDataReplayIntervalMs
      ),
      sendDataReplayMaxAttempts: requiredNumber(
        draft.recorderIngressSendDataReplayMaxAttempts
      ),
      sendDataReplayTargetTimeoutMs: requiredNumber(
        draft.recorderIngressSendDataReplayTargetTimeoutMs
      ),
      sendDataReplayAdaptiveMinConcurrency: requiredNumber(
        draft.recorderIngressSendDataReplayAdaptiveMinConcurrency
      ),
      sendDataReplayAdaptiveMaxConcurrency: requiredNumber(
        draft.recorderIngressSendDataReplayAdaptiveMaxConcurrency
      ),
      rawArchiveEnabled: true,
      rawArchiveMaxFileMiB: requiredNumber(
        draft.recorderIngressRawArchiveMaxFileMiB
      ),
      rawArchiveMaxFiles: requiredNumber(
        draft.recorderIngressRawArchiveMaxFiles
      ),
      rawArchiveAutoExportEnabled: true,
      rawArchiveAutoExportQuietSeconds: requiredNumber(
        draft.recorderIngressRawArchiveAutoExportQuietSeconds
      ),
      rawArchiveAutoExportScanIntervalSeconds: requiredNumber(
        draft.recorderIngressRawArchiveAutoExportScanIntervalSeconds
      ),
      rawArchiveAutoExportCursorStableSeconds: requiredNumber(
        draft.recorderIngressRawArchiveAutoExportCursorStableSeconds
      ),
      rawArchiveAutoExportRetryDelaySeconds: requiredNumber(
        draft.recorderIngressRawArchiveAutoExportRetryDelaySeconds
      ),
      rawArchiveAutoExportMaxAttempts: requiredNumber(
        draft.recorderIngressRawArchiveAutoExportMaxAttempts
      ),
      rawArchiveAutoExportRequestTimeoutSeconds: requiredNumber(
        draft.recorderIngressRawArchiveAutoExportRequestTimeoutSeconds
      )
    },
    containerMemoryLimitsEnabled: draft.containerMemoryLimitsEnabled,
    vitalServerContainerMemoryLimitMiB: requiredNumber(
      draft.vitalServerContainerMemoryLimitMiB
    ),
    recorderIngressContainerMemoryLimitMiB: requiredNumber(
      draft.recorderIngressContainerMemoryLimitMiB
    ),
    redisContainerMemoryLimitMiB: requiredNumber(
      draft.redisContainerMemoryLimitMiB
    ),
    adminPassword: current.adminPassword,
    changeAdminPassword: current.changeAdminPassword,
    automaticBackupEnabled: draft.automaticBackupEnabled,
    backupScheduleTimes: draft.backupScheduleTimes
      .split(",")
      .map((value) => value.trim())
      .filter(Boolean),
    backupRetentionCount: requiredNumber(draft.backupRetentionCount),
    logArchiveRetentionDays: requiredNumber(draft.logArchiveRetentionDays),
    logArchiveMaximumGiB: requiredNumber(draft.logArchiveMaximumGiB),
    redisRelay: {
      ...current.redisRelay,
      enabled: draft.redisRelayEnabled,
      target: {
        ...current.redisRelay.target,
        url: draft.redisRelayTargetURL.trim(),
        username: draft.redisRelayUsername.trim(),
        password: draft.redisRelayPassword,
        clearPassword: draft.redisRelayClearPassword,
        passwordConfigured: draft.redisRelayPasswordConfigured,
        tls: draft.redisRelayTLS
      },
      scope: draft.redisRelayScope,
      includeRecorderNetworkContext:
        draft.redisRelayIncludeRecorderNetworkContext
    },
    startOnBoot: draft.startOnBoot,
    autoRecoveryEnabled: draft.autoRecoveryEnabled,
    preventSystemSleep: draft.preventSystemSleep,
    restartAfterSave: draft.restartAfterSave
  };
}

export function usesCustomAdvertisedURL(settings: RuntimeSettings): boolean {
  return Boolean(
    settings.publicHost.trim() ||
      settings.publicPort !== settings.proxyPort
  );
}

export function parseOptionalNumber(value: string): number | undefined {
  const trimmed = value.trim();
  if (!trimmed) {
    return undefined;
  }
  const parsed = Number(trimmed);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function formatNumber(value: number | undefined): string {
  return value === undefined ? "" : String(value);
}

function requiredNumber(value: string): number {
  return parseOptionalNumber(value) ?? 0;
}

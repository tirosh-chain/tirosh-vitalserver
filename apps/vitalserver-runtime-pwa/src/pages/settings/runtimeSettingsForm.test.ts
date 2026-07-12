import { describe, expect, it } from "vitest";

import {
  draftToRuntimeSettings,
  runtimeSettingsToDraft,
  usesCustomAdvertisedURL,
  type RuntimeSettingsDraft
} from "./runtimeSettingsForm";
import { startOnBootControlState } from "@/domain/runtime-control/settings/runtimeSettingsPolicy";

describe("runtime settings form mapping", () => {
  it("maps runtime settings into editable draft values", () => {
    expect(
      runtimeSettingsToDraft({
        ...runtimeSettings(),
        cpuCount: 4,
        memoryGiB: 8,
        diskGiB: 64,
        proxyPort: 18080,
        runtimeControlPort: 18321,
        vitalFilesDirectory: "/data/vital-files",
        publicHost: "vital.local",
        publicPort: 443,
        recorderIngressSendDataMode: "spool_and_replay",
        recorderIngressSendDataReplayMaxMiBPerSecond: 25,
        containerMemoryLimitsEnabled: true,
        vitalServerContainerMemoryLimitMiB: 4096,
        recorderIngressContainerMemoryLimitMiB: 512,
        redisContainerMemoryLimitMiB: 1024,
        automaticBackupEnabled: true,
        backupScheduleTimes: ["03:15", "15:15"],
        backupRetentionCount: 7,
        logArchiveRetentionDays: 10,
        logArchiveMaximumGiB: 3,
        redisRelay: redisRelaySettings({
          enabled: true,
          target: {
            url: "redis://redis.example:6379/0",
            username: "relay",
            password: "",
            clearPassword: false,
            passwordConfigured: true,
            tls: true
          },
          scope: "waveform_trend_only",
          includeRecorderNetworkContext: true
        }),
        startOnBoot: true,
        autoRecoveryEnabled: true,
        preventSystemSleep: true,
        restartAfterSave: true
      })
    ).toMatchObject({
      cpuCount: "4",
      memoryGiB: "8",
      diskGiB: "64",
      proxyPort: "18080",
      runtimeControlPort: "18321",
      vitalFilesDirectory: "/data/vital-files",
      publicHost: "vital.local",
      publicPort: "443",
      recorderIngressLoadControlEnabled: true,
      recorderIngressSendDataReplayMaxMiBPerSecond: "25",
      containerMemoryLimitsEnabled: true,
      vitalServerContainerMemoryLimitMiB: "4096",
      recorderIngressContainerMemoryLimitMiB: "512",
      redisContainerMemoryLimitMiB: "1024",
      automaticBackupEnabled: true,
      backupScheduleTimes: "03:15, 15:15",
      backupRetentionCount: "7",
      logArchiveRetentionDays: "10",
      logArchiveMaximumGiB: "3",
      redisRelayEnabled: true,
      redisRelayTargetURL: "redis://redis.example:6379/0",
      redisRelayUsername: "relay",
      redisRelayPassword: "",
      redisRelayClearPassword: false,
      redisRelayPasswordConfigured: true,
      redisRelayTLS: true,
      redisRelayScope: "waveform_trend_only",
      redisRelayIncludeRecorderNetworkContext: true,
      startOnBoot: true,
      autoRecoveryEnabled: true,
      preventSystemSleep: true,
      restartAfterSave: true
    });
  });

  it("uses proxy port as advertised port when custom advertised URL is disabled", () => {
    expect(
      draftToRuntimeSettings(
        draft({
          ...draftFromSettings(runtimeSettings()),
          proxyPort: "18080",
          publicHost: "example.local",
          publicPort: "443"
        }),
        runtimeSettings(),
        false
      )
    )
      .toMatchObject({
        proxyPort: 18080,
        publicHost: "",
        publicPort: 18080
      });
  });

  it("keeps custom advertised host and port when enabled", () => {
    expect(
      draftToRuntimeSettings(
        draft({
          proxyPort: "18080",
          publicHost: "example.local",
          publicPort: "443"
        }),
        runtimeSettings({ minimumDiskGiB: 32 }),
        true
      )
    ).toMatchObject({
      minimumDiskGiB: 32,
      proxyPort: 18080,
      publicHost: "example.local",
      publicPort: 443,
      recorderIngressSendDataMode: "spool_and_replay",
      recorderIngressSendDataReplayMaxMiBPerSecond: 20
    });
  });

  it("maps recorder load control to passthrough or spool_and_replay settings", () => {
    expect(
      draftToRuntimeSettings(
        draft({
          ...draftFromSettings(runtimeSettings()),
          recorderIngressLoadControlEnabled: false,
          recorderIngressSendDataReplayMaxMiBPerSecond: "35"
        }),
        runtimeSettings(),
        false
      )
    ).toMatchObject({
      recorderIngressSendDataMode: "passthrough",
      recorderIngressSendDataReplayBatchSize: 1000,
      recorderIngressSendDataReplayMaxMiBPerSecond: 35,
      containerMemoryLimitsEnabled: false,
      vitalServerContainerMemoryLimitMiB: 4096,
      recorderIngressContainerMemoryLimitMiB: 512,
      redisContainerMemoryLimitMiB: 1024
    });
  });

  it("maps Redis Relay settings into the runtime settings contract", () => {
    expect(
      draftToRuntimeSettings(
        draft({
          ...draftFromSettings(runtimeSettings()),
          redisRelayEnabled: true,
          redisRelayTargetURL: "rediss://relay.example:6380/1",
          redisRelayUsername: "relay-user",
          redisRelayPassword: "secret",
          redisRelayClearPassword: false,
          redisRelayPasswordConfigured: false,
          redisRelayTLS: true,
          redisRelayScope: "waveform_trend_only",
          redisRelayIncludeRecorderNetworkContext: true
        }),
        runtimeSettings(),
        false
      ).redisRelay
    ).toMatchObject({
      enabled: true,
      target: {
        url: "rediss://relay.example:6380/1",
        username: "relay-user",
        password: "secret",
        clearPassword: false,
        passwordConfigured: false,
        tls: true
      },
      scope: "waveform_trend_only",
      includeRecorderNetworkContext: true,
      intervalSeconds: 1,
      scanCount: 1000
    });
  });

  it("promotes legacy hidden recorder ingress batch size to the internal guard minimum", () => {
    expect(
      draftToRuntimeSettings(
        draftFromSettings(runtimeSettings({ recorderIngressSendDataReplayBatchSize: 10 })),
        runtimeSettings({ recorderIngressSendDataReplayBatchSize: 10 }),
        false
      ).recorderIngressSendDataReplayBatchSize
    ).toBe(1000);
  });

  it("keeps recorder archive and auto export enabled as product defaults", () => {
    expect(
      draftToRuntimeSettings(
        draft({
          ...draftFromSettings(runtimeSettings()),
          recorderIngressRawArchiveEnabled: false,
          recorderIngressRawArchiveAutoExportEnabled: false
        }),
        runtimeSettings(),
        false
      ).recorderIngress
    ).toMatchObject({
      rawArchiveEnabled: true,
      rawArchiveAutoExportEnabled: true
    });
  });

  it("detects custom advertised URL settings", () => {
    expect(usesCustomAdvertisedURL(runtimeSettings({ proxyPort: 80, publicPort: 80 }))).toBe(false);
    expect(usesCustomAdvertisedURL(runtimeSettings({ proxyPort: 80, publicPort: 443 }))).toBe(true);
    expect(usesCustomAdvertisedURL(runtimeSettings({ publicHost: "vital.local" }))).toBe(true);
  });

  it("keeps start-on-boot edit state reasons explicit", () => {
    expect(
      startOnBootControlState({
        startOnBootConfigurable: true,
        capabilityReadState: "available",
        capabilities: capabilities({ canControlRuntimeServices: true })
      })
    ).toEqual({ enabled: true, reason: null });

    expect(
      startOnBootControlState({
        startOnBootConfigurable: false,
        capabilityReadState: "available",
        capabilities: capabilities({ canControlRuntimeServices: true })
      })
    ).toMatchObject({
      enabled: false,
      reason: "Start on boot is not configurable for this runtime."
    });

    expect(
      startOnBootControlState({
        startOnBootConfigurable: true,
        capabilityReadState: "failed",
        capabilities: undefined
      })
    ).toMatchObject({
      enabled: false,
      reason: "Runtime service control capability could not be read."
    });

    expect(
      startOnBootControlState({
        startOnBootConfigurable: true,
        capabilityReadState: "available",
        capabilities: capabilities({ canControlRuntimeServices: undefined })
      })
    ).toMatchObject({
      enabled: false,
      reason: "Runtime service control capability was not reported."
    });
  });
});

function runtimeSettings(overrides = {}) {
  return {
    readIssues: [],
    cpuCount: 2,
    memoryGiB: 4,
    diskGiB: 32,
    minimumDiskGiB: 4,
    networkMode: "shared" as const,
    bridgedInterface: "",
    proxyPort: 80,
    runtimeControlPort: 18321,
    vitalFilesDirectory: "/Users/shared/vital",
    vitalServerURL: "http://127.0.0.1:80/",
    remoteConsoleURL: "http://127.0.0.1:18321/",
    publicHost: "",
    publicPort: 80,
    recorderIngressSendDataMode: "spool_and_replay" as const,
    recorderIngressSendDataReplayBatchSize: 1000,
    recorderIngressSendDataReplayMaxMiBPerSecond: 20,
    recorderIngress: recorderIngressSettings(),
    containerMemoryLimitsEnabled: false,
    vitalServerContainerMemoryLimitMiB: 4096,
    recorderIngressContainerMemoryLimitMiB: 512,
    redisContainerMemoryLimitMiB: 1024,
    adminPassword: "",
    changeAdminPassword: false,
    startOnBoot: true,
    startOnBootConfigurable: true,
    autoRecoveryEnabled: true,
    preventSystemSleep: true,
    automaticBackupEnabled: true,
    backupScheduleTimes: ["03:15"],
    backupRetentionCount: 30,
    logArchiveRetentionDays: 14,
    logArchiveMaximumGiB: 1,
    redisRelay: redisRelaySettings(),
    restartAfterSave: true,
    ...overrides
  };
}

function redisRelaySettings(overrides = {}) {
  return {
    enabled: false,
    target: {
      url: "redis://redis.example:6379/0",
      username: "",
      password: "",
      clearPassword: false,
      passwordConfigured: false,
      tls: false
    },
    scope: "vital_reconstruction" as const,
    includeRecorderNetworkContext: false,
    intervalSeconds: 1,
    scanCount: 1000,
    ...overrides
  };
}

function recorderIngressSettings(overrides = {}) {
  return {
    sendDataMaxPendingItems: 100000,
    sendDataMaxPendingMiB: 512,
    sendDataMaxPayloadMiB: 10,
    sendDataReplayedMaxItems: 10000,
    sendDataRealtimeMaxPendingItems: 2000,
    sendDataReplayIntervalMs: 1000,
    sendDataReplayMaxAttempts: 3,
    sendDataReplayTargetTimeoutMs: 5000,
    sendDataReplayAdaptiveMinConcurrency: 1,
    sendDataReplayAdaptiveMaxConcurrency: 8,
    rawArchiveEnabled: true,
    rawArchiveMaxFileMiB: 512,
    rawArchiveMaxFiles: 24,
    rawArchiveAutoExportEnabled: true,
    rawArchiveAutoExportQuietSeconds: 300,
    rawArchiveAutoExportScanIntervalSeconds: 60,
    rawArchiveAutoExportCursorStableSeconds: 60,
    rawArchiveAutoExportRetryDelaySeconds: 60,
    rawArchiveAutoExportMaxAttempts: 3,
    rawArchiveAutoExportRequestTimeoutSeconds: 300,
    ...overrides
  };
}

function draftFromSettings(settings: ReturnType<typeof runtimeSettings>): RuntimeSettingsDraft {
  return runtimeSettingsToDraft(settings);
}

function draft(
  overrides: Partial<RuntimeSettingsDraft> = {}
): RuntimeSettingsDraft {
  return {
    cpuCount: "",
    memoryGiB: "",
    diskGiB: "",
    proxyPort: "",
    runtimeControlPort: "",
    vitalFilesDirectory: "",
    publicHost: "",
    publicPort: "",
    recorderIngressLoadControlEnabled: true,
    recorderIngressSendDataReplayMaxMiBPerSecond: "20",
    recorderIngressSendDataMaxPendingItems: "100000",
    recorderIngressSendDataMaxPendingMiB: "512",
    recorderIngressSendDataMaxPayloadMiB: "10",
    recorderIngressSendDataReplayedMaxItems: "10000",
    recorderIngressSendDataRealtimeMaxPendingItems: "2000",
    recorderIngressSendDataReplayIntervalMs: "1000",
    recorderIngressSendDataReplayMaxAttempts: "3",
    recorderIngressSendDataReplayTargetTimeoutMs: "5000",
    recorderIngressSendDataReplayAdaptiveMinConcurrency: "1",
    recorderIngressSendDataReplayAdaptiveMaxConcurrency: "8",
    recorderIngressRawArchiveEnabled: true,
    recorderIngressRawArchiveMaxFileMiB: "512",
    recorderIngressRawArchiveMaxFiles: "24",
    recorderIngressRawArchiveAutoExportEnabled: false,
    recorderIngressRawArchiveAutoExportQuietSeconds: "300",
    recorderIngressRawArchiveAutoExportScanIntervalSeconds: "60",
    recorderIngressRawArchiveAutoExportCursorStableSeconds: "60",
    recorderIngressRawArchiveAutoExportRetryDelaySeconds: "60",
    recorderIngressRawArchiveAutoExportMaxAttempts: "3",
    recorderIngressRawArchiveAutoExportRequestTimeoutSeconds: "300",
    containerMemoryLimitsEnabled: false,
    vitalServerContainerMemoryLimitMiB: "4096",
    recorderIngressContainerMemoryLimitMiB: "512",
    redisContainerMemoryLimitMiB: "1024",
    automaticBackupEnabled: false,
    backupScheduleTimes: "",
    backupRetentionCount: "",
    logArchiveRetentionDays: "",
    logArchiveMaximumGiB: "",
    redisRelayEnabled: false,
    redisRelayTargetURL: "redis://redis.example:6379/0",
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
    restartAfterSave: false,
    ...overrides
  };
}

function capabilities(overrides = {}) {
  return {
    canInstallRuntime: true,
    canUninstallRuntime: true,
    canApplyBundle: true,
    canRollback: true,
    canRollbackRelease: true,
    canEditRuntimeProviderResources: true,
    canEditNetworkExposure: true,
    canResetAdminPassword: true,
    canOpenLocalFiles: true,
    canStreamLogs: true,
    canControlRuntimeServices: true,
    canControlGuestServices: true,
    canRepairRuntimeDatastore: true,
    canExportLogs: true,
    canViewReleaseMetadata: true,
    canUseLab: true,
    ...overrides
  };
}

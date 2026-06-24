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
      recorderIngressSendDataReplayBatchSize: 10,
      recorderIngressSendDataReplayMaxMiBPerSecond: 35,
      containerMemoryLimitsEnabled: false,
      vitalServerContainerMemoryLimitMiB: 4096,
      recorderIngressContainerMemoryLimitMiB: 512,
      redisContainerMemoryLimitMiB: 1024
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
    recorderIngressSendDataReplayBatchSize: 10,
    recorderIngressSendDataReplayMaxMiBPerSecond: 20,
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
    restartAfterSave: true,
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
    containerMemoryLimitsEnabled: false,
    vitalServerContainerMemoryLimitMiB: "4096",
    recorderIngressContainerMemoryLimitMiB: "512",
    redisContainerMemoryLimitMiB: "1024",
    automaticBackupEnabled: false,
    backupScheduleTimes: "",
    backupRetentionCount: "",
    logArchiveRetentionDays: "",
    logArchiveMaximumGiB: "",
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
    canEditVMResources: true,
    canEditNetworkExposure: true,
    canResetAdminPassword: true,
    canOpenLocalFiles: true,
    canStreamLogs: true,
    canControlRuntimeServices: true,
    canExportLogs: true,
    canViewReleaseMetadata: true,
    canUseTestTools: true,
    ...overrides
  };
}

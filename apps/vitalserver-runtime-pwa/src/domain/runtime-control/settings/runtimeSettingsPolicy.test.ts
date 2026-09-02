import { describe, expect, it } from "vitest";

import {
  isProtectedVitalFilesDirectory,
  runtimeSettingsActivationDecision,
  validateRuntimeSettings
} from "./runtimeSettingsPolicy";

describe("runtime settings policy", () => {
  it("rejects protected vital files directories", () => {
    expect(isProtectedVitalFilesDirectory("/Users/test/Desktop/vital")).toBe(true);
    expect(isProtectedVitalFilesDirectory("/Users/Shared/TiroshVitalServer/vital")).toBe(false);
  });

  it("validates VM, port, disk, and backup limits", () => {
    const result = validateRuntimeSettings(fullSettings({
      cpuCount: 0,
      memoryGiB: 0,
      diskGiB: 8,
      minimumDiskGiB: 16,
      proxyPort: 70_000,
      runtimeControlPort: 70_000,
      publicPort: 0,
      automaticBackupEnabled: true,
      backupScheduleTimes: ["03:15"],
      backupRetentionCount: 31,
      logArchiveRetentionDays: 31,
      logArchiveMaximumGiB: 21,
      recorderIngressSendDataReplayMaxMiBPerSecond: 101,
      containerMemoryLimitsEnabled: false
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toHaveLength(10);
    expect(result.errors).toContain("Log archive retention must be between 1 and 30 days.");
    expect(result.errors).toContain("Log archive size limit must be between 1 and 20 GiB.");
    expect(result.errors).toContain("Max replay throughput must be between 1 and 100 MiB/s.");
  });

  it("validates enabled Redis Relay target settings", () => {
    const result = validateRuntimeSettings(fullSettings({
      redisRelay: redisRelaySettings({
        enabled: true,
        target: {
          url: "http://redis.example:6379/0",
          username: "relay",
          password: "",
          clearPassword: false,
          clearUsername: false,
          usernameConfigured: true,
          passwordConfigured: false,
          tls: false
        }
      })
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toContain(
      "Redis Relay target URL must be redis:// or rediss:// with a host."
    );
  });

  it("rejects Redis Relay target paths that are not database numbers", () => {
    const result = validateRuntimeSettings(fullSettings({
      redisRelay: redisRelaySettings({
        enabled: true,
        target: {
          url: "redis://redis.example:6379/not-a-db",
          username: "relay",
          password: "",
          clearPassword: false,
          clearUsername: false,
          usernameConfigured: true,
          passwordConfigured: false,
          tls: false
        }
      })
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toContain(
      "Redis Relay target URL must be redis:// or rediss:// with a host."
    );
  });

  it("rejects fractional recorder ingress integer settings", () => {
    const result = validateRuntimeSettings(fullSettings({
      recorderIngressSendDataReplayMaxMiBPerSecond: 20.5,
      recorderIngress: recorderIngressSettings({
        sendDataReplayIntervalMs: 1000.5
      })
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toContain("Max replay throughput must be between 1 and 100 MiB/s.");
    expect(result.errors).toContain("Replay interval must be an integer 1 or greater.");
  });

  it("validates enabled container memory limits in MiB against VM memory", () => {
    const result = validateRuntimeSettings(fullSettings({
      memoryGiB: 4,
      containerMemoryLimitsEnabled: true,
      vitalServerContainerMemoryLimitMiB: 8192,
      recorderIngressContainerMemoryLimitMiB: 64,
      redisContainerMemoryLimitMiB: 9000
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toContain("VitalServer container memory limit must be between 512 and 4096 MiB.");
    expect(result.errors).toContain("Recorder ingress container memory limit must be between 128 and 4096 MiB.");
    expect(result.errors).toContain("Redis container memory limit must be between 256 and 4096 MiB.");
    expect(result.errors).toContain("Container memory limits must total no more than 70% of VM memory.");
  });

  it("allows container memory limit total at the displayed maximum percent", () => {
    const result = validateRuntimeSettings(fullSettings({
      memoryGiB: 8,
      containerMemoryLimitsEnabled: true,
      vitalServerContainerMemoryLimitMiB: 2048,
      recorderIngressContainerMemoryLimitMiB: 410,
      redisContainerMemoryLimitMiB: 3277
    }));

    expect(result.valid).toBe(true);
    expect(result.errors).not.toContain("Container memory limits must total no more than 70% of VM memory.");
  });

  it("allows Redis container memory limits above the former 8 GiB cap", () => {
    const result = validateRuntimeSettings(fullSettings({
      memoryGiB: 48,
      containerMemoryLimitsEnabled: true,
      vitalServerContainerMemoryLimitMiB: 8192,
      recorderIngressContainerMemoryLimitMiB: 4096,
      redisContainerMemoryLimitMiB: 16_384
    }));

    expect(result.valid).toBe(true);
    expect(result.errors).toEqual([]);
  });

  it("rejects backup times outside HH:mm clock range", () => {
    const result = validateRuntimeSettings(fullSettings({
      backupScheduleTimes: ["24:00", "03:60"]
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toContain(
      "Backup times must use 24-hour HH:mm format, such as 03:15 or 15:15, and must be between 00:00 and 23:59."
    );
  });

  it("rejects duplicate backup times", () => {
    const result = validateRuntimeSettings(fullSettings({
      backupScheduleTimes: ["03:15", "03:15"]
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toContain("Backup times must be unique.");
  });

  it("reports no runtime activation for non-VM runtime settings", () => {
    const runtime = fullSettings();
    const draft = fullSettings({
      proxyPort: 18081,
      publicHost: "edge.local",
      backupRetentionCount: 12,
      logArchiveRetentionDays: 10,
      startOnBoot: false
    });

    const decision = runtimeSettingsActivationDecision(draft, runtime);

    expect(decision.requiresActivation).toBe(false);
    expect(decision.requiresVMRestart).toBe(false);
    expect(decision.vmRestartChanges).toEqual([]);
    expect(decision.message).toBe("No runtime activation required for these changes.");
  });

  it("reports VM restart activation for vital files directory changes", () => {
    const runtime = fullSettings();
    const draft = fullSettings({
      vitalFilesDirectory: "/Users/shared/new-vital",
      restartAfterSave: false
    });

    const decision = runtimeSettingsActivationDecision(draft, runtime);

    expect(decision.requiresActivation).toBe(true);
    expect(decision.requiresVMRestart).toBe(true);
    expect(decision.vmRestartChanges).toEqual(["Vital files directory"]);
    expect(decision.message).toBe(
      "Saved changes will not become active until the VM runtime restarts. Required by: Vital files directory."
    );
  });

  it("reports VM restart activation for resource changes when activation is enabled", () => {
    const runtime = fullSettings();
    const draft = fullSettings({
      cpuCount: 4,
      memoryGiB: 8,
      restartAfterSave: true
    });

    const decision = runtimeSettingsActivationDecision(draft, runtime);

    expect(decision.requiresVMRestart).toBe(true);
    expect(decision.vmRestartChanges).toEqual(["CPU", "Memory allocation"]);
    expect(decision.message).toBe(
      "The VM runtime will restart after save. Required by: CPU, Memory allocation."
    );
  });

  it("reports Guest stack reconcile activation for recorder load control changes", () => {
    const runtime = fullSettings();
    const draft = fullSettings({
      recorderIngressSendDataMode: "passthrough" as const,
      recorderIngressSendDataReplayMaxMiBPerSecond: 25,
      restartAfterSave: true
    });

    const decision = runtimeSettingsActivationDecision(draft, runtime);

    expect(decision.requiresActivation).toBe(true);
    expect(decision.requiresVMRestart).toBe(false);
    expect(decision.requiresGuestStackReconcile).toBe(true);
    expect(decision.guestStackChanges).toEqual([
      "Recorder load control",
      "Recorder replay throughput"
    ]);
    expect(decision.message).toBe(
      "Guest stack will be reconciled after save. Required by: Recorder load control, Recorder replay throughput."
    );
  });

  it("reports Guest stack reconcile activation for container memory limit changes", () => {
    const runtime = fullSettings();
    const draft = fullSettings({
      containerMemoryLimitsEnabled: false,
      vitalServerContainerMemoryLimitMiB: 2048,
      restartAfterSave: true
    });

    const decision = runtimeSettingsActivationDecision(draft, runtime);

    expect(decision.requiresActivation).toBe(true);
    expect(decision.requiresVMRestart).toBe(false);
    expect(decision.requiresGuestStackReconcile).toBe(true);
    expect(decision.guestStackChanges).toEqual([
      "VitalServer container memory limit"
    ]);
  });

  it("reports Guest stack reconcile activation for Redis Relay changes", () => {
    const runtime = fullSettings();
    const draft = fullSettings({
      redisRelay: redisRelaySettings({ enabled: true }),
      restartAfterSave: true
    });

    const decision = runtimeSettingsActivationDecision(draft, runtime);

    expect(decision.requiresGuestStackReconcile).toBe(true);
    expect(decision.guestStackChanges).toEqual(["Redis Relay"]);
  });
});

function fullSettings(overrides = {}) {
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
      clearUsername: false,
      usernameConfigured: false,
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

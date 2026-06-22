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
      logArchiveMaximumGiB: 21
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toHaveLength(9);
    expect(result.errors).toContain("Log archive retention must be between 1 and 30 days.");
    expect(result.errors).toContain("Log archive size limit must be between 1 and 20 GiB.");
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

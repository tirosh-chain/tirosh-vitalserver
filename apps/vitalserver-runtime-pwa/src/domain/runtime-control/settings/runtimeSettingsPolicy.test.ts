import { describe, expect, it } from "vitest";

import { isProtectedVitalFilesDirectory, validateRuntimeSettings } from "./runtimeSettingsPolicy";

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
    backupRetentionCount: 31
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toHaveLength(7);
  });

  it("rejects backup times outside HH:mm clock range", () => {
    const result = validateRuntimeSettings(fullSettings({
      backupScheduleTimes: ["24:00", "03:60"]
    }));

    expect(result.valid).toBe(false);
    expect(result.errors).toContain("Backup times must use HH:mm format.");
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
    restartAfterSave: true,
    ...overrides
  };
}

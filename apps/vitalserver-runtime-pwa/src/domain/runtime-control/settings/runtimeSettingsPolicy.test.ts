import { describe, expect, it } from "vitest";

import { isProtectedVitalFilesDirectory, validateRuntimeSettings } from "./runtimeSettingsPolicy";

describe("runtime settings policy", () => {
  it("rejects protected vital files directories", () => {
    expect(isProtectedVitalFilesDirectory("/Users/test/Desktop/vital")).toBe(true);
    expect(isProtectedVitalFilesDirectory("/Users/Shared/TiroshVitalServer/vital")).toBe(false);
  });

  it("validates VM, port, disk, and Redis backup limits", () => {
    const result = validateRuntimeSettings({
      cpuCount: 0,
      memoryGiB: 0,
      diskGiB: 8,
      minimumDiskGiB: 16,
      proxyPort: 70_000,
      publicPort: 0,
      redisBackupRetentionCount: 31
    });

    expect(result.valid).toBe(false);
    expect(result.errors).toHaveLength(6);
  });
});

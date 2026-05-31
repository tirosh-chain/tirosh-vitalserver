import { describe, expect, it } from "vitest";

import {
  draftToRuntimeSettings,
  runtimeSettingsToDraft,
  usesCustomAdvertisedURL,
  type RuntimeSettingsDraft
} from "./runtimeSettingsForm";

describe("runtime settings form mapping", () => {
  it("maps runtime settings into editable draft values", () => {
    expect(
      runtimeSettingsToDraft({
        cpuCount: 4,
        memoryGiB: 8,
        diskGiB: 64,
        proxyPort: 18080,
        runtimeControlPort: 18321,
        vitalFilesDirectory: "/data/vital-files",
        publicHost: "vital.local",
        publicPort: 443,
        redisBackupRetentionCount: 7,
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
      redisBackupRetentionCount: "7",
      startOnBoot: true,
      autoRecoveryEnabled: true,
      preventSystemSleep: true,
      restartAfterSave: true
    });
  });

  it("uses proxy port as advertised port when custom advertised URL is disabled", () => {
    expect(draftToRuntimeSettings(draft({ proxyPort: "18080" }), undefined, false))
      .toMatchObject({
        proxyPort: 18080,
        publicHost: undefined,
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
        { minimumDiskGiB: 32 },
        true
      )
    ).toMatchObject({
      minimumDiskGiB: 32,
      proxyPort: 18080,
      publicHost: "example.local",
      publicPort: 443
    });
  });

  it("detects custom advertised URL settings", () => {
    expect(usesCustomAdvertisedURL({ proxyPort: 80, publicPort: 80 })).toBe(false);
    expect(usesCustomAdvertisedURL({ proxyPort: 80, publicPort: 443 })).toBe(true);
    expect(usesCustomAdvertisedURL({ publicHost: "vital.local" })).toBe(true);
  });
});

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
    redisBackupRetentionCount: "",
    startOnBoot: false,
    autoRecoveryEnabled: false,
    preventSystemSleep: false,
    restartAfterSave: false,
    ...overrides
  };
}

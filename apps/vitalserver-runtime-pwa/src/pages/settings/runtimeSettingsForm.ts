import type { RuntimeSettings } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export type RuntimeSettingsDraft = {
  cpuCount: string;
  memoryGiB: string;
  diskGiB: string;
  proxyPort: string;
  runtimeControlPort: string;
  vitalFilesDirectory: string;
  publicHost: string;
  publicPort: string;
  redisBackupRetentionCount: string;
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
  redisBackupRetentionCount: "",
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
    vitalFilesDirectory: settings.vitalFilesDirectory ?? "",
    publicHost: settings.publicHost ?? "",
    publicPort: formatNumber(settings.publicPort),
    redisBackupRetentionCount: formatNumber(settings.redisBackupRetentionCount),
    startOnBoot: settings.startOnBoot ?? false,
    autoRecoveryEnabled: settings.autoRecoveryEnabled ?? false,
    preventSystemSleep: settings.preventSystemSleep ?? false,
    restartAfterSave: settings.restartAfterSave ?? false
  };
}

export function draftToRuntimeSettings(
  draft: RuntimeSettingsDraft,
  current: RuntimeSettings | undefined,
  customAdvertisedURL: boolean
): RuntimeSettings {
  const proxyPort = parseOptionalNumber(draft.proxyPort);
  return {
    cpuCount: parseOptionalNumber(draft.cpuCount),
    memoryGiB: parseOptionalNumber(draft.memoryGiB),
    diskGiB: parseOptionalNumber(draft.diskGiB),
    minimumDiskGiB: current?.minimumDiskGiB,
    proxyPort,
    runtimeControlPort: parseOptionalNumber(draft.runtimeControlPort),
    vitalFilesDirectory: emptyToUndefined(draft.vitalFilesDirectory),
    publicHost: customAdvertisedURL ? emptyToUndefined(draft.publicHost) : undefined,
    publicPort: customAdvertisedURL ? parseOptionalNumber(draft.publicPort) : proxyPort,
    redisBackupRetentionCount: parseOptionalNumber(
      draft.redisBackupRetentionCount
    ),
    startOnBoot: draft.startOnBoot,
    autoRecoveryEnabled: draft.autoRecoveryEnabled,
    preventSystemSleep: draft.preventSystemSleep,
    restartAfterSave: draft.restartAfterSave
  };
}

export function usesCustomAdvertisedURL(settings: RuntimeSettings): boolean {
  return Boolean(
    settings.publicHost?.trim() ||
      (settings.publicPort !== undefined && settings.publicPort !== settings.proxyPort)
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

function emptyToUndefined(value: string): string | undefined {
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

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
  automaticBackupEnabled: boolean;
  backupScheduleTimes: string;
  backupRetentionCount: string;
  logArchiveRetentionDays: string;
  logArchiveMaximumGiB: string;
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
  automaticBackupEnabled: false,
  backupScheduleTimes: "",
  backupRetentionCount: "",
  logArchiveRetentionDays: "",
  logArchiveMaximumGiB: "",
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
    automaticBackupEnabled: settings.automaticBackupEnabled,
    backupScheduleTimes: settings.backupScheduleTimes.join(", "),
    backupRetentionCount: formatNumber(settings.backupRetentionCount),
    logArchiveRetentionDays: formatNumber(settings.logArchiveRetentionDays),
    logArchiveMaximumGiB: formatNumber(settings.logArchiveMaximumGiB),
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

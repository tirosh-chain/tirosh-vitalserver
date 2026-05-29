import type { RuntimeSettings } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export type RuntimeSettingsValidationResult = {
  valid: boolean;
  errors: string[];
};

const protectedDirectoryNames = new Set([
  "Desktop",
  "Documents",
  "Downloads",
  "iCloud Drive"
]);

export function validateRuntimeSettings(
  settings: RuntimeSettings
): RuntimeSettingsValidationResult {
  const errors: string[] = [];

  if (settings.cpuCount !== undefined && settings.cpuCount < 1) {
    errors.push("CPU cores must be 1 or greater.");
  }
  if (settings.memoryGiB !== undefined && settings.memoryGiB < 1) {
    errors.push("Memory allocation must be 1 GiB or greater.");
  }
  if (
    settings.diskGiB !== undefined &&
    settings.minimumDiskGiB !== undefined &&
    settings.diskGiB < settings.minimumDiskGiB
  ) {
    errors.push(`VM disk must be at least ${settings.minimumDiskGiB} GiB.`);
  }
  if (!validPort(settings.proxyPort)) {
    errors.push("VitalServer listen port must be between 1 and 65535.");
  }
  if (!validPort(settings.runtimeControlPort)) {
    errors.push("Remote Console port must be between 1 and 65535.");
  }
  if (!validPort(settings.publicPort)) {
    errors.push("Advertised port must be between 1 and 65535.");
  }
  if (
    settings.redisBackupRetentionCount !== undefined &&
    (settings.redisBackupRetentionCount < 1 ||
      settings.redisBackupRetentionCount > 30)
  ) {
    errors.push("Redis backups must be between 1 and 30 archives.");
  }
  if (isProtectedVitalFilesDirectory(settings.vitalFilesDirectory)) {
    errors.push(
      "Vital files directory cannot be Desktop, Documents, Downloads, or iCloud Drive."
    );
  }

  return { valid: errors.length === 0, errors };
}

export function isProtectedVitalFilesDirectory(
  path: string | undefined
): boolean {
  if (!path) {
    return false;
  }
  const parts = path.split("/").filter(Boolean);
  return parts.some((part) => protectedDirectoryNames.has(part));
}

function validPort(value: number | undefined): boolean {
  return value === undefined || (Number.isInteger(value) && value >= 1 && value <= 65_535);
}

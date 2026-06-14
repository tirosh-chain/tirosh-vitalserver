import type {
  RuntimeControlCapabilities,
  RuntimeSettings
} from "@/domain/runtime-control/contracts/runtimeControlTypes";

export type RuntimeSettingsValidationResult = {
  valid: boolean;
  errors: string[];
};

export type RuntimeCapabilityReadState =
  | "available"
  | "loading"
  | "failed"
  | "missing";

export type RuntimeSettingsControlState =
  | {
      enabled: true;
      reason: null;
    }
  | {
      enabled: false;
      reason: string;
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

  if (settings.cpuCount < 1) {
    errors.push("CPU cores must be 1 or greater.");
  }
  if (settings.memoryGiB < 1) {
    errors.push("Memory allocation must be 1 GiB or greater.");
  }
  if (settings.diskGiB < settings.minimumDiskGiB) {
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
    settings.backupRetentionCount < 1 ||
    settings.backupRetentionCount > 30
  ) {
    errors.push("VitalServer Helper backups must be between 1 and 30 archives.");
  }
  if (
    settings.backupScheduleTimes.length === 0 ||
    settings.backupScheduleTimes.some((value) => !validBackupTime(value))
  ) {
    errors.push(
      "Backup times must use 24-hour HH:mm format, such as 03:15 or 15:15, and must be between 00:00 and 23:59."
    );
  }
  if (new Set(settings.backupScheduleTimes).size !== settings.backupScheduleTimes.length) {
    errors.push("Backup times must be unique.");
  }
  if (
    settings.logArchiveRetentionDays < 1 ||
    settings.logArchiveRetentionDays > 30
  ) {
    errors.push("Log archive retention must be between 1 and 30 days.");
  }
  if (
    settings.logArchiveMaximumGiB < 1 ||
    settings.logArchiveMaximumGiB > 20
  ) {
    errors.push("Log archive size limit must be between 1 and 20 GiB.");
  }
  if (isProtectedVitalFilesDirectory(settings.vitalFilesDirectory)) {
    errors.push(
      "Vital files directory cannot be Desktop, Documents, Downloads, or iCloud Drive."
    );
  }

  return { valid: errors.length === 0, errors };
}

export function startOnBootControlState(input: {
  startOnBootConfigurable: boolean;
  capabilityReadState: RuntimeCapabilityReadState;
  capabilities: RuntimeControlCapabilities | undefined;
}): RuntimeSettingsControlState {
  if (!input.startOnBootConfigurable) {
    return {
      enabled: false,
      reason: "Start on boot is not configurable for this runtime."
    };
  }

  if (input.capabilityReadState === "loading") {
    return {
      enabled: false,
      reason: "Runtime service control capability is still loading."
    };
  }

  if (input.capabilityReadState === "failed") {
    return {
      enabled: false,
      reason: "Runtime service control capability could not be read."
    };
  }

  if (input.capabilityReadState === "missing") {
    return {
      enabled: false,
      reason: "Runtime service control capability was not returned."
    };
  }

  if (input.capabilities?.canControlRuntimeServices === undefined) {
    return {
      enabled: false,
      reason: "Runtime service control capability was not reported."
    };
  }

  if (!input.capabilities.canControlRuntimeServices) {
    return {
      enabled: false,
      reason: "Runtime service control capability is unavailable."
    };
  }

  return { enabled: true, reason: null };
}

export function isProtectedVitalFilesDirectory(
  path: string
): boolean {
  if (!path) {
    return false;
  }
  const parts = path.split("/").filter(Boolean);
  return parts.some((part) => protectedDirectoryNames.has(part));
}

function validPort(value: number): boolean {
  return Number.isInteger(value) && value >= 1 && value <= 65_535;
}

function validBackupTime(value: string): boolean {
  const match = /^(\d{2}):(\d{2})$/.exec(value);
  if (!match) {
    return false;
  }
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59;
}

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
    settings.backupScheduleTimes.some((value) => !/^\d{2}:\d{2}$/.test(value))
  ) {
    errors.push("Backup times must use HH:mm format.");
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

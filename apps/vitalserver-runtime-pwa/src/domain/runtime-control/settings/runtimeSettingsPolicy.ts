import type {
  RuntimeControlCapabilities,
  RuntimeSettings
} from "@/domain/runtime-control/contracts/runtimeControlTypes";

export type RuntimeSettingsValidationResult = {
  valid: boolean;
  errors: string[];
};

export type RuntimeSettingsActivationDecision = {
  vmRestartChanges: string[];
  containerServiceChanges: string[];
  message: string;
  requiresVMRestart: boolean;
  requiresContainerServicesReconcile: boolean;
  requiresActivation: boolean;
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

export const containerMemoryLimitRanges = {
  vitalServer: { minMiB: 512, maxMiB: 32_768 },
  recorderIngress: { minMiB: 128, maxMiB: 4_096 },
  redis: { minMiB: 256, maxMiB: 8_192 },
  stepPercent: 1,
  maxCombinedPercent: 70
} as const;

const restartRequiredSettings: Array<{
  label: string;
  changed: (draft: RuntimeSettings, runtime: RuntimeSettings) => boolean;
}> = [
  {
    label: "CPU",
    changed: (draft, runtime) => draft.cpuCount !== runtime.cpuCount
  },
  {
    label: "Memory allocation",
    changed: (draft, runtime) => draft.memoryGiB !== runtime.memoryGiB
  },
  {
    label: "Disk",
    changed: (draft, runtime) => draft.diskGiB !== runtime.diskGiB
  },
  {
    label: "Network mode",
    changed: (draft, runtime) => draft.networkMode !== runtime.networkMode
  },
  {
    label: "Bridged interface",
    changed: (draft, runtime) =>
      draft.bridgedInterface !== runtime.bridgedInterface
  },
  {
    label: "Vital files directory",
    changed: (draft, runtime) =>
      draft.vitalFilesDirectory !== runtime.vitalFilesDirectory
  }
];

const containerServiceReconcileSettings: Array<{
  label: string;
  changed: (draft: RuntimeSettings, runtime: RuntimeSettings) => boolean;
}> = [
  {
    label: "Recorder load control",
    changed: (draft, runtime) =>
      draft.recorderIngressSendDataMode !== runtime.recorderIngressSendDataMode
  },
  {
    label: "Recorder replay throughput",
    changed: (draft, runtime) =>
      draft.recorderIngressSendDataReplayMaxMiBPerSecond !==
      runtime.recorderIngressSendDataReplayMaxMiBPerSecond
  },
  {
    label: "Recorder ingress hot/cold path",
    changed: (draft, runtime) =>
      JSON.stringify(draft.recorderIngress) !==
      JSON.stringify(runtime.recorderIngress)
  },
  {
    label: "Container memory limits",
    changed: (draft, runtime) =>
      draft.containerMemoryLimitsEnabled !== runtime.containerMemoryLimitsEnabled
  },
  {
    label: "VitalServer container memory limit",
    changed: (draft, runtime) =>
      draft.vitalServerContainerMemoryLimitMiB !==
      runtime.vitalServerContainerMemoryLimitMiB
  },
  {
    label: "Recorder ingress container memory limit",
    changed: (draft, runtime) =>
      draft.recorderIngressContainerMemoryLimitMiB !==
      runtime.recorderIngressContainerMemoryLimitMiB
  },
  {
    label: "Redis container memory limit",
    changed: (draft, runtime) =>
      draft.redisContainerMemoryLimitMiB !== runtime.redisContainerMemoryLimitMiB
  },
  {
    label: "Redis Relay",
    changed: (draft, runtime) =>
      JSON.stringify(draft.redisRelay) !== JSON.stringify(runtime.redisRelay)
  }
];

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
  if (settings.redisRelay.enabled) {
    if (!validRedisRelayTargetURL(settings.redisRelay.target.url)) {
      errors.push("Redis Relay target URL must be redis:// or rediss:// with a host.");
    }
    if (
      settings.redisRelay.target.url.includes("\n") ||
      settings.redisRelay.target.url.includes("\r") ||
      settings.redisRelay.target.username.includes("\n") ||
      settings.redisRelay.target.username.includes("\r") ||
      settings.redisRelay.target.password.includes("\n") ||
      settings.redisRelay.target.password.includes("\r")
    ) {
      errors.push("Redis Relay target values must not contain newlines.");
    }
    if (
      settings.redisRelay.intervalSeconds < 0.1 ||
      settings.redisRelay.scanCount < 1
    ) {
      errors.push("Redis Relay interval and scan count must be positive.");
    }
  }
  if (
    !Number.isInteger(settings.recorderIngressSendDataReplayMaxMiBPerSecond) ||
    settings.recorderIngressSendDataReplayMaxMiBPerSecond < 1 ||
    settings.recorderIngressSendDataReplayMaxMiBPerSecond > 100
  ) {
    errors.push("Max replay throughput must be between 1 and 100 MiB/s.");
  }
  for (const [label, value] of recorderIngressPositiveSettings(settings)) {
    if (!Number.isInteger(value) || value < 1) {
      errors.push(`${label} must be an integer 1 or greater.`);
    }
  }
  if (
    settings.recorderIngress.sendDataReplayAdaptiveMaxConcurrency <
    settings.recorderIngress.sendDataReplayAdaptiveMinConcurrency
  ) {
    errors.push("Replay max concurrency must be greater than or equal to min concurrency.");
  }
  if (settings.containerMemoryLimitsEnabled) {
    appendContainerMemoryLimitError({
      errors,
      label: "VitalServer container memory limit",
      valueMiB: settings.vitalServerContainerMemoryLimitMiB,
      memoryGiB: settings.memoryGiB,
      range: containerMemoryLimitRanges.vitalServer
    });
    appendContainerMemoryLimitError({
      errors,
      label: "Recorder ingress container memory limit",
      valueMiB: settings.recorderIngressContainerMemoryLimitMiB,
      memoryGiB: settings.memoryGiB,
      range: containerMemoryLimitRanges.recorderIngress
    });
    appendContainerMemoryLimitError({
      errors,
      label: "Redis container memory limit",
      valueMiB: settings.redisContainerMemoryLimitMiB,
      memoryGiB: settings.memoryGiB,
      range: containerMemoryLimitRanges.redis
    });
    const vmMiB = Math.max(settings.memoryGiB * 1024, 1);
    const totalPercent =
      containerMemoryLimitPercent(settings.vitalServerContainerMemoryLimitMiB, vmMiB) +
      containerMemoryLimitPercent(settings.recorderIngressContainerMemoryLimitMiB, vmMiB) +
      containerMemoryLimitPercent(settings.redisContainerMemoryLimitMiB, vmMiB);
    if (totalPercent > containerMemoryLimitRanges.maxCombinedPercent) {
      errors.push(
        `Container memory limits must total no more than ${containerMemoryLimitRanges.maxCombinedPercent}% of VM memory.`
      );
    }
  }
  if (isProtectedVitalFilesDirectory(settings.vitalFilesDirectory)) {
    errors.push(
      "Vital files directory cannot be Desktop, Documents, Downloads, or iCloud Drive."
    );
  }

  return { valid: errors.length === 0, errors };
}

function recorderIngressPositiveSettings(
  settings: RuntimeSettings
): Array<[string, number]> {
  return [
    ["Hot path pending item retention", settings.recorderIngress.sendDataMaxPendingItems],
    ["Hot path pending MiB", settings.recorderIngress.sendDataMaxPendingMiB],
    ["Max payload MiB", settings.recorderIngress.sendDataMaxPayloadMiB],
    ["Replayed item retention", settings.recorderIngress.sendDataReplayedMaxItems],
    ["Realtime pending item retention", settings.recorderIngress.sendDataRealtimeMaxPendingItems],
    ["Replay interval", settings.recorderIngress.sendDataReplayIntervalMs],
    ["Replay max attempts", settings.recorderIngress.sendDataReplayMaxAttempts],
    ["Replay target timeout", settings.recorderIngress.sendDataReplayTargetTimeoutMs],
    ["Replay min concurrency", settings.recorderIngress.sendDataReplayAdaptiveMinConcurrency],
    ["Replay max concurrency", settings.recorderIngress.sendDataReplayAdaptiveMaxConcurrency],
    ["Raw archive max file MiB", settings.recorderIngress.rawArchiveMaxFileMiB],
    ["Raw archive retained files", settings.recorderIngress.rawArchiveMaxFiles],
    ["Auto export quiet window", settings.recorderIngress.rawArchiveAutoExportQuietSeconds],
    ["Auto export scan interval", settings.recorderIngress.rawArchiveAutoExportScanIntervalSeconds],
    ["Auto export cursor stable window", settings.recorderIngress.rawArchiveAutoExportCursorStableSeconds],
    ["Auto export retry delay", settings.recorderIngress.rawArchiveAutoExportRetryDelaySeconds],
    ["Auto export max attempts", settings.recorderIngress.rawArchiveAutoExportMaxAttempts],
    ["Auto export request timeout", settings.recorderIngress.rawArchiveAutoExportRequestTimeoutSeconds]
  ];
}

function appendContainerMemoryLimitError(input: {
  errors: string[];
  label: string;
  valueMiB: number;
  memoryGiB: number;
  range: { minMiB: number; maxMiB: number };
}) {
  const maximumMiB = Math.max(
    input.range.minMiB,
    Math.min(input.range.maxMiB, input.memoryGiB * 1024)
  );
  if (input.valueMiB < input.range.minMiB || input.valueMiB > maximumMiB) {
    input.errors.push(
      `${input.label} must be between ${input.range.minMiB} and ${maximumMiB} MiB.`
    );
  }
}

export function runtimeSettingsActivationDecision(
  draft: RuntimeSettings,
  runtime: RuntimeSettings
): RuntimeSettingsActivationDecision {
  const vmRestartChanges = restartRequiredSettings
    .filter((setting) => setting.changed(draft, runtime))
    .map((setting) => setting.label);
  const containerServiceChanges = containerServiceReconcileSettings
    .filter((setting) => setting.changed(draft, runtime))
    .map((setting) => setting.label);
  const requiresVMRestart = vmRestartChanges.length > 0;
  const requiresContainerServicesReconcile = containerServiceChanges.length > 0;
  const requiresActivation =
    requiresVMRestart || requiresContainerServicesReconcile;

  return {
    vmRestartChanges,
    containerServiceChanges,
    requiresVMRestart,
    requiresContainerServicesReconcile,
    requiresActivation,
    message: activationMessage({
      vmRestartChanges,
      containerServiceChanges,
      restartAfterSave: draft.restartAfterSave
    })
  };
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

function validRedisRelayTargetURL(value: string): boolean {
  const trimmed = value.trim();
  if (!trimmed || trimmed !== value) {
    return false;
  }
  try {
    const url = new URL(value);
    return (
      (url.protocol === "redis:" || url.protocol === "rediss:") &&
      Boolean(url.hostname) &&
      (!url.port || validPort(Number(url.port))) &&
      validRedisRelayDatabasePath(url.pathname)
    );
  } catch {
    return false;
  }
}

function validRedisRelayDatabasePath(pathname: string): boolean {
  if (!pathname || pathname === "/") {
    return true;
  }
  const database = pathname.slice(1);
  return !database.includes("/") && /^\d+$/.test(database);
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

function containerMemoryLimitPercent(valueMiB: number, vmMiB: number): number {
  return Math.round((valueMiB / Math.max(vmMiB, 1)) * 100);
}

function activationMessage(input: {
  vmRestartChanges: string[];
  containerServiceChanges: string[];
  restartAfterSave: boolean;
}): string {
  const { vmRestartChanges, containerServiceChanges, restartAfterSave } = input;
  if (!vmRestartChanges.length && !containerServiceChanges.length) {
    return "No runtime activation required for these changes.";
  }

  if (!vmRestartChanges.length) {
    const requiredBy = containerServiceChanges.join(", ");
    if (restartAfterSave) {
      return `Container services will be reconciled after save. Required by: ${requiredBy}.`;
    }
    return `Saved changes will not become active until container services are reconciled. Required by: ${requiredBy}.`;
  }

  const requiredBy = [...vmRestartChanges, ...containerServiceChanges].join(
    ", "
  );
  if (restartAfterSave) {
    return `The VM runtime will restart after save. Required by: ${requiredBy}.`;
  }
  return `Saved changes will not become active until the VM runtime restarts. Required by: ${requiredBy}.`;
}

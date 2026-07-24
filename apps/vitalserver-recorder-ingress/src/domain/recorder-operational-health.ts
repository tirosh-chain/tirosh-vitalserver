type JSONObject = Record<string, unknown>;

export type RecorderOperationalHealthState =
  | "healthy"
  | "warning"
  | "critical"
  | "unknown";

export type RecorderOperationalIssue = {
  code: string;
  category: "power" | "storage" | "service" | "time" | "temperature" | "memory";
  severity: "warning" | "critical";
  title: string;
  detail: string;
  field: string;
};

export type RecorderOperationalHealth = {
  state: RecorderOperationalHealthState;
  evaluatedAt: string | null;
  issueCount: number;
  issues: RecorderOperationalIssue[];
};

export function assessRecorderOperationalHealth(
  observation: JSONObject | null,
  reportState: string,
): RecorderOperationalHealth {
  const payload = object(observation?.payload);
  const issues: RecorderOperationalIssue[] = [];
  const observedAt = string(observation?.deviceObservedAt);

  if (payload) {
    assessPower(object(payload.raspberryPi), issues);
    assessTemperature(object(payload.raspberryPi), issues);
    assessStorage(object(payload.storage), issues);
    assessMemory(object(payload.memory), issues);
    assessServices(object(payload.services), object(payload.vitalRecorder), issues);
    assessTime(string(observation?.ntpState), issues);
  }

  return {
    state: reportState !== "current" || !payload
      ? "unknown"
      : issues.some((issue) => issue.severity === "critical")
        ? "critical"
        : issues.length > 0
          ? "warning"
          : "healthy",
    evaluatedAt: observedAt,
    issueCount: issues.length,
    issues,
  };
}

function assessPower(
  raspberryPi: JSONObject | null,
  issues: RecorderOperationalIssue[],
): void {
  const throttleStatus = object(raspberryPi?.throttleStatus);
  const flags = throttleStatus
    ? throttleStatusValues(throttleStatus)
    : throttleFlagValues(readingString(object(raspberryPi?.throttleFlags)));
  const active = [
    flags.underVoltageNow && "undervoltage",
    flags.frequencyCappedNow && "frequency capping",
    flags.throttledNow && "CPU throttling",
    flags.softTemperatureLimitNow && "soft temperature limiting",
  ].filter((value): value is string => Boolean(value));
  if (active.length > 0) {
    issues.push({
      code: "raspberry-pi-throttle-active",
      category: "power",
      severity: "critical",
      title: "Power or throttling condition is active",
      detail: active.join(", "),
      field: "payload.raspberryPi.throttleStatus",
    });
    return;
  }
  const occurred = [
    flags.underVoltageOccurred && "undervoltage",
    flags.frequencyCappedOccurred && "frequency capping",
    flags.throttledOccurred && "CPU throttling",
    flags.softTemperatureLimitOccurred && "soft temperature limiting",
  ].filter((value): value is string => Boolean(value));
  if (occurred.length > 0) {
    issues.push({
      code: "raspberry-pi-throttle-history",
      category: "power",
      severity: "warning",
      title: "Power or throttling condition occurred since boot",
      detail: occurred.join(", "),
      field: "payload.raspberryPi.throttleStatus",
    });
  }
}

function assessTemperature(
  raspberryPi: JSONObject | null,
  issues: RecorderOperationalIssue[],
): void {
  const temperature = readingNumber(object(raspberryPi?.temperatureCelsius));
  if (temperature === null || temperature < 70) return;
  issues.push({
    code: temperature >= 80 ? "cpu-temperature-critical" : "cpu-temperature-high",
    category: "temperature",
    severity: temperature >= 80 ? "critical" : "warning",
    title: temperature >= 80 ? "CPU temperature is critical" : "CPU temperature is high",
    detail: `${temperature.toFixed(1)} °C`,
    field: "payload.raspberryPi.temperatureCelsius",
  });
}

function assessStorage(
  storage: JSONObject | null,
  issues: RecorderOperationalIssue[],
): void {
  assessFilesystem("root", object(storage?.root), issues);
  assessFilesystem("data", object(storage?.data), issues);

  const ext4 = storage?.ext4Filesystems;
  if (!Array.isArray(ext4)) return;
  const affected = ext4.flatMap((entry) => {
    const filesystem = object(entry);
    const errors = readingNumber(object(filesystem?.errorsCount)) ?? 0;
    const warnings = readingNumber(object(filesystem?.warningCount)) ?? 0;
    const name = string(filesystem?.name);
    return name && (errors > 0 || warnings > 0)
      ? [{ name, errors, warnings }]
      : [];
  });
  if (affected.length === 0) return;
  issues.push({
    code: affected.some((item) => item.errors > 0)
      ? "ext4-errors"
      : "ext4-warnings",
    category: "storage",
    severity: affected.some((item) => item.errors > 0)
      ? "critical"
      : "warning",
    title: "Filesystem integrity counters are non-zero",
    detail: affected.map((item) =>
      `${item.name}: ${item.errors} errors, ${item.warnings} warnings`
    ).join("; "),
    field: "payload.storage.ext4Filesystems",
  });
}

function assessFilesystem(
  name: "root" | "data",
  filesystem: JSONObject | null,
  issues: RecorderOperationalIssue[],
): void {
  const readOnly = readingBoolean(object(filesystem?.readOnly));
  if (readOnly === true) {
    issues.push({
      code: `${name}-filesystem-read-only`,
      category: "storage",
      severity: "critical",
      title: `${name === "root" ? "Root" : "Data"} filesystem is read-only`,
      detail: readingString(object(filesystem?.mountOptions)) || "read-only mount",
      field: `payload.storage.${name}.readOnly`,
    });
  }
  const usedPercent = readingNumber(object(filesystem?.usedPercent));
  if (usedPercent === null || usedPercent < 90) return;
  issues.push({
    code: `${name}-filesystem-usage-${usedPercent >= 95 ? "critical" : "high"}`,
    category: "storage",
    severity: usedPercent >= 95 ? "critical" : "warning",
    title: `${name === "root" ? "Root" : "Data"} storage usage is high`,
    detail: `${usedPercent.toFixed(1)}% used`,
    field: `payload.storage.${name}.usedPercent`,
  });
}

function assessMemory(
  memory: JSONObject | null,
  issues: RecorderOperationalIssue[],
): void {
  const total = readingNumber(object(memory?.totalBytes));
  const available = readingNumber(object(memory?.availableBytes));
  if (total === null || available === null || total <= 0) return;
  const availablePercent = available / total * 100;
  if (availablePercent >= 10) return;
  issues.push({
    code: "memory-available-critical",
    category: "memory",
    severity: "critical",
    title: "Available memory is critically low",
    detail: `${availablePercent.toFixed(1)}% available`,
    field: "payload.memory.availableBytes",
  });
}

function assessServices(
  services: JSONObject | null,
  vitalRecorder: JSONObject | null,
  issues: RecorderOperationalIssue[],
): void {
  const recorderState = readingString(object(vitalRecorder?.activeState));
  if (recorderState !== null && recorderState !== "active") {
    issues.push({
      code: "vital-recorder-service-inactive",
      category: "service",
      severity: "critical",
      title: "Vital Recorder service is not active",
      detail: recorderState,
      field: "payload.vitalRecorder.activeState",
    });
  }

  const systemState = readingString(object(services?.systemRunning));
  const failedUnits = readingString(object(services?.failedUnits));
  if (systemState !== null && systemState !== "running") {
    issues.push({
      code: "systemd-system-degraded",
      category: "service",
      severity: ["degraded", "maintenance", "starting"].includes(systemState)
        ? "warning"
        : "critical",
      title: "System service state is not fully running",
      detail: failedUnits
        ? `${systemState}; failed units: ${failedUnits.replace(/\s+/g, " ").trim()}`
        : systemState,
      field: "payload.services.systemRunning",
    });
  } else if (failedUnits && failedUnits.trim()) {
    issues.push({
      code: "systemd-failed-units",
      category: "service",
      severity: "warning",
      title: "Systemd has failed units",
      detail: failedUnits.replace(/\s+/g, " ").trim(),
      field: "payload.services.failedUnits",
    });
  }
}

function assessTime(
  ntpState: string | null,
  issues: RecorderOperationalIssue[],
): void {
  if (ntpState === null || ntpState === "synchronized") return;
  issues.push({
    code: "time-not-synchronized",
    category: "time",
    severity: "warning",
    title: "System time is not synchronized",
    detail: ntpState,
    field: "ntpState",
  });
}

function throttleStatusValues(source: JSONObject) {
  return {
    underVoltageNow: readingBoolean(object(source.underVoltageNow)) === true,
    frequencyCappedNow: readingBoolean(object(source.frequencyCappedNow)) === true,
    throttledNow: readingBoolean(object(source.throttledNow)) === true,
    softTemperatureLimitNow:
      readingBoolean(object(source.softTemperatureLimitNow)) === true,
    underVoltageOccurred:
      readingBoolean(object(source.underVoltageOccurred)) === true,
    frequencyCappedOccurred:
      readingBoolean(object(source.frequencyCappedOccurred)) === true,
    throttledOccurred:
      readingBoolean(object(source.throttledOccurred)) === true,
    softTemperatureLimitOccurred:
      readingBoolean(object(source.softTemperatureLimitOccurred)) === true,
  };
}

function throttleFlagValues(value: string | null) {
  const flags = value && /^0x[0-9a-f]+$/i.test(value)
    ? Number.parseInt(value.slice(2), 16)
    : 0;
  return {
    underVoltageNow: Boolean(flags & (1 << 0)),
    frequencyCappedNow: Boolean(flags & (1 << 1)),
    throttledNow: Boolean(flags & (1 << 2)),
    softTemperatureLimitNow: Boolean(flags & (1 << 3)),
    underVoltageOccurred: Boolean(flags & (1 << 16)),
    frequencyCappedOccurred: Boolean(flags & (1 << 17)),
    throttledOccurred: Boolean(flags & (1 << 18)),
    softTemperatureLimitOccurred: Boolean(flags & (1 << 19)),
  };
}

function readingNumber(source: JSONObject | null): number | null {
  return source?.state === "ok" && typeof source.value === "number"
    && Number.isFinite(source.value)
    ? source.value
    : null;
}

function readingString(source: JSONObject | null): string | null {
  return source?.state === "ok" && typeof source.value === "string"
    ? source.value
    : null;
}

function readingBoolean(source: JSONObject | null): boolean | null {
  return source?.state === "ok" && typeof source.value === "boolean"
    ? source.value
    : null;
}

function object(value: unknown): JSONObject | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as JSONObject
    : null;
}

function string(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

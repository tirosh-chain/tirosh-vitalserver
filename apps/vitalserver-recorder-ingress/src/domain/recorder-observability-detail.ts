import type {
  RecorderObservabilityReportState,
  RecorderObservabilitySupportState,
} from "./recorder-observability";
import {
  assessRecorderOperationalHealth,
  type RecorderOperationalHealth,
} from "./recorder-operational-health";

type JSONValue =
  | null
  | boolean
  | number
  | string
  | JSONValue[]
  | { [key: string]: JSONValue };

export type RecorderObservabilityReading = {
  state: "ok" | "missing" | "invalid" | "failed" | "unsupported";
  value: JSONValue;
  detail: string | null;
  observedAt: string | null;
};

export type RecorderObservabilityDetail = {
  state: "loaded";
  vrcode: string;
  support: {
    state: RecorderObservabilitySupportState;
    source: string | null;
    expectedSince: string | null;
    recorderVersion: string | null;
    producerVersion: string | null;
    protocolVersion: string | null;
  };
  report: {
    state: RecorderObservabilityReportState;
    receivedAt: string | null;
    deviceObservedAt: string | null;
    collectionState: string | null;
    readIssueCount: number;
  };
  profile: {
    state: "associated" | "unassociated" | "missing" | "invalid";
    receivedAt: string | null;
    deviceObservedAt: string | null;
    deviceId: string | null;
    bootId: string | null;
    software: Record<string, RecorderObservabilityReading>;
    collection: {
      powerIntervalSeconds: number | null;
      telemetryIntervalSeconds: number | null;
      observationIntervalSeconds: number | null;
    } | null;
    capabilities: Record<string, {
      state: string;
      source: string | null;
      detail: string | null;
    }>;
  };
  boot: {
    state: "notReported" | "started" | "shutdownClean";
    bootId: string | null;
    startedAt: string | null;
    cleanShutdownAt: string | null;
  };
  operationalHealth: RecorderOperationalHealth;
  readings: {
    temperatureCelsius: RecorderObservabilityReading;
    memoryAvailableBytes: RecorderObservabilityReading;
    memoryTotalBytes: RecorderObservabilityReading;
    rootUsedPercent: RecorderObservabilityReading;
    dataUsedPercent: RecorderObservabilityReading;
    recorderActiveState: RecorderObservabilityReading;
    publisherActiveState: RecorderObservabilityReading;
    publisherBufferBytes: RecorderObservabilityReading;
    publisherBufferLimitBytes: RecorderObservabilityReading;
    networkInterfaces: Array<{
      name: string;
      operState: RecorderObservabilityReading;
      carrier: RecorderObservabilityReading;
      rxErrors: RecorderObservabilityReading;
      txErrors: RecorderObservabilityReading;
    }>;
  };
  readIssues: Array<{ field: string; state: string; detail: string }>;
  readError: null;
};

export function mapRecorderObservabilityDetail(
  row: {
    vrcode: string;
    supportState: RecorderObservabilitySupportState;
    supportSource: string | null;
    reportState: RecorderObservabilityReportState;
    profileState: string | null;
    collectionState: string | null;
    latestObservationReceivedAt: string | null;
    readIssueCount: number;
    expectedSince: string | null;
    recorderVersion: string | null;
    producerVersion: string | null;
    protocolVersion: string | null;
    resources: Record<string, unknown> | null;
  },
): RecorderObservabilityDetail {
  const aggregate = object(row.resources);
  const healthEntry = object(aggregate?.observation);
  const health = object(healthEntry?.document);
  const payload = object(health?.payload);
  const profileRoot = object(aggregate?.recorderProfile);
  const profileEntry = object(profileRoot?.associated);
  const profile = object(profileEntry?.document);
  const bootRoot = object(aggregate?.bootEvent);
  const bootStarted = object(bootRoot?.started);
  const bootStartedDocument = object(bootStarted?.document);
  const bootShutdown = object(bootRoot?.shutdown);
  const bootShutdownDocument = object(bootShutdown?.document);
  const startedBootId = string(bootStartedDocument?.bootId);
  const shutdownBootId = string(bootShutdownDocument?.bootId);
  const shutdownMatchesStartedBoot = startedBootId !== null
    && shutdownBootId === startedBootId;
  const observedAt = string(health?.deviceObservedAt);
  const operationalHealth = assessRecorderOperationalHealth(
    health,
    row.reportState,
  );

  return {
    state: "loaded",
    vrcode: row.vrcode,
    support: {
      state: row.supportState,
      source: row.supportSource,
      expectedSince: row.expectedSince,
      recorderVersion: row.recorderVersion,
      producerVersion: row.producerVersion,
      protocolVersion: row.protocolVersion,
    },
    report: {
      state: row.reportState,
      receivedAt: row.latestObservationReceivedAt,
      deviceObservedAt: observedAt,
      collectionState: row.collectionState,
      readIssueCount: row.readIssueCount,
    },
    profile: {
      state: profileState(row.profileState),
      receivedAt: string(profileEntry?.receivedAt),
      deviceObservedAt: string(profile?.deviceObservedAt),
      deviceId: string(profile?.deviceId),
      bootId: string(profile?.bootId),
      software: readings(
        object(profile?.software),
        [
          "observerPackageVersion",
          "observerArtifactSha256",
          "vitalRecorderVersion",
          "osImageVersion",
          "kernelRelease",
        ],
        string(profile?.deviceObservedAt),
      ),
      collection: collection(object(profile?.collection)),
      capabilities: capabilities(object(profile?.capabilities)),
    },
    boot: {
      state: shutdownMatchesStartedBoot
        ? "shutdownClean"
        : bootStarted
          ? "started"
          : "notReported",
      bootId: startedBootId,
      startedAt: string(bootStartedDocument?.deviceObservedAt),
      cleanShutdownAt: shutdownMatchesStartedBoot
        ? string(object(bootShutdownDocument?.shutdown)?.shutdownAt)
        : null,
    },
    operationalHealth,
    readings: {
      temperatureCelsius: reading(
        object(object(payload?.raspberryPi)?.temperatureCelsius),
        observedAt,
      ),
      memoryAvailableBytes: reading(
        object(object(payload?.memory)?.availableBytes),
        observedAt,
      ),
      memoryTotalBytes: reading(
        object(object(payload?.memory)?.totalBytes),
        observedAt,
      ),
      rootUsedPercent: reading(
        object(object(object(payload?.storage)?.root)?.usedPercent),
        observedAt,
      ),
      dataUsedPercent: reading(
        object(object(object(payload?.storage)?.data)?.usedPercent),
        observedAt,
      ),
      recorderActiveState: reading(
        object(object(payload?.vitalRecorder)?.activeState),
        observedAt,
      ),
      publisherActiveState: reading(
        object(object(payload?.publisher)?.activeState),
        observedAt,
      ),
      publisherBufferBytes: reading(
        object(object(payload?.publisher)?.bufferBytes),
        observedAt,
      ),
      publisherBufferLimitBytes: scalarReading(
        object(payload?.publisher)?.bufferLimitBytes,
        observedAt,
        "publisher.bufferLimitBytes",
      ),
      networkInterfaces: interfaces(
        object(payload?.network)?.interfaces,
        observedAt,
      ),
    },
    readIssues: readIssues(health?.readIssues),
    readError: null,
  };
}

function reading(
  source: Record<string, unknown> | null,
  observedAt: string | null,
): RecorderObservabilityReading {
  const state = source?.state;
  if (!["ok", "missing", "invalid", "failed", "unsupported"].includes(
    typeof state === "string" ? state : "",
  )) {
    return {
      state: source ? "invalid" : "missing",
      value: null,
      detail: source ? "reading state is invalid" : "reading is absent",
      observedAt,
    };
  }
  if (state === "ok") {
    if (!Object.hasOwn(source, "value")) {
      return {
        state: "invalid",
        value: null,
        detail: "ok reading value is absent",
        observedAt,
      };
    }
    return {
      state,
      value: jsonValue(source.value),
      detail: null,
      observedAt,
    };
  }
  return {
    state: state as RecorderObservabilityReading["state"],
    value: null,
    detail: string(source.detail) || "reading detail is absent",
    observedAt,
  };
}

function scalarReading(
  value: unknown,
  observedAt: string | null,
  field: string,
): RecorderObservabilityReading {
  return typeof value === "number"
    ? { state: "ok", value, detail: null, observedAt }
    : {
        state: value === undefined ? "missing" : "invalid",
        value: null,
        detail: `${field} is ${value === undefined ? "absent" : "invalid"}`,
        observedAt,
      };
}

function readings(
  source: Record<string, unknown> | null,
  fields: string[],
  observedAt: string | null,
) {
  return Object.fromEntries(fields.map((field) => [
    field,
    reading(object(source?.[field]), observedAt),
  ]));
}

function collection(source: Record<string, unknown> | null) {
  if (!source) return null;
  return {
    powerIntervalSeconds: number(source.powerIntervalSeconds),
    telemetryIntervalSeconds: number(source.telemetryIntervalSeconds),
    observationIntervalSeconds: number(source.observationIntervalSeconds),
  };
}

function capabilities(source: Record<string, unknown> | null) {
  if (!source) return {};
  return Object.fromEntries(Object.entries(source).map(([name, value]) => {
    const item = object(value);
    return [name, {
      state: string(item?.state) || "invalid",
      source: string(item?.source),
      detail: string(item?.detail),
    }];
  }));
}

function interfaces(value: unknown, observedAt: string | null) {
  if (!Array.isArray(value)) return [];
  return value.flatMap((entry) => {
    const item = object(entry);
    const name = string(item?.name);
    return name
      ? [{
          name,
          operState: reading(object(item?.operState), observedAt),
          carrier: reading(object(item?.carrier), observedAt),
          rxErrors: reading(object(item?.rxErrors), observedAt),
          txErrors: reading(object(item?.txErrors), observedAt),
        }]
      : [];
  });
}

function readIssues(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value.map((entry, index) => {
    const item = object(entry);
    const field = string(item?.field);
    const state = string(item?.state);
    const detail = string(item?.detail);
    return field && state && detail
      ? { field, state, detail }
      : {
          field: `readIssues[${index}]`,
          state: "invalid",
          detail: "read issue contract is invalid",
        };
  });
}

function profileState(
  value: string | null,
): RecorderObservabilityDetail["profile"]["state"] {
  if (value === "associated") return "associated";
  if (value === "latest_unassociated" || value === "unassociated") {
    return "unassociated";
  }
  if (value === "missing" || value === null) return "missing";
  return "invalid";
}

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function string(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function number(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function jsonValue(value: unknown): JSONValue {
  if (value === null) return null;
  if (typeof value === "string") return value;
  if (typeof value === "boolean") return value;
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (Array.isArray(value)) return value.map(jsonValue);
  const source = object(value);
  return source
    ? Object.fromEntries(Object.entries(source).map(([key, item]) => [
        key,
        jsonValue(item),
      ]))
    : null;
}

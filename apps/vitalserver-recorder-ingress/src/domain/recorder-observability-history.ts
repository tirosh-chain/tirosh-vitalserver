export type RecorderObservabilityTimelineQuery = {
  vrcode: string;
  from: string;
  until: string;
  bucketSeconds: 300 | 900 | 3600;
};

export type RecorderObservabilityTimelineRow = {
  bucketStartedAt: string;
  sampleCount: number;
  metrics: Record<string, {
    average: number | null;
    stateCounts: Record<string, number>;
  }>;
};

export type RecorderObservabilityTimelineReadModel = {
  supportState: "supported" | "unsupported" | "unknown";
  rows: RecorderObservabilityTimelineRow[];
};

export type RecorderObservabilityIncidentQuery = {
  vrcode: string;
  from: string;
  until: string;
  incidentType: string | null;
  cursor: { receivedAt: string; recordId: string; code: string | null } | null;
  limit: number;
};

export type RecorderObservabilityIncidentRow = {
  incidentId: string;
  recordId: string;
  eventId: string;
  category: "kernel" | "boot" | "power" | "evidence";
  code: string;
  severity: "warning" | "critical";
  state: "active" | "recovering" | "historical";
  bootId: string | null;
  occurredAt: string | null;
  receivedAt: string;
  timeState: string | null;
  summary: string;
  evidence: Array<{
    field: string;
    state: string;
    detail: string | null;
  }>;
  source: "kernelIncident" | "bootEvent" | "observation";
  // Kept for the explicitly retained kernel incident evidence contract.
  capturedAt: string | null;
  captureTimeState: string | null;
  incidentType: string;
  incidentBootId: string | null;
  messageExcerpt: string | null;
  truncated: boolean;
};

const MAX_TIMELINE_SECONDS = 24 * 60 * 60;
const MAX_INCIDENT_SECONDS = 30 * 24 * 60 * 60;
const INCIDENT_TYPES = new Set([
  "panic",
  "oops",
  "watchdog",
  "lockup",
  "unknown",
  "boot-loop",
  "repeated-undervoltage",
  "ledger-continuity",
]);

export type RecorderObservabilityHistoryRoute =
  | { kind: "detail"; vrcode: string }
  | { kind: "timeline"; query: RecorderObservabilityTimelineQuery }
  | { kind: "incidents"; query: RecorderObservabilityIncidentQuery }
  | { kind: "list" }
  | { kind: "invalid"; reason: string };

export function parseRecorderObservabilityHistoryRoute(
  requestURL: string | undefined,
): RecorderObservabilityHistoryRoute | null {
  const url = new URL(requestURL || "/", "http://recorder-ingress");
  if (url.pathname === "/runtime/vitaldb/recorders") return { kind: "list" };
  const match = url.pathname.match(
    /^\/runtime\/vitaldb\/recorders\/([^/]+)\/observability(?:\/(timeline|incidents))?$/,
  );
  if (!match) {
    return url.pathname.startsWith("/runtime/vitaldb/recorders/")
      ? { kind: "invalid", reason: "path_invalid" }
      : null;
  }
  const vrcode = decodedVrcode(match[1]);
  if (!vrcode) return { kind: "invalid", reason: "vrcode_invalid" };
  if (!match[2]) return { kind: "detail", vrcode };
  const from = timestamp(url.searchParams.get("from"));
  const until = timestamp(url.searchParams.get("until"));
  if (!from || !until || until.epoch <= from.epoch) {
    return { kind: "invalid", reason: "time_window_invalid" };
  }
  const windowSeconds = (until.epoch - from.epoch) / 1000;
  if (match[2] === "timeline") {
    const bucket = Number(url.searchParams.get("bucketSeconds"));
    if (windowSeconds > MAX_TIMELINE_SECONDS) {
      return { kind: "invalid", reason: "timeline_window_too_large" };
    }
    if (bucket !== 300 && bucket !== 900 && bucket !== 3600) {
      return { kind: "invalid", reason: "bucket_seconds_invalid" };
    }
    return {
      kind: "timeline",
      query: {
        vrcode,
        from: from.value,
        until: until.value,
        bucketSeconds: bucket,
      },
    };
  }
  if (windowSeconds > MAX_INCIDENT_SECONDS) {
    return { kind: "invalid", reason: "incident_window_too_large" };
  }
  const incidentType = url.searchParams.get("type");
  if (incidentType !== null && !INCIDENT_TYPES.has(incidentType)) {
    return { kind: "invalid", reason: "incident_type_invalid" };
  }
  const limit = Number(url.searchParams.get("limit") || "50");
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    return { kind: "invalid", reason: "incident_limit_invalid" };
  }
  const cursorValue = url.searchParams.get("cursor");
  const cursor = cursorValue === null ? null : decodeIncidentCursor(cursorValue);
  if (cursorValue !== null && cursor === null) {
    return { kind: "invalid", reason: "incident_cursor_invalid" };
  }
  return {
    kind: "incidents",
    query: {
      vrcode,
      from: from.value,
      until: until.value,
      incidentType,
      cursor,
      limit,
    },
  };
}

export function timelineDocument(
  query: RecorderObservabilityTimelineQuery,
  readModel: RecorderObservabilityTimelineReadModel,
) {
  return {
    state: readModel.rows.length > 0
      ? "loaded"
      : readModel.supportState === "unsupported"
        ? "unsupported"
        : "notReported",
    vrcode: query.vrcode,
    supportState: readModel.supportState,
    timeBasis: "receivedAt",
    query: {
      from: query.from,
      until: query.until,
      bucketSeconds: query.bucketSeconds,
    },
    buckets: readModel.rows,
    readError: null,
  };
}

export function incidentsDocument(
  query: RecorderObservabilityIncidentQuery,
  rows: RecorderObservabilityIncidentRow[],
) {
  const visible = rows.slice(0, query.limit);
  const last = visible.at(-1);
  return {
    state: "loaded",
    vrcode: query.vrcode,
    timeBasis: "receivedAt",
    incidents: visible,
    nextCursor: rows.length > query.limit && last
      ? encodeIncidentCursor(last.receivedAt, last.recordId, last.code)
      : null,
    readError: null,
  };
}

export function encodeIncidentCursor(
  receivedAt: string,
  recordId: string,
  code: string | null = null,
): string {
  return Buffer.from(JSON.stringify([receivedAt, recordId, code]), "utf8")
    .toString("base64url");
}

function decodeIncidentCursor(
  value: string,
): { receivedAt: string; recordId: string; code: string | null } | null {
  try {
    const decoded = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
    if (!Array.isArray(decoded) || (decoded.length !== 2 && decoded.length !== 3)) return null;
    const receivedAt = timestamp(decoded[0]);
    const recordId = decoded[1];
    const code = decoded.length === 3 ? decoded[2] : null;
    return receivedAt && typeof recordId === "string" && /^[1-9][0-9]*$/.test(recordId)
      && (code === null || typeof code === "string")
      ? { receivedAt: receivedAt.value, recordId, code }
      : null;
  } catch (_error) {
    return null;
  }
}

function decodedVrcode(value: string): string | null {
  try {
    const decoded = decodeURIComponent(value);
    return /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(decoded) ? decoded : null;
  } catch (_error) {
    return null;
  }
}

function timestamp(value: unknown): { value: string; epoch: number } | null {
  if (typeof value !== "string" || value.trim() === "") return null;
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(value)) {
    return null;
  }
  const epoch = Date.parse(value);
  return Number.isFinite(epoch)
    ? { value: new Date(epoch).toISOString(), epoch }
    : null;
}

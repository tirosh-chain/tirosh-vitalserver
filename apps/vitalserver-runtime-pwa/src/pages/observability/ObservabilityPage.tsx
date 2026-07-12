import { useMemo, useState } from "react";

import {
  useLatestVitalDBObservation,
  usePlatformState,
  useRuntimeEvents,
  useVitalDBRecorders
} from "@/console/hooks";
import type { RuntimeEventQuery } from "@/console/runtimeControlGateway";
import type {
  RuntimeEventDocument,
  RuntimeVitalDBObservationSnapshot,
  VitalDBAnomalyObservation,
  VitalDBObservationDocument
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import type { RuntimeEventTypeValue } from "@/domain/runtime-control/contracts/runtimeEventTypes";
import {
  formatVitalRecorderObservationMetric,
  vitalRecorderSummaryFromHistory,
  type RuntimeVitalRecorderSummary
} from "@/domain/runtime-control/formatting/vitalRecorder";
import { formatLocalDateTime } from "@/domain/runtime-control/formatting/time";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { Panel } from "@/components/Panel";
import { StatusBadge, type StatusBadgeProps } from "@/components/StatusBadge";
import {
  runtimeEventPeriods,
  runtimeEventTypes,
  sinceForPeriod,
  type RuntimeEventPeriod
} from "@/domain/runtime-control/events/eventFilters";

export function ObservabilityPage() {
  const [period, setPeriod] = useState<RuntimeEventPeriod>("24h");
  const [eventType, setEventType] = useState<RuntimeEventTypeValue | "">("");
  const [limit, setLimit] = useState(50);
  const dailyEventRequest = useMemo(
    () => ({
      limit: 500,
      since: sinceForPeriod("24h")
    }),
    []
  );
  const eventRequest = useMemo(
    () => {
      const request: RuntimeEventQuery = {
        limit,
        since: sinceForPeriod(period)
      };
      if (eventType) {
        request.type = eventType;
      }
      return request;
    },
    [eventType, limit, period]
  );
  const observationQuery = useLatestVitalDBObservation();
  const recordersQuery = useVitalDBRecorders();
  const platformStateQuery = usePlatformState();
  const dailyEventsQuery = useRuntimeEvents(dailyEventRequest);
  const eventQuery = useRuntimeEvents(eventRequest);

  const vitalDBObservationRead = selectVitalDBObservationRead(
    observationQuery.data,
    observationQuery.error
  );
  const recorderSummary = vitalRecorderSummaryFromHistory(recordersQuery.data);
  const eventRead = runtimeEventsRead(eventQuery);
  const dailyEventRead = runtimeEventsRead(dailyEventsQuery);
  const anomalyReadIssue = vitalDBObservationAnomalyReadIssue(
    vitalDBObservationRead
  );
  const runtimeEvents = useMemo(
    () =>
      eventRead.state === "loaded"
        ? sortRuntimeEventsNewestFirst(eventRead.events)
        : [],
    [eventRead]
  );

  return (
    <div className="page-stack">
      <Panel title="Observation pipeline">
        <KeyValueRows
          rows={[
            {
              label: "VitalDB Observer",
              value: formatObserverStatus(vitalDBObservationRead)
            },
            {
              label: "Guest log sync service",
              value: formatGuestLogSyncService(
                platformStateQuery.data?.services.some(
                  (service) => service.role === "log-sync" && service.state === "running"
                )
              )
            },
            {
              label: "Observation updated",
              value:
                vitalDBObservationRead.state === "loaded"
                  ? formatLocalDateTime(vitalDBObservationRead.observation.observedAt)
                  : "Not reported"
            },
            {
              label: "Known recorders",
              value: formatVitalRecorderObservationMetric(
                recorderSummary,
                "knownRecorders"
              )
            },
            {
              label: "Known beds",
              value: formatVitalRecorderObservationMetric(
                recorderSummary,
                "knownBeds"
              )
            },
            {
              label: "Recorder anomalies",
              value: formatRecorderAnomalyMetric(
                recorderSummary,
                vitalDBObservationRead
              )
            },
            {
              label: "Runtime events (24h)",
              value: formatRuntimeEventCount(dailyEventRead)
            }
          ]}
        />
      </Panel>

      <Panel title="Recorder anomalies">
        {anomalyReadIssue ? (
          <ErrorState
            title="Recorder anomaly details are incomplete"
            error={new Error(anomalyReadIssue)}
          />
        ) : null}

        {vitalDBObservationRead.state !== "loaded" ? (
          <p className="empty-state">
            {vitalDBObservationReadEmptyMessage(vitalDBObservationRead)}
          </p>
        ) : vitalDBObservationRead.observation.anomalies.length === 0 &&
          !anomalyReadIssue ? (
          <p className="empty-state">No recorder anomalies were reported.</p>
        ) : vitalDBObservationRead.observation.anomalies.length === 0 ? (
          <p className="empty-state">
            Recorder anomaly records are incomplete.
          </p>
        ) : (
          <div className="anomaly-list">
            {vitalDBObservationRead.observation.anomalies.map((anomaly, index) => (
              <AnomalyItem
                key={anomaly.id ?? `${anomaly.kind ?? "anomaly"}-${index}`}
                anomaly={anomaly}
              />
            ))}
          </div>
        )}
      </Panel>

      <Panel title="Runtime Events">
        <div className="toolbar">
          <label>
            Period
            <select
              value={period}
              onChange={(event) =>
                setPeriod(parseRuntimeEventPeriod(event.target.value))
              }
            >
              {runtimeEventPeriods.map((candidate) => (
                <option key={candidate.value} value={candidate.value}>
                  {candidate.label}
                </option>
              ))}
            </select>
          </label>
          <label>
            Filter
            <select
              value={eventType}
              onChange={(event) =>
                setEventType(event.target.value as RuntimeEventTypeValue | "")
              }
            >
              <option value="">All events</option>
              {runtimeEventTypes.map((type) => (
                <option key={type} value={type}>
                  {type}
                </option>
              ))}
            </select>
          </label>
          <label>
            Limit
            <select
              value={limit}
              onChange={(event) => setLimit(Number(event.target.value))}
            >
              {[25, 50, 100, 250].map((candidate) => (
                <option key={candidate} value={candidate}>
                  {candidate}
                </option>
              ))}
            </select>
          </label>
          <span className="toolbar-count">
            {formatRuntimeEventCount(eventRead)}
          </span>
        </div>

        {eventRead.state === "loading" ? (
          <p className="empty-state">Loading runtime events...</p>
        ) : eventRead.state === "failed" ? (
          <ErrorState
            title="Runtime events are not available"
            error={eventRead.error}
          />
        ) : eventRead.state === "missing" ? (
          <ErrorState
            title="Runtime event response is incomplete"
            error={new Error("Runtime events response is missing events.")}
          />
        ) : eventRead.events.length === 0 ? (
          <p className="empty-state">No runtime events were found for this period.</p>
        ) : (
          <div className="event-list">
            {runtimeEvents.map((event) => (
              <RuntimeEventItem key={event.id ?? event.timestamp} event={event} />
            ))}
          </div>
        )}
      </Panel>
    </div>
  );
}

function sortRuntimeEventsNewestFirst(
  events: RuntimeEventDocument[]
): RuntimeEventDocument[] {
  return events
    .map((event, index) => ({
      event,
      index,
      timestamp: Date.parse(event.timestamp ?? "")
    }))
    .sort((left, right) => {
      const leftHasTimestamp = Number.isFinite(left.timestamp);
      const rightHasTimestamp = Number.isFinite(right.timestamp);
      if (leftHasTimestamp && rightHasTimestamp) {
        return right.timestamp - left.timestamp;
      }
      if (leftHasTimestamp) {
        return -1;
      }
      if (rightHasTimestamp) {
        return 1;
      }
      return left.index - right.index;
    })
    .map(({ event }) => event);
}

function AnomalyItem({ anomaly }: { anomaly: VitalDBAnomalyObservation }) {
  const severity = anomaly.severity ?? "unknown";

  return (
    <article className="anomaly-item">
      <div className="anomaly-meta">
        <StatusBadge tone={anomalySeverityTone(anomaly.severity)}>
          {severity}
        </StatusBadge>
        <strong>{anomaly.kind ?? "unknown"}</strong>
        <span>{anomaly.subject ?? "Unknown subject"}</span>
        <span>{formatLocalDateTime(anomaly.observedAt)}</span>
      </div>
      <p>{anomaly.message ?? "No anomaly message was reported."}</p>
    </article>
  );
}

function RuntimeEventItem({ event }: { event: RuntimeEventDocument }) {
  return (
    <article className="event-item">
      <div className="event-meta">
        <span>{formatLocalDateTime(event.timestamp)}</span>
        <strong>{event.eventType}</strong>
        <span>{event.operationState}</span>
        <span className="event-operation">
          {event.operationCommand || event.operationId}
        </span>
      </div>
      <h3>{event.message || "Message not reported"}</h3>
      <p>{event.source ? `source: ${event.source}` : "source not reported"}</p>
      {event.failure ? <p>{`${event.failure.kind}: ${event.failure.message}`}</p> : null}
    </article>
  );
}

type VitalDBObservationRead =
  | {
      state: "loaded";
      observation: VitalDBObservationDocument;
      readError: string | null;
    }
  | {
      state: "failed";
      readError: string;
    }
  | {
      state: "unavailable";
      readError: string | null;
    }
  | {
      state: "notReported";
    };

type VitalDBObservationReadIssue = VitalDBObservationDocument["readIssues"][number];

function selectVitalDBObservationRead(
  snapshot: RuntimeVitalDBObservationSnapshot | undefined,
  transportError: Error | null
): VitalDBObservationRead {
  if (transportError) {
    return { state: "failed", readError: transportError.message };
  }
  if (!snapshot?.state) {
    return { state: "notReported" };
  }
  if (snapshot.state === "loaded") {
    if (snapshot.observation) {
      return {
        state: "loaded",
        observation: snapshot.observation,
        readError: snapshot.readError ?? null
      };
    }
    return {
      state: "failed",
      readError: "VitalDB observation snapshot is loaded but observation is missing."
    };
  }
  if (snapshot.state === "failed") {
    return {
      state: "failed",
      readError: snapshot.readError || "VitalDB observation read failed."
    };
  }
  return {
    state: "unavailable",
    readError: snapshot.readError ?? null
  };
}

function formatObserverStatus(read: VitalDBObservationRead): string {
  switch (read.state) {
    case "loaded":
      if (read.readError) {
        return read.observation.ready ? "Ready with issues" : "Unhealthy with issues";
      }
      return read.observation.ready ? "Ready" : "Unhealthy";
    case "failed":
      return "Failed";
    case "unavailable":
      return "Unavailable";
    case "notReported":
      return "Not reported";
  }
}

function vitalDBObservationReadEmptyMessage(read: VitalDBObservationRead): string {
  switch (read.state) {
    case "loaded":
      return "";
    case "failed":
      return "VitalDB observation read failed.";
    case "unavailable":
      return "VitalDB observation is unavailable.";
    case "notReported":
      return "VitalDB observation has not been reported.";
  }
}

function vitalDBObservationAnomalyReadIssue(
  read: VitalDBObservationRead
): string | null {
  if (read.state === "failed") {
    return read.readError;
  }
  if (read.state === "unavailable") {
    return read.readError;
  }
  if (read.state !== "loaded") {
    return null;
  }
  const observationIssues =
    read.observation.readIssues.length > 0
      ? formatVitalDBObservationReadIssues(read.observation.readIssues)
      : null;
  return [read.readError, observationIssues].filter(Boolean).join("; ") || null;
}

function formatVitalDBObservationReadIssues(
  issues: VitalDBObservationReadIssue[]
): string {
  const groups = new Map<
    string,
    { source: string; message: string; count: number }
  >();
  for (const issue of issues) {
    const message = skippedAuditEventReason(issue.message) ?? issue.message;
    const key = `${issue.source}\u0000${message}`;
    const group = groups.get(key);
    if (group) {
      group.count += 1;
    } else {
      groups.set(key, { source: issue.source, message, count: 1 });
    }
  }

  const formatted = Array.from(groups.values()).map((group) =>
    group.count === 1
      ? `${group.source}: ${group.message}`
      : `${group.source}: ${group.count} events were skipped: ${group.message}`
  );
  const visible = formatted.slice(0, 5);
  const omittedCount = formatted.length - visible.length;
  if (omittedCount > 0) {
    visible.push(`${omittedCount} additional read issue groups were omitted`);
  }
  return visible.join("; ");
}

function skippedAuditEventReason(message: string): string | null {
  return /^event \d+ was skipped: (.+)$/.exec(message)?.[1] ?? null;
}

type RuntimeEventsRead =
  | {
      state: "loading";
    }
  | {
      state: "failed";
      error: unknown;
    }
  | {
      state: "missing";
    }
  | {
      state: "loaded";
      events: RuntimeEventDocument[];
      matchingCount: number | null;
    };

function runtimeEventsRead(query: {
  data?: { events?: RuntimeEventDocument[]; matchingCount?: number | null };
  error: unknown;
  isError: boolean;
  isPending: boolean;
}): RuntimeEventsRead {
  if (query.isPending) {
    return { state: "loading" };
  }
  if (query.isError) {
    return { state: "failed", error: query.error };
  }
  if (!query.data || !Array.isArray(query.data.events)) {
    return { state: "missing" };
  }
  return {
    state: "loaded",
    events: query.data.events,
    matchingCount:
      typeof query.data.matchingCount === "number" ? query.data.matchingCount : null
  };
}

function formatRuntimeEventCount(read: RuntimeEventsRead): string {
  switch (read.state) {
    case "loaded":
      if (read.matchingCount !== null && read.matchingCount !== read.events.length) {
        return `${read.events.length} shown · ${read.matchingCount} matching`;
      }
      return `${read.events.length} events`;
    case "loading":
      return "Loading...";
    case "failed":
      return "Failed";
    case "missing":
      return "Not reported";
  }
}

function formatGuestLogSyncService(value: boolean | null | undefined): string {
  if (value === true) {
    return "Running";
  }
  if (value === false) {
    return "Stopped";
  }
  return "Not reported";
}

function formatRecorderAnomalyMetric(
  recorderSummary: RuntimeVitalRecorderSummary | undefined,
  read: VitalDBObservationRead
): string {
  const summaryValue = String(formatVitalRecorderObservationMetric(
    recorderSummary,
    "recorderAnomalies"
  ));
  if (read.state !== "loaded") {
    return summaryValue;
  }
  const detailCount = read.observation.anomalies.length;
  if (String(detailCount) === String(summaryValue)) {
    return summaryValue;
  }
  return `${summaryValue} reported, ${detailCount} detailed`;
}

function parseRuntimeEventPeriod(value: string): RuntimeEventPeriod {
  const period = runtimeEventPeriods.find((candidate) => candidate.value === value);
  return period?.value ?? "24h";
}

function anomalySeverityTone(
  severity: VitalDBAnomalyObservation["severity"]
): StatusBadgeProps["tone"] {
  switch (severity) {
    case "critical":
      return "danger";
    case "warning":
      return "warning";
    case "info":
      return "neutral";
    default:
      return "neutral";
  }
}

import { useState } from "react";

import { useRuntimeEvents, useRuntimeOverview } from "../../application/runtime-control/queries";
import type { RuntimeEventDocument } from "../../domain/runtime-control/contracts/runtimeControlTypes";
import { formatRuntimeState } from "../../domain/runtime-control/formatting/runtimeState";
import { formatLocalDateTime } from "../../domain/runtime-control/formatting/time";
import { KeyValueRows } from "../../shared/ui/KeyValueRows";
import { Panel } from "../../shared/ui/Panel";
import {
  runtimeEventPeriods,
  runtimeEventTypes,
  sinceForPeriod,
  type RuntimeEventPeriod
} from "../../domain/runtime-control/events/eventFilters";

export function ObservabilityPage() {
  const [period, setPeriod] = useState<RuntimeEventPeriod>("24h");
  const [eventType, setEventType] = useState("");
  const [limit, setLimit] = useState(50);
  const overviewQuery = useRuntimeOverview();
  const dailyEventsQuery = useRuntimeEvents({
    limit: 500,
    since: sinceForPeriod("24h")
  });
  const eventQuery = useRuntimeEvents({
    limit,
    since: sinceForPeriod(period),
    type: eventType || undefined
  });

  const overview = overviewQuery.data;
  const recorderSummary = overview?.vitalRecorder;
  const eventCount = eventQuery.data?.events?.length ?? 0;
  const dailyEventCount = dailyEventsQuery.data?.events?.length ?? 0;

  return (
    <div className="page-stack">
      <Panel title="Observation pipeline">
        <KeyValueRows
          rows={[
            {
              label: "VitalDB Observer",
              value: overview?.vitalDBObservation?.ready ? "Ready" : "Unknown"
            },
            {
              label: "Guest log sync service",
              value: overview?.status?.guestLogSyncServiceLoaded
                ? "Running"
                : "Stopped"
            },
            {
              label: "Observation updated",
              value: formatLocalDateTime(recorderSummary?.observedAt)
            },
            {
              label: "Known recorders",
              value: recorderSummary?.knownRecorders ?? 0
            },
            {
              label: "Known beds",
              value: recorderSummary?.knownBeds ?? 0
            },
            {
              label: "Recorder anomalies",
              value: recorderSummary?.recorderAnomalies ?? 0
            },
            {
              label: "Runtime events (24h)",
              value: dailyEventCount
            }
          ]}
        />
      </Panel>

      <Panel title="Runtime Events">
        <div className="toolbar">
          <label>
            Period
            <select
              value={period}
              onChange={(event) => setPeriod(event.target.value as RuntimeEventPeriod)}
            >
              {runtimeEventPeriods.map((candidate) => (
                <option key={candidate.value} value={candidate.value}>
                  {candidate.label}
                </option>
              ))}
            </select>
          </label>
          <label>
            Type
            <select
              value={eventType}
              onChange={(event) => setEventType(event.target.value)}
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
          <span className="toolbar-count">{eventCount} events</span>
        </div>

        {eventQuery.isPending ? (
          <p className="empty-state">Loading runtime events...</p>
        ) : eventQuery.isError ? (
          <p className="error-state">Runtime events are not available.</p>
        ) : (
          <div className="event-list">
            {(eventQuery.data.events ?? []).map((event) => (
              <RuntimeEventItem key={event.id ?? event.timestamp} event={event} />
            ))}
          </div>
        )}
      </Panel>
    </div>
  );
}

function RuntimeEventItem({ event }: { event: RuntimeEventDocument }) {
  return (
    <article className="event-item">
      <div className="event-meta">
        <span>{formatLocalDateTime(event.timestamp)}</span>
        <strong>{event.eventType}</strong>
        <span>{formatRuntimeState(event.status)}</span>
        <span className="event-source">{event.operation || event.source}</span>
      </div>
      <h3>{event.message || event.eventType || "Runtime event"}</h3>
      {event.failureReasons?.length ? (
        <p>{event.failureReasons.join(", ")}</p>
      ) : null}
    </article>
  );
}

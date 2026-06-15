import { useMemo, useState } from "react";

import { useVitalDBRecorders, useVitalDBRelationships } from "@/console/hooks";
import type {
  VitalDBRecorderRecord,
  VitalDBRecorders,
  VitalDBRelationships
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  formatBoolean,
  formatRecorderStatus,
  recorderStatusTone
} from "@/domain/runtime-control/formatting/status";
import {
  formatLocalDateTime,
  formatLocalDateTimeWithAge
} from "@/domain/runtime-control/formatting/time";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import { DataTable } from "@/components/DataTable";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { MetricStrip } from "@/components/MetricStrip";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";
import { RecorderActivityChart } from "./RecorderActivityChart";
import { RelationshipHistory } from "@/pages/relationships/RelationshipHistory";

export function RecordersPage() {
  const recordersQuery = useVitalDBRecorders();
  const relationshipsQuery = useVitalDBRelationships();
  const allRecorders = useMemo(
    () =>
      recordersQuery.data === undefined
        ? null
        : [...recordersQuery.data.recorders].sort(sortByLastSeen),
    [recordersQuery.data]
  );
  const [searchText, setSearchText] = useState("");
  const [showHistory, setShowHistory] = useState(false);
  const [selectedVrcode, setSelectedVrcode] = useState<string | null>(null);
  const visibleRecorders = allRecorders === null
    ? null
    : showHistory
      ? allRecorders
      : allRecorders.filter(
          (recorder) => recorder.presentInLatestObservation === true
        );
  const recorders = visibleRecorders === null
    ? null
    : filterRecorders(visibleRecorders, searchText);
  const selectedRecorder =
    recorders?.find((recorder) => recorder.vrcode === selectedVrcode) ??
    recorders?.[0] ??
    null;
  const summary = recordersQuery.data?.summary ?? null;

  return (
    <div className="page-stack">
      <Panel
        title="Recorders"
        actions={
          <div className="toolbar compact-toolbar">
            <input
              type="search"
              placeholder="Search VRecorders"
              value={searchText}
              onChange={(event) => setSearchText(event.target.value)}
            />
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={showHistory}
                onChange={(event) => setShowHistory(event.target.checked)}
              />
              History
            </label>
            <button
              type="button"
              disabled={recordersQuery.isFetching}
              onClick={() => recordersQuery.refetch()}
            >
              Refresh
            </button>
          </div>
        }
      >
        <MetricStrip
          metrics={[
            {
              label: "Known recorders",
              value: summary?.knownRecorders ?? NOT_REPORTED
            },
            { label: "Current", value: summary?.currentRecorders ?? NOT_REPORTED },
            {
              label: "Online recorders",
              value: summary?.onlineRecorders ?? NOT_REPORTED
            },
            {
              label: "Stale recorders",
              value: summary?.staleRecorders ?? NOT_REPORTED
            },
            {
              label: "Recorder anomalies",
              value: summary?.recorderAnomalies ?? NOT_REPORTED
            },
            {
              label: "Data updated",
              value: formatLocalDateTime(recordersQuery.data?.updatedAt)
            }
          ]}
        />

        {recordersQuery.isPending ? (
          <p className="empty-state">Loading VRecorders...</p>
        ) : recordersQuery.isError ? (
          <ErrorState
            title="VRecorder history is not available"
            error={recordersQuery.error}
          />
        ) : recorders === null ? (
          <ErrorState
            title="VRecorder history response is incomplete"
            error={
              new Error("Runtime Control API did not return VRecorder history data.")
            }
          />
        ) : (
          <DataTable
            rows={recorders}
            getRowKey={(recorder) => recorder.vrcode}
            selectedKey={selectedRecorder?.vrcode}
            onSelectRow={(recorder) => setSelectedVrcode(recorder.vrcode)}
            emptyText="No VRecorders found."
            columns={[
              {
                key: "vrcode",
                header: "VRecorder",
                render: (recorder) => <strong>{recorder.vrcode}</strong>
              },
              {
                key: "status",
                header: "Status",
                render: (recorder) => (
                  <StatusBadge tone={recorderStatusTone(recorder.status)}>
                    {formatRecorderStatus(recorder.status)}
                  </StatusBadge>
                )
              },
              {
                key: "ip",
                header: "IP",
                render: (recorder) => (
                  <div>
                    <div>{recorder.lastIP ?? NOT_REPORTED}</div>
                    <span className="muted">
                      {formatIPVerificationSummary(recorder.redisIPSync)}
                    </span>
                  </div>
                )
              },
              {
                key: "bed",
                header: "Bed",
                render: (recorder) =>
                  recorder.bedName ?? recorder.bedID ?? NOT_REPORTED
              },
              {
                key: "lastSeen",
                header: "Last seen",
                render: (recorder) => formatLocalDateTimeWithAge(recorder.lastSeenAt)
              },
              {
                key: "anomaly",
                header: "Anomaly",
                render: (recorder) => formatAnomalySummary(recorder)
              }
            ]}
          />
        )}
      </Panel>

      {selectedRecorder && recordersQuery.data ? (
        <RecorderDetails
          recorder={selectedRecorder}
          activityHistory={recordersQuery.data.activityHistory}
          relationships={relationshipsQuery.data}
          relationshipsError={relationshipsQuery.error}
        />
      ) : null}
    </div>
  );
}

function RecorderDetails({
  recorder,
  activityHistory,
  relationships,
  relationshipsError
}: {
  recorder: VitalDBRecorderRecord;
  activityHistory: VitalDBRecorders["activityHistory"];
  relationships: VitalDBRelationships | undefined;
  relationshipsError: unknown;
}) {
  const assignments = (relationships?.assignments ?? []).filter(
    (assignment) => assignment.vrcode === recorder.vrcode
  );
  const events = (relationships?.events ?? []).filter(
    (event) =>
      event.vrcode === recorder.vrcode || event.previousVrcode === recorder.vrcode
  );

  return (
    <Panel title="Recorder Details">
      <div className="detail-heading">
        <StatusBadge tone={recorderStatusTone(recorder.status)}>
          <strong>{recorder.vrcode}</strong>
          {formatRecorderStatus(recorder.status)}
        </StatusBadge>
        <span>{formatLocalDateTime(recorder.lastSeenAt)}</span>
      </div>

      <KeyValueRows
        rows={[
          { label: "Version", value: recorder.version ?? NOT_REPORTED },
          {
            label: "Bed",
            value: recorder.bedName ?? recorder.bedID ?? NOT_REPORTED
          },
          { label: "Patient", value: formatBoolean(recorder.patientConnected) },
          { label: "First seen", value: formatLocalDateTime(recorder.firstSeenAt) },
          {
            label: "Last seen",
            value: formatLocalDateTimeWithAge(recorder.lastSeenAt)
          },
          {
            label: "Latest anomaly",
            value: formatAnomalySummary(recorder)
          }
        ]}
      />

      <div className="subsection">
        <h3>Network access</h3>
        <KeyValueRows
          rows={[
            { label: "Connection IP", value: recorder.lastIP ?? NOT_REPORTED },
            {
              label: "IP verification",
              value: formatIPVerificationDetail(recorder.redisIPSync)
            },
            {
              label: "Active IP",
              value: recorder.redisIPSync?.selectedIp ?? NOT_REPORTED
            },
            {
              label: "Last checked",
              value: formatLocalDateTime(
                recorder.redisIPSync?.lastVerifiedAt ??
                  recorder.redisIPSync?.lastWriteAt
              )
            },
            {
              label: "Last issue",
              value: recorder.redisIPSync?.lastFailure ?? "-"
            }
          ]}
        />
      </div>

      <div className="subsection">
        <h3>Activity</h3>
        {activityHistory.readError ? (
          <ErrorState
            title="Recorder activity history is incomplete"
            error={new Error(activityHistory.readError)}
          />
        ) : (
          <RecorderActivityChart recorder={recorder} />
        )}
      </div>

      <RelationshipHistory
        title="recorder"
        relationships={relationships}
        relationshipsError={relationshipsError}
        assignments={assignments}
        events={events}
      />
    </Panel>
  );
}

function formatIPVerificationSummary(
  sync: VitalDBRecorderRecord["redisIPSync"] | null | undefined
): string {
  switch (sync?.status) {
    case "verified":
      return "IP verified";
    case "corrected":
      return "IP updated";
    case "correcting":
      return "Updating IP";
    case "mismatch":
      return "IP mismatch";
    case "write_failed":
      return "IP update failed";
    case "verify_failed":
      return "IP check failed";
    case "pending":
    case "written":
      return "IP check pending";
    case "disabled":
      return "IP tracking disabled";
    case "unknown":
      return "IP status unknown";
    case "unavailable":
      return "IP status unavailable";
    default:
      return "IP status not reported";
  }
}

function formatIPVerificationDetail(
  sync: VitalDBRecorderRecord["redisIPSync"] | null | undefined
): string {
  const summary = formatIPVerificationSummary(sync);
  const timestamp = sync?.lastVerifiedAt ?? sync?.lastWriteAt;
  if (!timestamp) {
    return summary;
  }
  return `${summary} at ${formatLocalDateTime(timestamp)}`;
}

function formatAnomalySummary(
  record: Pick<
    VitalDBRecorderRecord,
    | "currentAnomalyCount"
    | "latestAnomalyKind"
    | "latestAnomalySeverity"
    | "latestAnomalyMessage"
  >
): string {
  if (record.currentAnomalyCount <= 0) {
    return "None";
  }
  const kind = formatAnomalyKind(record.latestAnomalyKind);
  const severity = record.latestAnomalySeverity
    ? ` · ${record.latestAnomalySeverity}`
    : "";
  const message = record.latestAnomalyMessage
    ? ` · ${record.latestAnomalyMessage}`
    : "";
  return `${kind}${severity}${message}`;
}

function formatAnomalyKind(value: string | null | undefined): string {
  if (!value) {
    return "Reported anomaly";
  }
  return value
    .split("-")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

function sortByLastSeen(
  left: VitalDBRecorderRecord,
  right: VitalDBRecorderRecord
): number {
  const leftTimestamp = timestamp(left.lastSeenAt);
  const rightTimestamp = timestamp(right.lastSeenAt);
  if (leftTimestamp === null && rightTimestamp === null) {
    return left.vrcode.localeCompare(right.vrcode);
  }
  if (leftTimestamp === null) {
    return 1;
  }
  if (rightTimestamp === null) {
    return -1;
  }
  return rightTimestamp - leftTimestamp;
}

function timestamp(value: string | null | undefined): number | null {
  if (!value) {
    return null;
  }
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? null : parsed;
}

function filterRecorders(
  recorders: VitalDBRecorderRecord[],
  searchText: string
): VitalDBRecorderRecord[] {
  const query = searchText.trim().toLowerCase();
  if (!query) {
    return recorders;
  }
  return recorders.filter((recorder) =>
    [
      recorder.vrcode,
      recorder.lastIP,
      recorder.version,
      recorder.bedID,
      recorder.bedName
    ]
      .filter(Boolean)
      .some((value) => value?.toLowerCase().includes(query))
  );
}

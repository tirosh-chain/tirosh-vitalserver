import { useMemo, useState } from "react";

import { useVitalDBRecorders } from "../../application/runtime-control/queries";
import type { VitalDBRecorderRecord } from "../../domain/runtime-control/contracts/runtimeControlTypes";
import {
  formatBoolean,
  formatRecorderStatus,
  recorderStatusTone
} from "../../domain/runtime-control/formatting/status";
import { formatLocalDateTime } from "../../domain/runtime-control/formatting/time";
import { DataTable } from "../../shared/ui/DataTable";
import { ErrorState } from "../../shared/ui/ErrorState";
import { KeyValueRows } from "../../shared/ui/KeyValueRows";
import { MetricStrip } from "../../shared/ui/MetricStrip";
import { Panel } from "../../shared/ui/Panel";
import { StatusBadge } from "../../shared/ui/StatusBadge";
import { RecorderActivityChart } from "./RecorderActivityChart";

export function RecordersPage() {
  const recordersQuery = useVitalDBRecorders();
  const allRecorders = useMemo(
    () => [...(recordersQuery.data?.recorders ?? [])].sort(sortByLastSeen),
    [recordersQuery.data?.recorders]
  );
  const [searchText, setSearchText] = useState("");
  const [showHistory, setShowHistory] = useState(false);
  const [selectedVrcode, setSelectedVrcode] = useState<string | null>(null);
  const visibleRecorders = showHistory
    ? allRecorders
    : allRecorders.filter((recorder) => recorder.presentInLatestObservation !== false);
  const recorders = filterRecorders(visibleRecorders, searchText);
  const selectedRecorder =
    recorders.find((recorder) => recorder.vrcode === selectedVrcode) ??
    recorders[0];

  const summary = {
    known: allRecorders.length,
    current: allRecorders.filter(
      (recorder) => recorder.presentInLatestObservation !== false
    ).length,
    online: visibleRecorders.filter((recorder) => recorder.status === "online").length,
    stale: visibleRecorders.filter((recorder) => recorder.status === "stale").length,
    anomalies: visibleRecorders.reduce(
      (total, recorder) => total + (recorder.currentAnomalyCount ?? 0),
      0
    )
  };

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
            { label: "Known recorders", value: summary.known },
            { label: "Current", value: summary.current },
            { label: "Online recorders", value: summary.online },
            { label: "Stale recorders", value: summary.stale },
            { label: "Recorder anomalies", value: summary.anomalies }
          ]}
        />

        {recordersQuery.isPending ? (
          <p className="empty-state">Loading VRecorders...</p>
        ) : recordersQuery.isError ? (
          <ErrorState
            title="VRecorder history is not available"
            error={recordersQuery.error}
          />
        ) : (
          <DataTable
            rows={recorders}
            getRowKey={(recorder) => recorder.vrcode ?? "unknown"}
            selectedKey={selectedRecorder?.vrcode}
            onSelectRow={(recorder) => setSelectedVrcode(recorder.vrcode ?? null)}
            emptyText="No VRecorders have been observed."
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
                render: (recorder) => recorder.lastIP ?? "Unknown"
              },
              {
                key: "bed",
                header: "Bed",
                render: (recorder) => recorder.bedName ?? recorder.bedID ?? "Unknown"
              },
              {
                key: "lastSeen",
                header: "Last seen",
                render: (recorder) => formatLocalDateTime(recorder.lastSeenAt)
              },
              {
                key: "anomaly",
                header: "Anomaly",
                render: (recorder) => recorder.currentAnomalyCount ?? 0
              }
            ]}
          />
        )}
      </Panel>

      {selectedRecorder ? <RecorderDetails recorder={selectedRecorder} /> : null}
    </div>
  );
}

function RecorderDetails({ recorder }: { recorder: VitalDBRecorderRecord }) {
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
          { label: "IP", value: recorder.lastIP ?? "Unknown" },
          { label: "Version", value: recorder.version ?? "Unknown" },
          { label: "Bed", value: recorder.bedName ?? recorder.bedID ?? "Unknown" },
          { label: "Patient", value: formatBoolean(recorder.patientConnected) },
          { label: "First seen", value: formatLocalDateTime(recorder.firstSeenAt) },
          { label: "Last seen", value: formatLocalDateTime(recorder.lastSeenAt) },
          { label: "Observations", value: recorder.observationCount ?? 0 },
          {
            label: "Recorder anomalies",
            value: recorder.currentAnomalyCount ?? 0
          }
        ]}
      />

      <div className="subsection">
        <h3>Activity</h3>
        <RecorderActivityChart recorder={recorder} />
      </div>
    </Panel>
  );
}

function sortByLastSeen(
  left: VitalDBRecorderRecord,
  right: VitalDBRecorderRecord
): number {
  return timestamp(right.lastSeenAt) - timestamp(left.lastSeenAt);
}

function timestamp(value: string | null | undefined): number {
  if (!value) {
    return 0;
  }
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? 0 : parsed;
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

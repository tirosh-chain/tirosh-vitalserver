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
  const recorders = useMemo(
    () => [...(recordersQuery.data?.recorders ?? [])].sort(sortByLastSeen),
    [recordersQuery.data?.recorders]
  );
  const [selectedVrcode, setSelectedVrcode] = useState<string | null>(null);
  const selectedRecorder =
    recorders.find((recorder) => recorder.vrcode === selectedVrcode) ??
    recorders[0];

  const summary = {
    known: recorders.length,
    online: recorders.filter((recorder) => recorder.status === "online").length,
    stale: recorders.filter((recorder) => recorder.status === "stale").length,
    anomalies: recorders.reduce(
      (total, recorder) => total + (recorder.currentAnomalyCount ?? 0),
      0
    )
  };

  return (
    <div className="page-stack">
      <Panel title="Recorders">
        <MetricStrip
          metrics={[
            { label: "Known recorders", value: summary.known },
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

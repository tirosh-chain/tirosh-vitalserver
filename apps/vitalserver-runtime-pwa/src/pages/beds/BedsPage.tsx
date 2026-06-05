import { useMemo, useState } from "react";

import { useVitalDBRecorders } from "@/console/hooks";
import type { VitalDBBedRecord } from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  formatBoolean,
  formatRecorderStatus,
  recorderStatusTone
} from "@/domain/runtime-control/formatting/status";
import { formatLocalDateTime } from "@/domain/runtime-control/formatting/time";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import { DataTable } from "@/components/DataTable";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { MetricStrip } from "@/components/MetricStrip";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";

export function BedsPage() {
  const recordersQuery = useVitalDBRecorders();
  const allBeds = useMemo(
    () =>
      recordersQuery.data === undefined
        ? null
        : [...recordersQuery.data.beds].sort(sortByLastSeen),
    [recordersQuery.data]
  );
  const [searchText, setSearchText] = useState("");
  const beds = allBeds === null ? null : filterBeds(allBeds, searchText);
  const [selectedBedID, setSelectedBedID] = useState<string | null>(null);
  const selectedBed =
    beds?.find((bed) => bed.bedID === selectedBedID) ??
    beds?.[0] ??
    null;

  const summary = recordersQuery.data?.summary ?? null;

  return (
    <div className="page-stack">
      <Panel
        title="Beds"
        actions={
          <div className="toolbar compact-toolbar">
            <input
              type="search"
              placeholder="Search beds"
              value={searchText}
              onChange={(event) => setSearchText(event.target.value)}
            />
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
            { label: "Known beds", value: summary?.knownBeds ?? NOT_REPORTED },
            { label: "Online beds", value: summary?.onlineBeds ?? NOT_REPORTED },
            { label: "Stale beds", value: summary?.staleBeds ?? NOT_REPORTED },
            {
              label: "Assignments",
              value: summary?.bedAssignments ?? NOT_REPORTED
            },
            { label: "Bed anomalies", value: summary?.bedAnomalies ?? NOT_REPORTED }
          ]}
        />

        {recordersQuery.isPending ? (
          <p className="empty-state">Loading beds...</p>
        ) : recordersQuery.isError ? (
          <ErrorState
            title="Bed history is not available"
            error={recordersQuery.error}
          />
        ) : beds === null ? (
          <ErrorState
            title="Bed history response is incomplete"
            error={
              new Error("Runtime Control API did not return bed history data.")
            }
          />
        ) : (
          <DataTable
            rows={beds}
            getRowKey={(bed) => bed.bedID}
            selectedKey={selectedBed?.bedID}
            onSelectRow={(bed) => setSelectedBedID(bed.bedID)}
            emptyText="No beds have been observed."
            columns={[
              {
                key: "bed",
                header: "Bed ID",
                render: (bed) => <strong>{shorten(bed.bedID)}</strong>
              },
              {
                key: "name",
                header: "Name",
                render: (bed) => bed.name ?? NOT_REPORTED
              },
              {
                key: "vrcode",
                header: "VRecorder",
                render: (bed) => bed.vrcode ?? NOT_REPORTED
              },
              {
                key: "status",
                header: "Status",
                render: (bed) => (
                  <StatusBadge tone={recorderStatusTone(bed.status)}>
                    {formatRecorderStatus(bed.status)}
                  </StatusBadge>
                )
              },
              {
                key: "lastSeen",
                header: "Last seen",
                render: (bed) => formatLocalDateTime(bed.lastSeenAt)
              },
              {
                key: "anomaly",
                header: "Anomaly",
                render: (bed) => bed.currentAnomalyCount
              }
            ]}
          />
        )}
      </Panel>

      {selectedBed ? <BedDetails bed={selectedBed} /> : null}
    </div>
  );
}

function BedDetails({ bed }: { bed: VitalDBBedRecord }) {
  return (
    <Panel title="Bed Details">
      <div className="detail-heading">
        <StatusBadge tone={recorderStatusTone(bed.status)}>
          <strong>{bed.name ?? bed.bedID}</strong>
          {formatRecorderStatus(bed.status)}
        </StatusBadge>
        <span>{formatLocalDateTime(bed.lastSeenAt)}</span>
      </div>

      <KeyValueRows
        rows={[
          { label: "Bed ID", value: bed.bedID },
          { label: "Name", value: bed.name ?? NOT_REPORTED },
          { label: "VRecorder", value: bed.vrcode ?? NOT_REPORTED },
          { label: "Patient", value: formatBoolean(bed.patientConnected) },
          { label: "First seen", value: formatLocalDateTime(bed.firstSeenAt) },
          { label: "Last seen", value: formatLocalDateTime(bed.lastSeenAt) },
          { label: "Observations", value: bed.observationCount },
          { label: "Duplicate observations", value: bed.duplicateObservationCount },
          { label: "Bed anomalies", value: bed.currentAnomalyCount }
        ]}
      />
    </Panel>
  );
}

function shorten(value: string): string {
  if (value.length <= 18) {
    return value;
  }
  return `${value.slice(0, 10)}...${value.slice(-8)}`;
}

function sortByLastSeen(left: VitalDBBedRecord, right: VitalDBBedRecord): number {
  const leftTimestamp = timestamp(left.lastSeenAt);
  const rightTimestamp = timestamp(right.lastSeenAt);
  if (leftTimestamp === null && rightTimestamp === null) {
    return left.bedID.localeCompare(right.bedID);
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

function filterBeds(beds: VitalDBBedRecord[], searchText: string): VitalDBBedRecord[] {
  const query = searchText.trim().toLowerCase();
  if (!query) {
    return beds;
  }
  return beds.filter((bed) =>
    [bed.bedID, bed.name, bed.vrcode]
      .filter(Boolean)
      .some((value) => value?.toLowerCase().includes(query))
  );
}

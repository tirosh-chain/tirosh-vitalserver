import { useMemo, useState } from "react";

import { useVitalDBBeds } from "@/console/hooks";
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
  const bedsQuery = useVitalDBBeds();
  const allBeds = useMemo(
    () => (bedsQuery.data ? [...bedsQuery.data].sort(sortByLastSeen) : null),
    [bedsQuery.data]
  );
  const [searchText, setSearchText] = useState("");
  const beds = filterBeds(allBeds ?? [], searchText);
  const identifiedBeds = beds.filter(hasBedID);
  const [selectedBedID, setSelectedBedID] = useState<string | null>(null);
  const selectedBed =
    identifiedBeds.find((bed) => bed.bedID === selectedBedID) ??
    identifiedBeds[0];

  const summary = allBeds
    ? {
        known: allBeds.length,
        online: allBeds.filter((bed) => bed.status === "online").length,
        stale: allBeds.filter((bed) => bed.status === "stale").length,
        assignments: allBeds.filter((bed) => Boolean(bed.vrcode)).length,
        anomalies: allBeds.reduce(
          (total, bed) => total + (bed.currentAnomalyCount ?? 0),
          0
        )
      }
    : null;

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
              disabled={bedsQuery.isFetching}
              onClick={() => bedsQuery.refetch()}
            >
              Refresh
            </button>
          </div>
        }
      >
        <MetricStrip
          metrics={[
            { label: "Known beds", value: summary?.known ?? NOT_REPORTED },
            { label: "Online beds", value: summary?.online ?? NOT_REPORTED },
            { label: "Stale beds", value: summary?.stale ?? NOT_REPORTED },
            { label: "Assignments", value: summary?.assignments ?? NOT_REPORTED },
            { label: "Bed anomalies", value: summary?.anomalies ?? NOT_REPORTED }
          ]}
        />

        {bedsQuery.isPending ? (
          <p className="empty-state">Loading beds...</p>
        ) : bedsQuery.isError ? (
          <ErrorState
            title="Bed history is not available"
            error={bedsQuery.error}
          />
        ) : (
          <DataTable
            rows={identifiedBeds}
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
                render: (bed) => bed.name ?? "Unknown"
              },
              {
                key: "vrcode",
                header: "VRecorder",
                render: (bed) => bed.vrcode ?? "Unknown"
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
                render: (bed) => bed.currentAnomalyCount ?? 0
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
          { label: "Name", value: bed.name ?? "Unknown" },
          { label: "VRecorder", value: bed.vrcode ?? "Unknown" },
          { label: "Patient", value: formatBoolean(bed.patientConnected) },
          { label: "First seen", value: formatLocalDateTime(bed.firstSeenAt) },
          { label: "Last seen", value: formatLocalDateTime(bed.lastSeenAt) },
          { label: "Observations", value: bed.observationCount ?? 0 },
          { label: "Bed anomalies", value: bed.currentAnomalyCount ?? 0 }
        ]}
      />
    </Panel>
  );
}

function hasBedID(bed: VitalDBBedRecord): bed is VitalDBBedRecord & { bedID: string } {
  return typeof bed.bedID === "string" && bed.bedID.length > 0;
}

function shorten(value: string | undefined): string {
  if (!value) {
    return "Unknown";
  }
  if (value.length <= 18) {
    return value;
  }
  return `${value.slice(0, 10)}...${value.slice(-8)}`;
}

function sortByLastSeen(left: VitalDBBedRecord, right: VitalDBBedRecord): number {
  return timestamp(right.lastSeenAt) - timestamp(left.lastSeenAt);
}

function timestamp(value: string | null | undefined): number {
  if (!value) {
    return 0;
  }
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? 0 : parsed;
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

import { useMemo, useState } from "react";

import {
  useDeleteVitalDBBeds,
  useHideVitalDBBeds,
  useUnhideVitalDBBeds,
  useVitalDBRecorders,
  useVitalDBRelationships
} from "@/console/hooks";
import type {
  VitalDBBedRecord,
  VitalDBRelationships
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  formatPatientStatus,
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
import { RelationshipHistory } from "@/pages/relationships/RelationshipHistory";

export function BedsPage() {
  const recordersQuery = useVitalDBRecorders();
  const relationshipsQuery = useVitalDBRelationships();
  const allBeds = useMemo(
    () =>
      recordersQuery.data === undefined
        ? null
        : [...recordersQuery.data.beds].sort(sortByLastSeen),
    [recordersQuery.data]
  );
  const [searchText, setSearchText] = useState("");
  const [showHidden, setShowHidden] = useState(false);
  const hideBeds = useHideVitalDBBeds();
  const unhideBeds = useUnhideVitalDBBeds();
  const deleteBeds = useDeleteVitalDBBeds();
  const visibleBeds =
    allBeds === null
      ? null
      : allBeds.filter((bed) => showHidden || bed.visibility !== "hidden");
  const beds = visibleBeds === null ? null : filterBeds(visibleBeds, searchText);
  const visibilityMutationPending =
    hideBeds.isPending || unhideBeds.isPending || deleteBeds.isPending;
  const visibilityMutationError =
    hideBeds.error ?? unhideBeds.error ?? deleteBeds.error;
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
            <label className="checkbox-label">
              <input
                type="checkbox"
                checked={showHidden}
                onChange={(event) => setShowHidden(event.target.checked)}
              />
              Show hidden
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
            { label: "Known beds", value: summary?.knownBeds ?? NOT_REPORTED },
            { label: "Online beds", value: summary?.onlineBeds ?? NOT_REPORTED },
            { label: "Stale beds", value: summary?.staleBeds ?? NOT_REPORTED },
            {
              label: "Assignments",
              value: summary?.bedAssignments ?? NOT_REPORTED
            },
            { label: "Bed anomalies", value: summary?.bedAnomalies ?? NOT_REPORTED },
            {
              label: "Data updated",
              value: formatLocalDateTime(recordersQuery.data?.updatedAt)
            }
          ]}
        />

        {visibilityMutationError ? (
          <p className="form-error">{mutationErrorMessage(visibilityMutationError)}</p>
        ) : null}

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
            emptyText="No beds found."
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
                render: (bed) => formatLocalDateTimeWithAge(bed.lastSeenAt)
              },
              {
                key: "visibility",
                header: "Visibility",
                render: (bed) => formatVisibility(bed.visibility)
              },
              {
                key: "anomaly",
                header: "Anomaly",
                render: (bed) => formatAnomalySummary(bed)
              },
              {
                key: "actions",
                header: "Actions",
                render: (bed) => (
                  <div className="toolbar compact-toolbar">
                    {bed.visibility === "hidden" ? (
                      <>
                        <button
                          type="button"
                          disabled={visibilityMutationPending}
                          onClick={() => unhideBeds.mutate({ bedIDs: [bed.bedID] })}
                        >
                          Unhide
                        </button>
                        {showHidden ? (
                          <button
                            type="button"
                            disabled={visibilityMutationPending}
                            onClick={() => {
                              if (window.confirm(`Delete hidden bed ${bed.bedID}?`)) {
                                deleteBeds.mutate({ bedIDs: [bed.bedID] });
                              }
                            }}
                          >
                            Delete
                          </button>
                        ) : null}
                      </>
                    ) : (
                      <button
                        type="button"
                        disabled={visibilityMutationPending}
                        onClick={() => hideBeds.mutate({ bedIDs: [bed.bedID] })}
                      >
                        Hide
                      </button>
                    )}
                  </div>
                )
              }
            ]}
          />
        )}
      </Panel>

      {selectedBed ? (
        <BedDetails
          bed={selectedBed}
          relationships={relationshipsQuery.data}
          relationshipsError={relationshipsQuery.error}
        />
      ) : null}
    </div>
  );
}

function BedDetails({
  bed,
  relationships,
  relationshipsError
}: {
  bed: VitalDBBedRecord;
  relationships: VitalDBRelationships | undefined;
  relationshipsError: unknown;
}) {
  const assignments = (relationships?.assignments ?? []).filter(
    (assignment) => assignment.bedID === bed.bedID
  );
  const events = (relationships?.events ?? []).filter(
    (event) => event.bedID === bed.bedID
  );

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
          {
            label: "VRecorder status",
            value: bed.linkedRecorderStatus ? (
              <StatusBadge tone={recorderStatusTone(bed.linkedRecorderStatus)}>
                {formatRecorderStatus(bed.linkedRecorderStatus)}
              </StatusBadge>
            ) : (
              NOT_REPORTED
            )
          },
          { label: "VRecorder IP", value: bed.linkedRecorderIP ?? NOT_REPORTED },
          {
            label: "VRecorder last seen",
            value: formatLocalDateTimeWithAge(bed.linkedRecorderLastSeenAt)
          },
          {
            label: "Patient status",
            value: formatPatientStatus(bed.patientConnected)
          },
          { label: "First seen", value: formatLocalDateTime(bed.firstSeenAt) },
          { label: "Last seen", value: formatLocalDateTimeWithAge(bed.lastSeenAt) },
          { label: "Latest anomaly", value: formatAnomalySummary(bed) }
        ]}
      />

      <RelationshipHistory
        title="bed"
        relationships={relationships}
        relationshipsError={relationshipsError}
        assignments={assignments}
        events={events}
      />
    </Panel>
  );
}

function formatAnomalySummary(
  record: Pick<
    VitalDBBedRecord,
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

function formatVisibility(value: VitalDBBedRecord["visibility"]): string {
  return value === "hidden" ? "Hidden" : "Visible";
}

function mutationErrorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
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

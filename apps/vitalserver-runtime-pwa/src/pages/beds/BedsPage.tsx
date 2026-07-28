import { useMemo, useState } from "react";

import {
  useDeleteVitalDBBeds,
  useHideVitalDBBeds,
  useLabBeds,
  useUnhideVitalDBBeds,
  useVitalDBBeds,
  useVitalDBRelationships
} from "@/console/hooks";
import type {
  RuntimeLabBed,
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
  const bedsQuery = useVitalDBBeds();
  const relationshipsQuery = useVitalDBRelationships();
  const labBedsQuery = useLabBeds();
  const allBeds = useMemo(
    () =>
      bedsQuery.data === undefined
        ? null
        : [...bedsQuery.data.beds].sort(sortByLastSeen),
    [bedsQuery.data]
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

  const summary = bedsQuery.data?.summary ?? null;

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
            { label: "Beds observed", value: summary?.knownBeds ?? NOT_REPORTED },
            { label: "Online beds", value: summary?.onlineBeds ?? NOT_REPORTED },
            { label: "Stale beds", value: summary?.staleBeds ?? NOT_REPORTED },
            { label: "Data issues", value: summary?.bedAnomalies ?? NOT_REPORTED },
            {
              label: "Data updated",
              value: formatLocalDateTime(bedsQuery.data?.updatedAt)
            }
          ]}
        />

        {visibilityMutationError ? (
          <p className="form-error">{mutationErrorMessage(visibilityMutationError)}</p>
        ) : null}

        {bedsQuery.isPending ? (
          <p className="empty-state">Loading beds...</p>
        ) : bedsQuery.isError ? (
          <ErrorState
            title="Bed history is not available"
            error={bedsQuery.error}
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
            emptyText="No VitalDB bed observations found."
            cardTitleColumnKey="bed"
            columns={[
              {
                key: "status",
                header: "Bed status",
                render: (bed) => (
                  <StatusBadge tone={recorderStatusTone(bed.status)}>
                    {formatRecorderStatus(bed.status)}
                  </StatusBadge>
                )
              },
              {
                key: "bed",
                header: "Bed",
                render: (bed) => (
                  <span className="bed-identity">
                    <strong>{bed.name ?? NOT_REPORTED}</strong>
                    <span className="muted">{shorten(bed.bedID)}</span>
                  </span>
                )
              },
              {
                key: "patient",
                header: "Patient presence",
                render: (bed) => formatPatientStatus(bed.patientConnected)
              },
              {
                key: "lastSeen",
                header: "Last observation",
                render: (bed) => formatLocalDateTimeWithAge(bed.lastSeenAt)
              },
              {
                key: "anomaly",
                header: "Data issue",
                render: (bed) => formatAnomalySummary(bed)
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
          visibilityMutationPending={visibilityMutationPending}
          onHide={() => hideBeds.mutate({ bedIDs: [selectedBed.bedID] })}
          onUnhide={() => unhideBeds.mutate({ bedIDs: [selectedBed.bedID] })}
          onDelete={() => {
            if (window.confirm(`Delete hidden bed ${selectedBed.bedID}?`)) {
              deleteBeds.mutate({ bedIDs: [selectedBed.bedID] });
            }
          }}
        />
      ) : null}

      <LabBedsPanel
        beds={labBedsQuery.data?.beds ?? []}
        state={labBedsQuery.data?.state}
        readError={labBedsQuery.data?.readError ?? null}
        isPending={labBedsQuery.isPending}
        isError={labBedsQuery.isError}
        error={labBedsQuery.error}
        isFetching={labBedsQuery.isFetching}
        onRefresh={() => labBedsQuery.refetch()}
      />
    </div>
  );
}

function LabBedsPanel({
  beds,
  state,
  readError,
  isPending,
  isError,
  error,
  isFetching,
  onRefresh
}: {
  beds: RuntimeLabBed[];
  state: string | undefined;
  readError: string | null;
  isPending: boolean;
  isError: boolean;
  error: unknown;
  isFetching: boolean;
  onRefresh: () => void;
}) {
  const [selectedBedID, setSelectedBedID] = useState<string | null>(null);
  const selectedBed =
    beds.find((bed) => bed.bedId === selectedBedID) ?? beds[0] ?? null;

  return (
    <>
      <Panel
        title="Product Lab beds"
        actions={
          <button type="button" disabled={isFetching} onClick={onRefresh}>
            Refresh
          </button>
        }
      >
        <MetricStrip
          metrics={[
            { label: "Lab beds", value: beds.length },
            { label: "Read state", value: state ?? NOT_REPORTED },
            { label: "Read error", value: readError ?? "-" }
          ]}
        />
        {isPending ? (
          <p className="empty-state">Loading Product Lab beds...</p>
        ) : isError ? (
          <ErrorState title="Product Lab beds are not available" error={error} />
        ) : (
          <DataTable
            rows={beds}
            getRowKey={(bed) => bed.bedId}
            selectedKey={selectedBed?.bedId}
            onSelectRow={(bed) => setSelectedBedID(bed.bedId)}
            emptyText="No Product Lab beds found."
            columns={[
              {
                key: "name",
                header: "Name",
                render: (bed) => <strong>{bed.name}</strong>
              },
              {
                key: "bedId",
                header: "Bed ID",
                render: (bed) => bed.bedId
              },
              {
                key: "session",
                header: "Session",
                render: (bed) => bed.sessionId
              },
              {
                key: "state",
                header: "State",
                render: (bed) => (
                  <StatusBadge tone={labStateTone(bed.state)}>
                    {bed.state}
                  </StatusBadge>
                )
              },
              {
                key: "updated",
                header: "Updated",
                render: (bed) => formatLocalDateTime(bed.updatedAt)
              }
            ]}
          />
        )}
      </Panel>

      {selectedBed ? <ProductLabBedDetails bed={selectedBed} /> : null}
    </>
  );
}

function ProductLabBedDetails({ bed }: { bed: RuntimeLabBed }) {
  return (
    <Panel title="Product Lab Bed Details">
      <div className="detail-heading">
        <StatusBadge tone={labStateTone(bed.state)}>
          <strong>{bed.name}</strong>
          {bed.state}
        </StatusBadge>
        <span>{formatLocalDateTime(bed.updatedAt)}</span>
      </div>

      <KeyValueRows
        rows={[
          { label: "Name", value: bed.name },
          { label: "Bed ID", value: bed.bedId },
          { label: "Session", value: bed.sessionId },
          {
            label: "State",
            value: (
              <StatusBadge tone={labStateTone(bed.state)}>
                {bed.state}
              </StatusBadge>
            )
          },
          { label: "Created", value: formatLocalDateTime(bed.createdAt) },
          { label: "Updated", value: formatLocalDateTime(bed.updatedAt) }
        ]}
      />
    </Panel>
  );
}

function BedDetails({
  bed,
  relationships,
  relationshipsError,
  visibilityMutationPending,
  onHide,
  onUnhide,
  onDelete
}: {
  bed: VitalDBBedRecord;
  relationships: VitalDBRelationships | undefined;
  relationshipsError: unknown;
  visibilityMutationPending: boolean;
  onHide: () => void;
  onUnhide: () => void;
  onDelete: () => void;
}) {
  const assignments = (relationships?.assignments ?? []).filter(
    (assignment) => assignment.bedID === bed.bedID
  );
  const events = (relationships?.events ?? []).filter(
    (event) => event.bedID === bed.bedID
  );

  return (
    <Panel
      title="Bed Details"
      actions={
        <div className="toolbar compact-toolbar">
          {bed.visibility === "hidden" ? (
            <>
              <button
                type="button"
                disabled={visibilityMutationPending}
                onClick={onUnhide}
              >
                Show in list
              </button>
              <button
                type="button"
                disabled={visibilityMutationPending}
                onClick={onDelete}
              >
                Delete hidden bed
              </button>
            </>
          ) : (
            <button
              type="button"
              disabled={visibilityMutationPending}
              onClick={onHide}
            >
              Hide from list
            </button>
          )}
        </div>
      }
    >
      <div className="detail-heading">
        <StatusBadge tone={recorderStatusTone(bed.status)}>
          <strong>{bed.name ?? bed.bedID}</strong>
          {formatRecorderStatus(bed.status)}
        </StatusBadge>
        <span>{formatLocalDateTime(bed.lastSeenAt)}</span>
      </div>

      <KeyValueRows
        rows={[
          {
            label: "Patient presence",
            value: formatPatientStatus(bed.patientConnected)
          },
          {
            label: "Bed status",
            value: (
              <StatusBadge tone={recorderStatusTone(bed.status)}>
                {formatRecorderStatus(bed.status)}
              </StatusBadge>
            )
          },
          {
            label: "Last observation",
            value: formatLocalDateTimeWithAge(bed.lastSeenAt)
          },
          { label: "First observed", value: formatLocalDateTime(bed.firstSeenAt) },
          { label: "Data issue", value: formatAnomalySummary(bed) },
          { label: "Bed ID", value: bed.bedID },
          { label: "List visibility", value: formatVisibility(bed.visibility) }
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

function labStateTone(state: string): "success" | "warning" | "danger" | "neutral" {
  switch (state) {
    case "running":
      return "success";
    case "accepted":
    case "stopped":
      return "warning";
    case "failed":
      return "danger";
    default:
      return "neutral";
  }
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
    [bed.bedID, bed.name]
      .filter(Boolean)
      .some((value) => value?.toLowerCase().includes(query))
  );
}

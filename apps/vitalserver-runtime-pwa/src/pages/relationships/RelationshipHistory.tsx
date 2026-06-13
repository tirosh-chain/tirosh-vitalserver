import type {
  VitalDBRelationshipAssignment,
  VitalDBRelationshipEvent,
  VitalDBRelationships
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { formatLocalDateTime } from "@/domain/runtime-control/formatting/time";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";

type RelationshipHistoryProps = {
  title: "recorder" | "bed";
  relationships: VitalDBRelationships | undefined;
  relationshipsError: unknown;
  assignments: VitalDBRelationshipAssignment[];
  events: VitalDBRelationshipEvent[];
};

export function RelationshipHistory({
  title,
  relationships,
  relationshipsError,
  assignments,
  events
}: RelationshipHistoryProps) {
  const readError = relationshipReadError(relationships, relationshipsError);
  const visibleAssignments = assignments.slice(0, 8);
  const visibleEvents = events.slice(0, 8);
  const loadedWithoutHistory =
    relationships?.state === "loaded" &&
    visibleAssignments.length === 0 &&
    visibleEvents.length === 0;

  return (
    <div className="subsection">
      <h3>Relationship history</h3>
      {readError ? (
        <p className="form-error">Relationship history read issue: {readError}</p>
      ) : null}
      {loadedWithoutHistory ? (
        <p className="empty-state">
          No {title} relationship history has been observed.
        </p>
      ) : relationships?.state !== "readFailed" ? (
        <>
          {visibleAssignments.length > 0 ? (
            <RelationshipList
              title="Assignments"
              rows={visibleAssignments.map((assignment) => ({
                id: assignment.assignmentID,
                title:
                  title === "recorder"
                    ? assignment.bedName ?? assignment.bedID
                    : assignment.vrcode,
                detail: `${formatLocalDateTime(assignment.startedAt)} - ${formatLocalDateTime(
                  assignment.endedAt
                )}`,
                trailing: formatRelationshipStatus(assignment.status)
              }))}
            />
          ) : null}
          {visibleEvents.length > 0 ? (
            <RelationshipList
              title="Events"
              rows={visibleEvents.map((event) => ({
                id: event.eventID,
                title: `${formatRelationshipSeverity(event.severity)} · ${formatRelationshipEventType(
                  event.eventType
                )}`,
                detail: event.message,
                trailing: formatLocalDateTime(event.observedAt)
              }))}
            />
          ) : null}
        </>
      ) : null}
    </div>
  );
}

function RelationshipList({
  title,
  rows
}: {
  title: string;
  rows: Array<{ id: string; title: string; detail: string; trailing: string }>;
}) {
  return (
    <div className="relationship-list">
      <h4>{title}</h4>
      <div className="relationship-rows">
        {rows.map((row) => (
          <div className="relationship-row" key={row.id}>
            <strong>{row.title || NOT_REPORTED}</strong>
            <span>{row.detail}</span>
            <span>{row.trailing}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function relationshipReadError(
  relationships: VitalDBRelationships | undefined,
  relationshipsError: unknown
): string | null {
  if (relationships?.readError) {
    return relationships.readError;
  }
  if (relationshipsError instanceof Error) {
    return relationshipsError.message;
  }
  return null;
}

function formatRelationshipStatus(value: string | null | undefined): string {
  return formatWords(value) || "Unknown";
}

function formatRelationshipSeverity(value: string | null | undefined): string {
  return formatWords(value) || "Unknown";
}

function formatRelationshipEventType(value: string | null | undefined): string {
  return formatWords(value) || "relationship event";
}

function formatWords(value: string | null | undefined): string {
  if (!value) {
    return "";
  }
  return value
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

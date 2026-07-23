import { useMemo, useState } from "react";

import {
  useDeleteVitalDBRecorders,
  useHideVitalDBRecorders,
  useLabRecorders,
  useRecorderObservabilityDetail,
  useRecorderObservabilityIncidents,
  useRecorderObservabilityTimeline,
  useUnhideVitalDBRecorders,
  useVitalDBRecorderVitalFiles,
  useVitalDBRecorders,
  useVitalDBRelationships
} from "@/console/hooks";
import type {
  RuntimeLabRecorder,
  RuntimeRecorderObservabilityDetail,
  RuntimeRecorderObservabilityIncidents,
  RuntimeRecorderObservabilityTimeline,
  VitalDBRecorderRecord,
  RuntimeVitalRecorderVitalFileHistory,
  VitalDBRelationships
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  formatPatientStatus,
  formatRecorderStatus,
  recorderStatusTone
} from "@/domain/runtime-control/formatting/status";
import {
  formatLocalDateTime,
  formatRelativeAge
} from "@/domain/runtime-control/formatting/time";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import { formatBytes } from "@/domain/runtime-control/formatting/bytes";
import { DataTable } from "@/components/DataTable";
import { Button } from "@/components/Button";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { MetricStrip } from "@/components/MetricStrip";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";
import { RecorderActivityChart } from "./RecorderActivityChart";
import { RelationshipHistory } from "@/pages/relationships/RelationshipHistory";

type RecorderVisibilityNotice = {
  message: string;
  undoVrcode: string | null;
};

export function RecordersPage() {
  const recordersQuery = useVitalDBRecorders();
  const relationshipsQuery = useVitalDBRelationships();
  const labRecordersQuery = useLabRecorders();
  const allRecorders = useMemo(
    () =>
      recordersQuery.data === undefined
        ? null
        : [...recordersQuery.data.recorders].sort(sortByLastSeen),
    [recordersQuery.data]
  );
  const [searchText, setSearchText] = useState("");
  const [showHistory, setShowHistory] = useState(false);
  const [showHidden, setShowHidden] = useState(false);
  const [selectedVrcode, setSelectedVrcode] = useState<string | null>(null);
  const [selectedLabRecorderID, setSelectedLabRecorderID] = useState<string | null>(null);
  const [visibilityNotice, setVisibilityNotice] =
    useState<RecorderVisibilityNotice | null>(null);
  const hideRecorders = useHideVitalDBRecorders();
  const unhideRecorders = useUnhideVitalDBRecorders();
  const deleteRecorders = useDeleteVitalDBRecorders();
  const visibleRecorders = allRecorders === null
    ? null
    : allRecorders.filter((recorder) => {
        if (!showHistory && recorder.presentInLatestObservation !== true) {
          return false;
        }
        if (!showHidden && recorder.visibility === "hidden") {
          return false;
        }
        return true;
      });
  const recorders = visibleRecorders === null
    ? null
    : filterRecorders(visibleRecorders, searchText);
  const visibilityMutationPending =
    hideRecorders.isPending ||
    unhideRecorders.isPending ||
    deleteRecorders.isPending;
  const visibilityMutationError =
    hideRecorders.error ?? unhideRecorders.error ?? deleteRecorders.error;
  const selectedRecorder = selectedLabRecorderID === null
    ? recorders?.find((recorder) => recorder.vrcode === selectedVrcode) ?? null
    : null;
  const recorderVitalFilesQuery = useVitalDBRecorderVitalFiles(
    selectedRecorder?.vrcode ?? null
  );
  const recorderObservabilityQuery = useRecorderObservabilityDetail(
    selectedRecorder?.vrcode ?? null
  );
  const observabilityHistoryWindow = useMemo(() => {
    if (selectedRecorder === null) {
      return null;
    }
    const until = new Date();
    until.setSeconds(0, 0);
    return {
      vrcode: selectedRecorder.vrcode,
      from: new Date(until.getTime() - 24 * 60 * 60 * 1_000).toISOString(),
      until: until.toISOString()
    };
  }, [selectedRecorder?.vrcode]);
  const recorderObservabilityTimelineQuery = useRecorderObservabilityTimeline(
    observabilityHistoryWindow === null
      ? null
      : { ...observabilityHistoryWindow, bucketSeconds: 900 }
  );
  const recorderObservabilityIncidentsQuery = useRecorderObservabilityIncidents(
    observabilityHistoryWindow === null
      ? null
      : { ...observabilityHistoryWindow, limit: 20 }
  );
  const selectedLabRecorder =
    labRecordersQuery.data?.recorders.find(
      (recorder) => recorder.recorderId === selectedLabRecorderID
    ) ?? null;
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
          className="recorder-metrics"
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

        {visibilityMutationError ? (
          <p className="form-error">{mutationErrorMessage(visibilityMutationError)}</p>
        ) : null}

        {visibilityNotice ? (
          <div className="recorder-visibility-notice" role="status" aria-live="polite">
            <span>{visibilityNotice.message}</span>
            {visibilityNotice.undoVrcode ? (
              <button
                type="button"
                disabled={visibilityMutationPending}
                onClick={() => {
                  const vrcode = visibilityNotice.undoVrcode;
                  if (!vrcode) {
                    return;
                  }
                  unhideRecorders.mutate(
                    { vrcodes: [vrcode] },
                    {
                      onSuccess: () => {
                        setSelectedVrcode(vrcode);
                        setVisibilityNotice({
                          message: `${vrcode} shown in recorder list.`,
                          undoVrcode: null
                        });
                      }
                    }
                  );
                }}
              >
                Undo
              </button>
            ) : null}
          </div>
        ) : null}

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
          <div className="recorder-table">
            <DataTable
              rows={recorders}
              getRowKey={(recorder) => recorder.vrcode}
              selectedKey={selectedRecorder?.vrcode}
              onSelectRow={(recorder) => {
                setSelectedVrcode(recorder.vrcode);
                setSelectedLabRecorderID(null);
              }}
              emptyText="No VitalDB VRecorder observations found."
              cardTitleColumnKey="vrcode"
              columns={[
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
                  key: "vrcode",
                  header: "VRecorder",
                  render: (recorder) => (
                    <span className="recorder-identity">
                      <strong>{recorder.vrcode}</strong>
                      {recorder.visibility === "hidden" ? (
                        <span className="visibility-badge">Hidden</span>
                      ) : null}
                    </span>
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
                  render: (recorder) => formatRelativeAge(recorder.lastSeenAt)
                },
                {
                  key: "healthReport",
                  header: "Health report",
                  render: (recorder) => (
                    <StatusBadge tone={observabilityTone(recorder.observability)}>
                      {formatObservabilityReport(recorder.observability)}
                    </StatusBadge>
                  )
                },
                {
                  key: "anomaly",
                  header: "Anomaly",
                  render: (recorder) => formatAnomalySummary(recorder)
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
                }
              ]}
            />
          </div>
        )}
      </Panel>

      {selectedRecorder && recordersQuery.data ? (
        <RecorderDetails
          recorder={selectedRecorder}
          relationships={relationshipsQuery.data}
          relationshipsError={relationshipsQuery.error}
          vitalFiles={recorderVitalFilesQuery.data}
          vitalFilesError={recorderVitalFilesQuery.error}
          vitalFilesLoading={recorderVitalFilesQuery.isPending}
          observabilityDetail={recorderObservabilityQuery.data}
          observabilityDetailError={recorderObservabilityQuery.error}
          observabilityDetailLoading={recorderObservabilityQuery.isPending}
          observabilityTimeline={recorderObservabilityTimelineQuery.data}
          observabilityTimelineError={recorderObservabilityTimelineQuery.error}
          observabilityTimelineLoading={recorderObservabilityTimelineQuery.isPending}
          observabilityIncidents={recorderObservabilityIncidentsQuery.data}
          observabilityIncidentsError={recorderObservabilityIncidentsQuery.error}
          observabilityIncidentsLoading={recorderObservabilityIncidentsQuery.isPending}
          showDelete={showHidden}
          mutationPending={visibilityMutationPending}
          onHide={() => {
            const vrcode = selectedRecorder.vrcode;
            setVisibilityNotice(null);
            hideRecorders.mutate(
              { vrcodes: [vrcode] },
              {
                onSuccess: () => {
                  setSelectedVrcode(null);
                  setVisibilityNotice({
                    message: `${vrcode} hidden from recorder list.`,
                    undoVrcode: vrcode
                  });
                }
              }
            );
          }}
          onUnhide={() => {
            const vrcode = selectedRecorder.vrcode;
            setVisibilityNotice(null);
            unhideRecorders.mutate(
              { vrcodes: [vrcode] },
              {
                onSuccess: () => {
                  setVisibilityNotice({
                    message: `${vrcode} shown in recorder list.`,
                    undoVrcode: null
                  });
                }
              }
            );
          }}
          onDelete={() => {
            const vrcode = selectedRecorder.vrcode;
            setVisibilityNotice(null);
            deleteRecorders.mutate(
              { vrcodes: [vrcode] },
              {
                onSuccess: () => {
                  setSelectedVrcode(null);
                  setVisibilityNotice({
                    message: `${vrcode} deleted from recorder history.`,
                    undoVrcode: null
                  });
                }
              }
            );
          }}
        />
      ) : null}

      {selectedLabRecorder ? (
        <LabRecorderDetails recorder={selectedLabRecorder} />
      ) : null}

      <LabRecordersPanel
        recorders={labRecordersQuery.data?.recorders ?? []}
        state={labRecordersQuery.data?.state}
        readError={labRecordersQuery.data?.readError ?? null}
        isPending={labRecordersQuery.isPending}
        isError={labRecordersQuery.isError}
        error={labRecordersQuery.error}
        isFetching={labRecordersQuery.isFetching}
        onRefresh={() => labRecordersQuery.refetch()}
        selectedRecorderID={selectedLabRecorderID}
        onSelect={(recorder) => {
          setSelectedLabRecorderID(recorder.recorderId);
          setSelectedVrcode(null);
        }}
      />
    </div>
  );
}

function LabRecordersPanel({
  recorders,
  state,
  readError,
  isPending,
  isError,
  error,
  isFetching,
  onRefresh,
  selectedRecorderID,
  onSelect
}: {
  recorders: RuntimeLabRecorder[];
  state: string | undefined;
  readError: string | null;
  isPending: boolean;
  isError: boolean;
  error: unknown;
  isFetching: boolean;
  onRefresh: () => void;
  selectedRecorderID: string | null;
  onSelect: (recorder: RuntimeLabRecorder) => void;
}) {
  return (
    <Panel
      title="Product Lab recorders"
      actions={
        <button type="button" disabled={isFetching} onClick={onRefresh}>
          Refresh
        </button>
      }
    >
      <MetricStrip
        metrics={[
          { label: "Lab recorders", value: recorders.length },
          { label: "Read state", value: state ?? NOT_REPORTED },
          { label: "Read error", value: readError ?? "-" }
        ]}
      />
      {isPending ? (
        <p className="empty-state">Loading Product Lab recorders...</p>
      ) : isError ? (
        <ErrorState title="Product Lab recorders are not available" error={error} />
      ) : (
        <DataTable
          rows={recorders}
          getRowKey={(recorder) => recorder.recorderId}
          selectedKey={selectedRecorderID ?? undefined}
          onSelectRow={onSelect}
          emptyText="No Product Lab recorders found."
          columns={[
            {
              key: "vrcode",
              header: "VRecorder",
              render: (recorder) => <strong>{recorder.vrcode}</strong>
            },
            {
              key: "recorderId",
              header: "Recorder ID",
              render: (recorder) => recorder.recorderId
            },
            {
              key: "bed",
              header: "Bed",
              render: (recorder) => recorder.bedId
            },
            {
              key: "session",
              header: "Session",
              render: (recorder) => recorder.sessionId
            },
            {
              key: "state",
              header: "State",
              render: (recorder) => (
                <StatusBadge tone={labStateTone(recorder.state)}>
                  {recorder.state}
                </StatusBadge>
              )
            },
            {
              key: "send",
              header: "Send",
              render: (recorder) => recorder.lastSendState
            },
            {
              key: "updated",
              header: "Updated",
              render: (recorder) => formatLocalDateTime(recorder.updatedAt)
            }
          ]}
        />
      )}
    </Panel>
  );
}

function LabRecorderDetails({ recorder }: { recorder: RuntimeLabRecorder }) {
  return (
    <Panel title="Recorder Details">
      <div className="detail-heading">
        <StatusBadge tone={labStateTone(recorder.state)}>
          <strong>{recorder.vrcode}</strong>
          {recorder.state}
        </StatusBadge>
        <span>{formatLocalDateTime(recorder.updatedAt)}</span>
      </div>
      <KeyValueRows
        rows={[
          { label: "Recorder ID", value: recorder.recorderId },
          { label: "Bed", value: recorder.bedId },
          { label: "Session", value: recorder.sessionId },
          { label: "Messages", value: recorder.messagesSent },
          { label: "Last send", value: recorder.lastSendState },
          { label: "Last send at", value: formatLocalDateTime(recorder.lastSendAt) },
          { label: "Last error", value: recorder.lastSendError ?? "-" },
          { label: "Created", value: formatLocalDateTime(recorder.createdAt) },
          { label: "Updated", value: formatLocalDateTime(recorder.updatedAt) }
        ]}
      />
    </Panel>
  );
}

function RecorderDetails({
  recorder,
  relationships,
  relationshipsError,
  vitalFiles,
  vitalFilesError,
  vitalFilesLoading,
  observabilityDetail,
  observabilityDetailError,
  observabilityDetailLoading,
  observabilityTimeline,
  observabilityTimelineError,
  observabilityTimelineLoading,
  observabilityIncidents,
  observabilityIncidentsError,
  observabilityIncidentsLoading,
  showDelete,
  mutationPending,
  onHide,
  onUnhide,
  onDelete
}: {
  recorder: VitalDBRecorderRecord;
  relationships: VitalDBRelationships | undefined;
  relationshipsError: unknown;
  vitalFiles: RuntimeVitalRecorderVitalFileHistory | undefined;
  vitalFilesError: unknown;
  vitalFilesLoading: boolean;
  observabilityDetail: RuntimeRecorderObservabilityDetail | undefined;
  observabilityDetailError: unknown;
  observabilityDetailLoading: boolean;
  observabilityTimeline: RuntimeRecorderObservabilityTimeline | undefined;
  observabilityTimelineError: unknown;
  observabilityTimelineLoading: boolean;
  observabilityIncidents: RuntimeRecorderObservabilityIncidents | undefined;
  observabilityIncidentsError: unknown;
  observabilityIncidentsLoading: boolean;
  showDelete: boolean;
  mutationPending: boolean;
  onHide: () => void;
  onUnhide: () => void;
  onDelete: () => void;
}) {
  const assignments = (relationships?.assignments ?? []).filter(
    (assignment) => assignment.vrcode === recorder.vrcode
  );
  const events = (relationships?.events ?? []).filter(
    (event) =>
      event.vrcode === recorder.vrcode || event.previousVrcode === recorder.vrcode
  );

  return (
    <Panel title="Recorder Details" className="recorder-details">
      <div className="detail-heading">
        <div className="recorder-detail-identity">
          <StatusBadge tone={recorderStatusTone(recorder.status)}>
            <strong>{recorder.vrcode}</strong>
            {formatRecorderStatus(recorder.status)}
          </StatusBadge>
          {recorder.visibility === "hidden" ? (
            <span className="visibility-badge">Hidden from list</span>
          ) : null}
        </div>
        <div className="toolbar compact-toolbar recorder-detail-actions">
          {recorder.visibility === "hidden" ? (
            <button type="button" disabled={mutationPending} onClick={onUnhide}>
              Show in list
            </button>
          ) : (
            <button
              type="button"
              disabled={mutationPending}
              onClick={onHide}
              title="Removes this recorder from the default list. Recorder data is not deleted."
            >
              Hide from list
            </button>
          )}
        </div>
      </div>

      <div className="detail-section detail-section-first">
        <h3>Overview</h3>
        <KeyValueRows
          rows={[
            { label: "Version", value: recorder.version ?? NOT_REPORTED },
            {
              label: "Bed",
              value: recorder.bedName ?? recorder.bedID ?? NOT_REPORTED
            },
            {
              label: "Patient status",
              value: formatPatientStatus(recorder.patientConnected)
            },
            { label: "First seen", value: formatLocalDateTime(recorder.firstSeenAt) },
            {
              label: "Last seen",
              value: formatLocalDateTime(recorder.lastSeenAt)
            },
            {
              label: "Latest anomaly",
              value: formatAnomalySummary(recorder)
            }
          ]}
        />
      </div>

      <div className="detail-section">
        <h3>Health report</h3>
        <RecorderObservabilityDetailSection
          recorder={recorder}
          detail={observabilityDetail}
          error={observabilityDetailError}
          loading={observabilityDetailLoading}
        />
        <RecorderObservabilityHistory
          recorder={recorder}
          timeline={observabilityTimeline}
          timelineError={observabilityTimelineError}
          timelineLoading={observabilityTimelineLoading}
          incidents={observabilityIncidents}
          incidentsError={observabilityIncidentsError}
          incidentsLoading={observabilityIncidentsLoading}
        />
      </div>

      <div className="detail-section">
        <h3>Activity</h3>
        <RecorderActivityChart recorder={recorder} />
      </div>

      <div className="detail-section">
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

      <RelationshipHistory
        title="recorder"
        relationships={relationships}
        relationshipsError={relationshipsError}
        assignments={assignments}
        events={events}
      />

      <div className="detail-section">
        <h3>Vital files</h3>
        <RecorderVitalFiles
          history={vitalFiles}
          error={vitalFilesError}
          loading={vitalFilesLoading}
        />
      </div>

      {recorder.visibility === "hidden" && showDelete ? (
        <div className="detail-section recorder-data-management">
          <h3>Data management</h3>
          <p className="muted">
            Deleting removes this hidden recorder from the retained recorder history.
          </p>
          <Button
            tone="danger"
            disabled={mutationPending}
            onClick={() => {
              if (window.confirm(`Delete hidden VRecorder ${recorder.vrcode}?`)) {
                onDelete();
              }
            }}
          >
            Delete hidden recorder
          </Button>
        </div>
      ) : null}
    </Panel>
  );
}

function RecorderObservabilityDetailSection({
  recorder,
  detail,
  error,
  loading
}: {
  recorder: VitalDBRecorderRecord;
  detail: RuntimeRecorderObservabilityDetail | undefined;
  error: unknown;
  loading: boolean;
}) {
  if (error) {
    return <ErrorState title="Health detail is not available" error={error} />;
  }
  if (loading || detail === undefined) {
    return <p className="muted">Loading health detail...</p>;
  }
  if (detail.vrcode !== recorder.vrcode) {
    return (
      <p className="error-text">
        Health detail identity does not match the selected Recorder.
      </p>
    );
  }
  if (detail.state === "unavailable") {
    return (
      <p className="error-text">
        Health detail read failed: {detail.readError ?? "No failure detail was provided."}
      </p>
    );
  }
  const summaryMismatch =
    recorder.observability !== undefined &&
    (recorder.observability.supportState !== detail.support.state ||
      recorder.observability.reportState !== detail.report.state);

  return (
    <>
      {summaryMismatch ? (
        <p className="error-text">
          Recorder list and health detail report different support or report states.
        </p>
      ) : null}
      <KeyValueRows
        rows={[
          { label: "Support", value: formatDetailSupport(detail) },
          { label: "Report", value: formatDetailReport(detail) },
          { label: "Last report", value: formatLocalDateTime(detail.report.receivedAt) },
          { label: "Temperature", value: formatReading(detail.readings.temperatureCelsius, " °C") },
          {
            label: "Memory available",
            value: formatByteReading(detail.readings.memoryAvailableBytes)
          },
          {
            label: "Memory total",
            value: formatByteReading(detail.readings.memoryTotalBytes)
          },
          {
            label: "Root storage used",
            value: formatReading(detail.readings.rootUsedPercent, "%")
          },
          {
            label: "Data storage used",
            value: formatReading(detail.readings.dataUsedPercent, "%")
          },
          {
            label: "Recorder service",
            value: formatReading(detail.readings.recorderActiveState)
          },
          {
            label: "Publisher",
            value: formatReading(detail.readings.publisherActiveState)
          },
          {
            label: "Publisher buffer",
            value: `${formatByteReading(detail.readings.publisherBufferBytes)} / ${formatByteReading(
              detail.readings.publisherBufferLimitBytes
            )}`
          },
          { label: "Profile", value: detail.profile.state },
          { label: "Boot", value: formatBoot(detail) },
          { label: "Read issues", value: detail.report.readIssueCount }
        ]}
      />
      {detail.readIssues.length > 0 ? (
        <ul className="recorder-observability-issues">
          {detail.readIssues.map((issue, index) => (
            <li key={`${issue.field}-${index}`}>
              <strong>{issue.field}</strong>: {issue.state} — {issue.detail}
            </li>
          ))}
        </ul>
      ) : null}
      {detail.readings.networkInterfaces.length > 0 ? (
        <div className="recorder-observability-network">
          <h4>Network interfaces</h4>
          {detail.readings.networkInterfaces.map((networkInterface) => (
            <p key={networkInterface.name} className="muted">
              {networkInterface.name}: {formatReading(networkInterface.operState)},
              carrier {formatReading(networkInterface.carrier)}, RX errors{" "}
              {formatReading(networkInterface.rxErrors)}, TX errors{" "}
              {formatReading(networkInterface.txErrors)}
            </p>
          ))}
        </div>
      ) : null}
    </>
  );
}

function RecorderObservabilityHistory({
  recorder,
  timeline,
  timelineError,
  timelineLoading,
  incidents,
  incidentsError,
  incidentsLoading
}: {
  recorder: VitalDBRecorderRecord;
  timeline: RuntimeRecorderObservabilityTimeline | undefined;
  timelineError: unknown;
  timelineLoading: boolean;
  incidents: RuntimeRecorderObservabilityIncidents | undefined;
  incidentsError: unknown;
  incidentsLoading: boolean;
}) {
  const identityMismatch =
    (timeline !== undefined && timeline.vrcode !== recorder.vrcode) ||
    (incidents !== undefined && incidents.vrcode !== recorder.vrcode);
  return (
    <div className="recorder-observability-history">
      <h4>Last 24 hours</h4>
      {identityMismatch ? (
        <p className="error-text">
          Health history identity does not match the selected Recorder.
        </p>
      ) : null}
      {timelineError ? (
        <ErrorState title="Health timeline request failed" error={timelineError} />
      ) : timelineLoading ? (
        <p className="muted">Loading health timeline...</p>
      ) : timeline?.state === "unavailable" ? (
        <p className="error-text">
          Health timeline read failed: {timeline.readError ?? "No failure detail was provided."}
        </p>
      ) : timeline?.state === "unsupported" ? (
        <p className="muted">This Recorder explicitly does not support health reports.</p>
      ) : timeline?.state === "notReported" ? (
        <p className="muted">No health report was received during this window.</p>
      ) : timeline?.state === "loaded" && timeline.buckets.length > 0 ? (
        <ObservabilityStorageChart timeline={timeline} />
      ) : (
        <p className="muted">Health timeline is not available.</p>
      )}

      <h4>Recent incidents</h4>
      {incidentsError ? (
        <ErrorState title="Incident history request failed" error={incidentsError} />
      ) : incidentsLoading ? (
        <p className="muted">Loading incidents...</p>
      ) : incidents?.state === "unavailable" ? (
        <p className="error-text">
          Incident history read failed: {incidents.readError ?? "No failure detail was provided."}
        </p>
      ) : incidents?.incidents.length ? (
        <ul className="recorder-observability-issues">
          {incidents.incidents.map((incident) => (
            <li key={incident.recordId}>
              <strong>{incident.incidentType}</strong>{" "}
              {formatLocalDateTime(incident.receivedAt)} — {incident.messageExcerpt}
              {incident.truncated ? " (truncated)" : ""}
            </li>
          ))}
        </ul>
      ) : (
        <p className="muted">No kernel incident was received during this window.</p>
      )}
    </div>
  );
}

function ObservabilityStorageChart({
  timeline
}: {
  timeline: RuntimeRecorderObservabilityTimeline;
}) {
  const width = 720;
  const height = 180;
  const inset = 28;
  const points = timeline.buckets.map((bucket, index) => ({
    x:
      timeline.buckets.length === 1
        ? width / 2
        : inset + (index / (timeline.buckets.length - 1)) * (width - inset * 2),
    root: bucket.metrics.rootUsedPercent?.average ?? null,
    data: bucket.metrics.dataUsedPercent?.average ?? null
  }));
  if (!points.some((point) => point.root !== null || point.data !== null)) {
    return (
      <p className="muted">
        Health reports were received, but storage usage was not reported in this window.
      </p>
    );
  }
  const y = (value: number) =>
    height - inset - (Math.max(0, Math.min(100, value)) / 100) * (height - inset * 2);
  return (
    <div>
      <svg
        className="activity-chart"
        viewBox={`0 0 ${width} ${height}`}
        role="img"
        aria-label="Root and data storage usage over the last 24 hours"
      >
        <line
          className="activity-axis-line"
          x1={inset}
          y1={inset}
          x2={inset}
          y2={height - inset}
        />
        <line
          className="activity-axis-line"
          x1={inset}
          y1={height - inset}
          x2={width - inset}
          y2={height - inset}
        />
        {(["root", "data"] as const).flatMap((metric, seriesIndex) =>
          points.slice(1).flatMap((point, index) => {
            const previous = points[index];
            const previousValue = previous[metric];
            const value = point[metric];
            return previousValue === null || value === null
              ? []
              : [
                  <line
                    key={`${metric}-${index}`}
                    x1={previous.x}
                    y1={y(previousValue)}
                    x2={point.x}
                    y2={y(value)}
                    className={seriesIndex === 0 ? "chart-series-primary" : "chart-series-secondary"}
                  />
                ];
          })
        )}
      </svg>
      <p className="muted">Storage used: root (blue), data (orange). Receipt time, 15-minute buckets.</p>
    </div>
  );
}

function formatDetailSupport(detail: RuntimeRecorderObservabilityDetail): string {
  switch (detail.support.state) {
    case "supported":
      return "Supported";
    case "unsupported":
      return "Not available on this version";
    case "unknown":
      return "Support unknown";
  }
}

function formatDetailReport(detail: RuntimeRecorderObservabilityDetail): string {
  if (detail.support.state === "unsupported") {
    return "Not applicable";
  }
  switch (detail.report.state) {
    case "awaitingFirstReport":
      return "Waiting for first report";
    case "current":
      return "Current";
    case "stale":
      return "Stale";
    case "missing":
      return "Missing";
    case "readFailed":
      return "Unavailable";
    case "notEvaluated":
      return "Not evaluated";
  }
}

function formatReading(
  reading: RuntimeRecorderObservabilityDetail["readings"]["temperatureCelsius"],
  suffix = ""
): string {
  if (reading.state !== "ok") {
    return `${reading.state}${reading.detail ? ` — ${reading.detail}` : ""}`;
  }
  if (
    typeof reading.value !== "string" &&
    typeof reading.value !== "number" &&
    typeof reading.value !== "boolean"
  ) {
    return "invalid — scalar value expected";
  }
  return `${String(reading.value)}${suffix}`;
}

function formatByteReading(
  reading: RuntimeRecorderObservabilityDetail["readings"]["memoryAvailableBytes"]
): string {
  return reading.state === "ok" && typeof reading.value === "number"
    ? formatBytes(reading.value)
    : formatReading(reading);
}

function formatBoot(detail: RuntimeRecorderObservabilityDetail): string {
  switch (detail.boot.state) {
    case "started":
      return `Started ${formatLocalDateTime(detail.boot.startedAt)}`;
    case "shutdownClean":
      return `Clean shutdown ${formatLocalDateTime(detail.boot.cleanShutdownAt)}`;
    case "notReported":
      return "Not reported";
  }
}

function formatObservabilityReport(
  observability: VitalDBRecorderRecord["observability"]
): string {
  if (observability?.supportState === "unsupported") {
    return "Not applicable";
  }
  switch (observability?.reportState) {
    case "awaitingFirstReport":
      return "Waiting for first report";
    case "current":
      return "Current";
    case "stale":
      return "Stale";
    case "missing":
      return "Missing";
    case "readFailed":
      return "Unavailable";
    case "notEvaluated":
    default:
      return "Not evaluated";
  }
}

function observabilityTone(
  observability: VitalDBRecorderRecord["observability"]
): "success" | "warning" | "danger" | "neutral" {
  switch (observability?.reportState) {
    case "current":
      return "success";
    case "awaitingFirstReport":
    case "stale":
      return "warning";
    case "missing":
    case "readFailed":
      return "danger";
    default:
      return "neutral";
  }
}

function RecorderVitalFiles({
  history,
  error,
  loading
}: {
  history: RuntimeVitalRecorderVitalFileHistory | undefined;
  error: unknown;
  loading: boolean;
}) {
  if (error) {
    return <ErrorState error={error} />;
  }
  if (loading || history === undefined) {
    return <p className="muted">Loading tracked Vital files...</p>;
  }
  if (history.files.length === 0) {
    return (
      <p className={history.state === "readFailed" ? "error-text" : "muted"}>
        {history.readError === null
          ? "No tracked Vital files are attributed to this VRecorder."
          : `Vital file history read issue: ${history.readError}`}
      </p>
    );
  }
  return (
    <div className="recorder-vital-file-list">
      {history.files.map((file) => (
        <div className="recorder-vital-file" key={file.fileID}>
          <div className="detail-heading">
            <strong>{file.filename}</strong>
            <div className="toolbar compact-toolbar">
              <span className="visibility-badge">
                {file.origin === "nativeRecorderUpload"
                  ? "Recorder upload"
                  : "Cold-path recovery"}
              </span>
              <StatusBadge tone={file.status === "failed" ? "danger" : "neutral"}>
                {file.status}
              </StatusBadge>
            </div>
          </div>
          <p className="muted">
            {formatBytes(file.sizeBytes)} · received {formatLocalDateTime(file.receivedAt)}
          </p>
          <p className="muted">
            Bed {file.bedName ?? NOT_REPORTED} · attribution {file.attribution.state}
          </p>
          {file.failure === null ? null : (
            <p className="error-text">
              {file.failure.stage} / {file.failure.code}: {file.failure.message}
            </p>
          )}
        </div>
      ))}
    </div>
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

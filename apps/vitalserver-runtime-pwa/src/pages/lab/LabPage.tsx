import { useEffect, useMemo, useState } from "react";

import {
  useCreateLabBeds,
  useCreateLabRecorders,
  useCreateLabSession,
  useFinishLabSession,
  useDeleteLabBeds,
  useDeleteLabRecorders,
  useLabBeds,
  useLabRecorders,
  useLabScenarios,
  useLabSession,
  useLabSessions,
  useLabVitalFiles,
  useReplayLabVitalFile,
  useResetLabBeds,
  useResetLabRecorders,
  useControlCapabilities,
  useStartLabSession,
  useStartLabRecorder,
  useStopLabRecorder,
  useStopLabSession,
  useUploadLabVitalFiles
} from "@/console/hooks";
import type {
  RuntimeLabBed,
  RuntimeLabVitalFile,
  RuntimeLabRecorder,
  RuntimeLabScenario,
  RuntimeLabSession,
  RuntimeLabSessionResponse
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";

export function LabPage() {
  const capabilities = useControlCapabilities();
  const scenarios = useLabScenarios();
  const beds = useLabBeds();
  const recorders = useLabRecorders();
  const sessions = useLabSessions(
    capabilities.data?.canListLabSessions === true
  );
  const vitalFiles = useLabVitalFiles();
  const createBeds = useCreateLabBeds();
  const deleteBeds = useDeleteLabBeds();
  const resetBeds = useResetLabBeds();
  const createRecorders = useCreateLabRecorders();
  const deleteRecorders = useDeleteLabRecorders();
  const resetRecorders = useResetLabRecorders();
  const createSession = useCreateLabSession();
  const startSession = useStartLabSession();
  const stopSession = useStopLabSession();
  const finishSession = useFinishLabSession();
  const startRecorder = useStartLabRecorder();
  const stopRecorder = useStopLabRecorder();
  const replayVitalFile = useReplayLabVitalFile();
  const uploadVitalFiles = useUploadLabVitalFiles();

  const [selectedScenarioId, setSelectedScenarioId] = useState("");
  const [targetURL, setTargetURL] = useState("");
  const [sessionName, setSessionName] = useState("Lab session");
  const [recorderCount, setRecorderCount] = useState(1);
  const [sessionBedTargets, setSessionBedTargets] = useState("");
  const [selectedSessionId, setSelectedSessionId] = useState("");
  const [bedRoomNames, setBedRoomNames] = useState("Lab-1");
  const [bedPrefix, setBedPrefix] = useState("Lab bed");
  const [deleteBedTargets, setDeleteBedTargets] = useState("");
  const [recorderBedTargets, setRecorderBedTargets] = useState("");
  const [deleteRecorderTargets, setDeleteRecorderTargets] = useState("");
  const [vitalFilePath, setVitalFilePath] = useState("");
  const [vitalUploadFiles, setVitalUploadFiles] = useState<File[]>([]);
  const [vitalReplayName, setVitalReplayName] = useState("Vital file replay");
  const [vitalReplayResourceMode, setVitalReplayResourceMode] =
    useState<"quickCreate" | "existing">("quickCreate");
  const [vitalReplayBedId, setVitalReplayBedId] = useState("");
  const [vitalReplayRecorderId, setVitalReplayRecorderId] = useState("");
  const [vitalReplayRepeatMode, setVitalReplayRepeatMode] =
    useState<"once" | "count" | "continuous">("once");
  const [vitalReplayCount, setVitalReplayCount] = useState(2);
  const [lastResponse, setLastResponse] =
    useState<RuntimeLabSessionResponse | null>(null);

  const session = useLabSession(selectedSessionId.trim() || null);
  const scenarioOptions = scenarios.data?.scenarios ?? [];
  const vitalFileOptions = vitalFiles.data?.vitalFiles ?? [];
  const selectedScenario = useMemo(
    () => scenarioOptions.find((scenario) => scenario.scenarioId === selectedScenarioId),
    [scenarioOptions, selectedScenarioId]
  );
  const sessionOptions = sessions.data?.sessions ?? [];
  const selectedSessionRecorders = useMemo(
    () =>
      (recorders.data?.recorders ?? []).filter(
        (recorder) => recorder.sessionId === selectedSessionId
      ),
    [recorders.data?.recorders, selectedSessionId]
  );

  useEffect(() => {
    if (
      selectedScenarioId.length === 0 &&
      scenarioOptions.length > 0
    ) {
      setSelectedScenarioId(scenarioOptions[0]?.scenarioId ?? "");
    }
  }, [scenarioOptions, selectedScenarioId]);

  useEffect(() => {
    if (vitalFilePath.length === 0 && vitalFileOptions.length > 0) {
      setVitalFilePath(vitalFileOptions[0]?.relativePath ?? "");
    }
  }, [vitalFileOptions, vitalFilePath]);

  useEffect(() => {
    if (vitalReplayBedId.length === 0 && (beds.data?.beds.length ?? 0) > 0) {
      setVitalReplayBedId(beds.data?.beds[0]?.bedId ?? "");
    }
  }, [beds.data?.beds, vitalReplayBedId]);

  const replayBedRecorders = (recorders.data?.recorders ?? []).filter(
    (recorder) => recorder.bedId === vitalReplayBedId
  );
  useEffect(() => {
    if (!replayBedRecorders.some((recorder) => recorder.recorderId === vitalReplayRecorderId)) {
      setVitalReplayRecorderId(replayBedRecorders[0]?.recorderId ?? "");
    }
  }, [replayBedRecorders, vitalReplayRecorderId]);

  useEffect(() => {
    if (selectedSessionId.length > 0 || sessionOptions.length === 0) {
      return;
    }
    const initialSession =
      sessionOptions.find((candidate) => candidate.state === "running") ??
      sessionOptions[0];
    setSelectedSessionId(initialSession?.sessionId ?? "");
  }, [selectedSessionId, sessionOptions]);

  const isBusy =
    createSession.isPending ||
    createBeds.isPending ||
    deleteBeds.isPending ||
    resetBeds.isPending ||
    createRecorders.isPending ||
    deleteRecorders.isPending ||
    resetRecorders.isPending ||
    startSession.isPending ||
    stopSession.isPending ||
    finishSession.isPending ||
    startRecorder.isPending ||
    stopRecorder.isPending ||
    replayVitalFile.isPending ||
    uploadVitalFiles.isPending;
  const latestError =
    scenarios.error ??
    beds.error ??
    recorders.error ??
    sessions.error ??
    vitalFiles.error ??
    session.error ??
    capabilities.error ??
    createBeds.error ??
    deleteBeds.error ??
    resetBeds.error ??
    createRecorders.error ??
    deleteRecorders.error ??
    resetRecorders.error ??
    createSession.error ??
    startSession.error ??
    stopSession.error ??
    finishSession.error ??
    startRecorder.error ??
    stopRecorder.error ??
    replayVitalFile.error ??
    uploadVitalFiles.error;
  const labCapability = capabilities.data?.canUseLab;
  const canListSessions = capabilities.data?.canListLabSessions === true;
  const canControlRecorders =
    capabilities.data?.canControlLabRecorders === true;
  const activeResponse =
    (lastResponse?.session?.sessionId === selectedSessionId ? lastResponse : null) ??
    session.data;
  const activeSessionId = activeResponse?.session?.sessionId ?? selectedSessionId.trim();
  const canCreate =
    labCapability === true &&
    scenarios.data?.state === "loaded" &&
    selectedScenarioId.trim().length > 0 &&
    recorderCount >= 1 &&
    !isBusy;
  const canControl = labCapability === true && activeSessionId.length > 0 && !isBusy;
  const canStartSession =
    canControl &&
    (activeResponse?.session?.state === "accepted" ||
      activeResponse?.session?.state === "stopped");
  const canStopSession =
    canControl && activeResponse?.session?.state === "running";
  const canFinishSession =
    canControl &&
    (activeResponse?.session?.state === "running" ||
      activeResponse?.session?.state === "stopped" ||
      activeResponse?.session?.state === "finished");
  const hasTargetURL = targetURL.trim().length > 0;
  const canReplay =
    labCapability === true &&
    vitalFilePath.trim().length > 0 &&
    hasTargetURL &&
    (vitalReplayResourceMode === "quickCreate" ||
      (vitalReplayBedId.length > 0 && vitalReplayRecorderId.length > 0)) &&
    (vitalReplayRepeatMode !== "count" || vitalReplayCount >= 2) &&
    !isBusy;
  const canUploadVitalFiles =
    labCapability === true &&
    vitalUploadFiles.length > 0 &&
    !isBusy;
  const canCreateBeds = labCapability === true && splitList(bedRoomNames).length > 0 && !isBusy;
  const canDeleteBeds = labCapability === true && splitList(deleteBedTargets).length > 0 && !isBusy;
  const canCreateRecorders = labCapability === true && splitList(recorderBedTargets).length > 0 && !isBusy;
  const canDeleteRecorders = labCapability === true && splitList(deleteRecorderTargets).length > 0 && !isBusy;

  const create = () => {
    const bedIds = splitList(sessionBedTargets);
    const resolvedRecorderCount =
      bedIds.length > 0 ? bedIds.length : Math.max(1, Math.trunc(recorderCount));
    createSession.mutate(
      {
        scenarioId: selectedScenarioId.trim(),
        name: sessionName.trim() || null,
        recorderCount: resolvedRecorderCount,
        targetURL: optionalText(targetURL),
        bedIds
      },
      {
        onSuccess: (response) => {
          setLastResponse(response);
          setSelectedSessionId(response.session?.sessionId ?? "");
        }
      }
    );
  };

  const start = () => {
    startSession.mutate(activeSessionId, {
      onSuccess: (response) => {
        setLastResponse(response);
        setSelectedSessionId(response.session?.sessionId ?? activeSessionId);
      }
    });
  };

  const stop = () => {
    stopSession.mutate(activeSessionId, {
      onSuccess: (response) => {
        setLastResponse(response);
        setSelectedSessionId(response.session?.sessionId ?? activeSessionId);
      }
    });
  };

  const finish = () => {
    finishSession.mutate(activeSessionId, {
      onSuccess: (response) => {
        setLastResponse(response);
        setSelectedSessionId(response.session?.sessionId ?? activeSessionId);
      }
    });
  };

  const replay = () => {
    replayVitalFile.mutate(
      {
        vitalFileRelativePath: vitalFilePath.trim(),
        sessionName: vitalReplayName.trim() || null,
        targetURL: optionalText(targetURL),
        resourceSelection:
          vitalReplayResourceMode === "quickCreate"
            ? { mode: "quickCreate" }
            : {
                mode: "existing",
                bedId: vitalReplayBedId,
                recorderId: vitalReplayRecorderId
              },
        repeatPolicy:
          vitalReplayRepeatMode === "count"
            ? { mode: "count", count: Math.trunc(vitalReplayCount) }
            : { mode: vitalReplayRepeatMode }
      },
      {
        onSuccess: (response) => {
          setLastResponse(response);
          setSelectedSessionId(response.session?.sessionId ?? "");
        }
      }
    );
  };

  const uploadSelectedVitalFiles = () => {
    uploadVitalFiles.mutate(
      { files: vitalUploadFiles },
      { onSuccess: () => setVitalUploadFiles([]) }
    );
  };

  const createManualBeds = () => {
    const roomNames = splitList(bedRoomNames);
    createBeds.mutate({
      count: roomNames.length,
      roomNames,
      prefix: bedPrefix.trim() || null,
      targetURL: optionalText(targetURL)
    });
  };


  const deleteManualBeds = () => {
    deleteBeds.mutate({ bedIds: splitList(deleteBedTargets) });
  };

  const createManualRecorders = () => {
    createRecorders.mutate({ bedIds: splitList(recorderBedTargets) });
  };

  const deleteManualRecorders = () => {
    deleteRecorders.mutate({ recorderIds: splitList(deleteRecorderTargets) });
  };

  return (
    <div className="page-stack">
      <Panel
        title="Product Lab"
        actions={
          <button
            type="button"
            disabled={scenarios.isFetching}
            onClick={() => scenarios.refetch()}
          >
            Refresh
          </button>
        }
      >
        <KeyValueRows
          rows={[
            { label: "Catalog", value: scenarios.data?.state ?? NOT_REPORTED },
            {
              label: "Capability",
              value: labCapability === undefined ? NOT_REPORTED : String(labCapability)
            },
            { label: "Session list", value: String(canListSessions) },
            { label: "Recorder control", value: String(canControlRecorders) },
            { label: "Scenarios", value: scenarioOptions.length },
            { label: "Vital files", value: vitalFileOptions.length },
            { label: "Read error", value: scenarios.data?.readError ?? "-" },
            { label: "Vital file read error", value: vitalFiles.data?.readError ?? "-" },
            { label: "Selected", value: selectedScenario?.name ?? NOT_REPORTED }
          ]}
        />
        {latestError ? <ErrorState title="Lab operation failed" error={latestError} /> : null}
      </Panel>

      <Panel
        title="New scenario session"
        actions={
          <button
            type="button"
            className="ui-button-primary"
            disabled={!canCreate}
            onClick={create}
          >
            Create session
          </button>
        }
      >
        <div className="settings-grid">
          <label>
            Scenario
            <select
              value={selectedScenarioId}
              onChange={(event) => setSelectedScenarioId(event.target.value)}
              disabled={scenarioOptions.length === 0}
            >
              {scenarioOptions.map((scenario) => (
                <option key={scenario.scenarioId} value={scenario.scenarioId}>
                  {scenario.name}
                </option>
              ))}
            </select>
          </label>
          <label>
            Recorders
            <input
              type="number"
              min="1"
              value={recorderCount}
              onChange={(event) => setRecorderCount(Number(event.target.value))}
            />
          </label>
          <label className="full-width">
            Target URL
            <input
              type="url"
              value={targetURL}
              onChange={(event) => setTargetURL(event.target.value)}
              placeholder="http://vitalserver:8000"
            />
          </label>
          <label className="full-width">
            Session bed IDs
            <input
              type="text"
              value={sessionBedTargets}
              onChange={(event) => setSessionBedTargets(event.target.value)}
              placeholder="manual_session_1-bed-1, manual_session_1-bed-2"
            />
          </label>
          <label className="full-width">
            Session name
            <input
              type="text"
              value={sessionName}
              onChange={(event) => setSessionName(event.target.value)}
            />
          </label>
        </div>
        <ScenarioList scenarios={scenarioOptions} />
      </Panel>

      <Panel
        title="Sessions"
        actions={
          <button
            type="button"
            disabled={!canListSessions || sessions.isFetching}
            onClick={() => sessions.refetch()}
          >
            Refresh
          </button>
        }
      >
        <KeyValueRows
          rows={[
            { label: "Read state", value: sessions.data?.state ?? NOT_REPORTED },
            { label: "Sessions", value: sessionOptions.length },
            { label: "Read error", value: sessions.data?.readError ?? "-" }
          ]}
        />
        <LabSessionList
          sessions={sessionOptions}
          selectedSessionId={selectedSessionId}
          onSelect={setSelectedSessionId}
        />
      </Panel>

      <Panel
        title="Selected session"
        actions={
          <>
            <button type="button" disabled={!canStartSession} onClick={start}>
              Start
            </button>
            <button type="button" disabled={!canStopSession} onClick={stop}>
              Pause
            </button>
            <button type="button" disabled={!canFinishSession} onClick={finish}>
              {activeResponse?.session?.state === "finished"
                ? "Retry export"
                : "Finish & export"}
            </button>
          </>
        }
      >
        <LabResponseSummary response={activeResponse} />
      </Panel>

      <Panel
        title="Session recorders"
        actions={
          <button
            type="button"
            disabled={recorders.isFetching}
            onClick={() => recorders.refetch()}
          >
            Refresh
          </button>
        }
      >
        {activeResponse?.session?.state !== "running" && selectedSessionId ? (
          <p className="muted">
            Recorder controls are available while the selected session is running.
          </p>
        ) : null}
        <LabSessionRecorderList
          recorders={selectedSessionRecorders}
          sessionState={activeResponse?.session?.state}
          disabled={labCapability !== true || !canControlRecorders || isBusy}
          onStart={(recorderId) =>
            startRecorder.mutate({ sessionId: selectedSessionId, recorderId })
          }
          onStop={(recorderId) =>
            stopRecorder.mutate({ sessionId: selectedSessionId, recorderId })
          }
        />
      </Panel>

      <Panel
        title="Bed management"
        actions={
          <>
            <button type="button" disabled={!canCreateBeds} onClick={createManualBeds}>
              Create beds
            </button>
            <button type="button" disabled={!canDeleteBeds} onClick={deleteManualBeds}>
              Delete beds
            </button>
            <button type="button" disabled={labCapability !== true || isBusy} onClick={() => resetBeds.mutate(undefined)}>
              Reset beds
            </button>
          </>
        }
      >
        <div className="settings-grid">
          <label>
            Names
            <input
              type="text"
              value={bedRoomNames}
              onChange={(event) => setBedRoomNames(event.target.value)}
            />
          </label>
          <label>
            Prefix
            <input
              type="text"
              value={bedPrefix}
              onChange={(event) => setBedPrefix(event.target.value)}
            />
          </label>
          <label className="full-width">
            Delete bed IDs
            <input
              type="text"
              value={deleteBedTargets}
              onChange={(event) => setDeleteBedTargets(event.target.value)}
            />
          </label>
        </div>
      </Panel>

      <Panel
        title="Recorder management"
        actions={
          <>
            <button type="button" disabled={!canCreateRecorders} onClick={createManualRecorders}>
              Create recorders
            </button>
            <button type="button" disabled={!canDeleteRecorders} onClick={deleteManualRecorders}>
              Delete recorders
            </button>
            <button type="button" disabled={labCapability !== true || isBusy} onClick={() => resetRecorders.mutate(undefined)}>
              Reset recorders
            </button>
          </>
        }
      >
        <div className="settings-grid">
          <label className="full-width">
            Bed IDs
            <input
              type="text"
              value={recorderBedTargets}
              onChange={(event) => setRecorderBedTargets(event.target.value)}
            />
          </label>
          <label className="full-width">
            Delete recorder IDs
            <input
              type="text"
              value={deleteRecorderTargets}
              onChange={(event) => setDeleteRecorderTargets(event.target.value)}
            />
          </label>
        </div>
      </Panel>

      <Panel
        title="Lab read model"
        actions={
          <button
            type="button"
            disabled={beds.isFetching || recorders.isFetching}
            onClick={() => {
              beds.refetch();
              recorders.refetch();
            }}
          >
            Refresh
          </button>
        }
      >
        <KeyValueRows
          rows={[
            { label: "Beds", value: beds.data?.beds.length ?? NOT_REPORTED },
            {
              label: "Recorders",
              value: recorders.data?.recorders.length ?? NOT_REPORTED
            },
            { label: "Bed read", value: beds.data?.state ?? NOT_REPORTED },
            {
              label: "Recorder read",
              value: recorders.data?.state ?? NOT_REPORTED
            },
            { label: "Bed read error", value: beds.data?.readError ?? "-" },
            {
              label: "Recorder read error",
              value: recorders.data?.readError ?? "-"
            }
          ]}
        />
        <LabReadModelList
          beds={beds.data?.beds ?? []}
          recorders={recorders.data?.recorders ?? []}
        />
      </Panel>

      <Panel
        title="Vital Files"
        actions={
          <>
            <button type="button" disabled={vitalFiles.isFetching} onClick={() => vitalFiles.refetch()}>
              Refresh files
            </button>
            <button
              type="button"
              className="ui-button-primary"
              disabled={!canReplay}
              onClick={replay}
            >
              Replay
            </button>
          </>
        }
      >
        <section className="page-stack" aria-label="Upload Vital Files">
          <h3>Upload to library</h3>
          <p>
            Select one or more <code>.vital</code> files. Each file is evaluated
            independently; failures do not stop later files from being uploaded.
          </p>
          <input
            key={vitalUploadFiles.length === 0 ? "empty" : "selected"}
            type="file"
            accept=".vital"
            multiple
            aria-label="Vital files to upload"
            onChange={(event) => setVitalUploadFiles(Array.from(event.target.files ?? []))}
          />
          <div>
            {vitalUploadFiles.length === 0
              ? "No files selected"
              : `${vitalUploadFiles.length} file(s): ${vitalUploadFiles.map((file) => file.name).join(", ")}`}
          </div>
          <button
            type="button"
            disabled={!canUploadVitalFiles}
            onClick={uploadSelectedVitalFiles}
          >
            Upload {vitalUploadFiles.length > 0 ? vitalUploadFiles.length : ""} file(s)
          </button>
          {uploadVitalFiles.data?.failedFiles.length ? (
            <ErrorState
              title="Files that could not be uploaded"
              error={new Error(
                uploadVitalFiles.data.failedFiles
                  .map((failure) => `${failure.fileName}: ${failure.reason}`)
                  .join("\n")
              )}
            />
          ) : null}
        </section>
        <hr />
        <h3>Replay uploaded file</h3>
        <div className="settings-grid">
          <label>
            Session name
            <input
              type="text"
              value={vitalReplayName}
              onChange={(event) => setVitalReplayName(event.target.value)}
            />
          </label>
          <label>
            Uploaded Vital File
            <select
              value={vitalFilePath}
              onChange={(event) => setVitalFilePath(event.target.value)}
              disabled={vitalFileOptions.length === 0}
            >
              {vitalFileOptions.map((vitalFile) => (
                <option key={vitalFile.relativePath} value={vitalFile.relativePath}>
                  {vitalFile.displayName}
                </option>
              ))}
            </select>
          </label>
          <label>
            Replay resources
            <select
              value={vitalReplayResourceMode}
              onChange={(event) =>
                setVitalReplayResourceMode(event.target.value as "quickCreate" | "existing")
              }
            >
              <option value="quickCreate">Quick create bed and recorder</option>
              <option value="existing">Use existing bed and recorder</option>
            </select>
          </label>
          <label>
            Repeat
            <select
              value={vitalReplayRepeatMode}
              onChange={(event) =>
                setVitalReplayRepeatMode(event.target.value as "once" | "count" | "continuous")
              }
            >
              <option value="once">Once</option>
              <option value="count">N times</option>
              <option value="continuous">Continuous</option>
            </select>
          </label>
          {vitalReplayResourceMode === "existing" ? (
            <>
              <label>
                Bed
                <select value={vitalReplayBedId} onChange={(event) => setVitalReplayBedId(event.target.value)}>
                  {(beds.data?.beds ?? []).map((bed) => (
                    <option key={bed.bedId} value={bed.bedId}>{bed.name}</option>
                  ))}
                </select>
              </label>
              <label>
                Recorder
                <select value={vitalReplayRecorderId} onChange={(event) => setVitalReplayRecorderId(event.target.value)}>
                  {replayBedRecorders.map((recorder) => (
                    <option key={recorder.recorderId} value={recorder.recorderId}>{recorder.vrcode}</option>
                  ))}
                </select>
              </label>
            </>
          ) : null}
          {vitalReplayRepeatMode === "count" ? (
            <label>
              Repeat count
              <input
                type="number"
                min={2}
                step={1}
                value={vitalReplayCount}
                onChange={(event) => setVitalReplayCount(Number(event.target.value))}
              />
            </label>
          ) : null}
        </div>
        <VitalFileList vitalFiles={vitalFileOptions} />
      </Panel>
    </div>
  );
}

function optionalText(value: string): string | null {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function LabSessionList({
  sessions,
  selectedSessionId,
  onSelect
}: {
  sessions: RuntimeLabSession[];
  selectedSessionId: string;
  onSelect: (sessionId: string) => void;
}) {
  if (sessions.length === 0) {
    return <p className="muted">No Lab sessions reported.</p>;
  }

  return (
    <div className="session-list">
      {sessions.map((session) => (
        <button
          key={session.sessionId}
          type="button"
          className="session-row"
          aria-pressed={session.sessionId === selectedSessionId}
          onClick={() => onSelect(session.sessionId)}
        >
          <div>
            <strong>{session.name ?? session.sessionId}</strong>
            <StatusBadge tone={labSessionStateTone(session.state)}>
              {session.state}
            </StatusBadge>
          </div>
          <KeyValueRows
            rows={[
              { label: "Scenario", value: session.scenarioId },
              { label: "Recorders", value: session.recorderCount },
              {
                label: "Recovery artifact export",
                value: archiveFinalizationSummary(session)
              },
              { label: "Session ID", value: session.sessionId },
              { label: "Updated", value: session.updatedAt ?? NOT_REPORTED }
            ]}
          />
        </button>
      ))}
    </div>
  );
}

function LabSessionRecorderList({
  recorders,
  sessionState,
  disabled,
  onStart,
  onStop
}: {
  recorders: RuntimeLabRecorder[];
  sessionState: RuntimeLabSession["state"] | undefined;
  disabled: boolean;
  onStart: (recorderId: string) => void;
  onStop: (recorderId: string) => void;
}) {
  if (recorders.length === 0) {
    return <p className="muted">No recorders reported for the selected session.</p>;
  }

  return (
    <div className="session-list">
      {recorders.map((recorder) => (
        <div key={recorder.recorderId} className="session-row">
          <div>
            <strong>{recorder.vrcode}</strong>
            <StatusBadge tone={labSessionStateTone(recorder.state)}>
              {recorder.state}
            </StatusBadge>
          </div>
          <KeyValueRows
            rows={[
              { label: "Recorder ID", value: recorder.recorderId },
              { label: "Bed", value: recorder.bedId },
              { label: "Messages", value: recorder.messagesSent },
              { label: "Last send", value: recorder.lastSendState },
              { label: "Send error", value: recorder.lastSendError ?? "-" }
            ]}
          />
          <div className="button-row">
            <button
              type="button"
              disabled={
                disabled || sessionState !== "running" || recorder.state === "running"
              }
              onClick={() => onStart(recorder.recorderId)}
            >
              Start recorder
            </button>
            <button
              type="button"
              disabled={
                disabled || sessionState !== "running" || recorder.state !== "running"
              }
              onClick={() => onStop(recorder.recorderId)}
            >
              Stop recorder
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}

function LabReadModelList({
  beds,
  recorders
}: {
  beds: RuntimeLabBed[];
  recorders: RuntimeLabRecorder[];
}) {
  if (beds.length === 0 && recorders.length === 0) {
    return <p className="muted">No Lab read model reported.</p>;
  }

  return (
    <div className="session-list">
      {beds.map((bed) => (
        <div key={bed.bedId} className="session-row">
          <div>
            <strong>{bed.name}</strong>
            <span className="muted">{bed.state}</span>
          </div>
          <p className="muted">{bed.bedId}</p>
        </div>
      ))}
      {recorders.map((recorder) => (
        <div key={recorder.recorderId} className="session-row">
          <div>
            <strong>{recorder.vrcode}</strong>
            <span className="muted">{recorder.lastSendState}</span>
          </div>
          <KeyValueRows
            rows={[
              { label: "Messages", value: recorder.messagesSent },
              { label: "Bed", value: recorder.bedId },
              { label: "Session", value: recorder.sessionId },
              { label: "Last send", value: recorder.lastSendAt ?? NOT_REPORTED },
              { label: "Send error", value: recorder.lastSendError ?? "-" }
            ]}
          />
        </div>
      ))}
    </div>
  );
}

function VitalFileList({ vitalFiles }: { vitalFiles: RuntimeLabVitalFile[] }) {
  if (vitalFiles.length === 0) {
    return <p className="muted">No vital files reported.</p>;
  }

  return (
    <div className="session-list">
      {vitalFiles.slice(0, 8).map((vitalFile) => (
        <div key={vitalFile.guestPath} className="session-row">
          <div>
            <strong>{vitalFile.displayName}</strong>
            <span className="muted">{formatBytes(vitalFile.sizeBytes)}</span>
          </div>
          <KeyValueRows
            rows={[
              { label: "Guest path", value: vitalFile.guestPath },
              { label: "Relative path", value: vitalFile.relativePath },
              { label: "Modified", value: vitalFile.modifiedAt ?? NOT_REPORTED }
            ]}
          />
        </div>
      ))}
    </div>
  );
}

function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes)) {
    return NOT_REPORTED;
  }
  if (bytes < 1024) {
    return `${bytes} B`;
  }
  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KiB`;
  }
  if (bytes < 1024 * 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MiB`;
  }
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GiB`;
}

function splitList(value: string): string[] {
  return value
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function ScenarioList({ scenarios }: { scenarios: RuntimeLabScenario[] }) {
  if (scenarios.length === 0) {
    return <p className="muted">No scenarios reported.</p>;
  }

  return (
    <div className="session-list">
      {scenarios.map((scenario) => (
        <div key={scenario.scenarioId} className="session-row">
          <div>
            <strong>{scenario.name}</strong>
            <span className="muted">{scenario.category}</span>
          </div>
          {scenario.description ? <p className="muted">{scenario.description}</p> : null}
        </div>
      ))}
    </div>
  );
}

function LabResponseSummary({
  response
}: {
  response: RuntimeLabSessionResponse | null | undefined;
}) {
  if (!response) {
    return <p className="muted">No session selected.</p>;
  }

  const session = response.session;

  return (
    <KeyValueRows
      rows={[
        {
          label: "State",
          value: (
            <StatusBadge tone={labStateTone(response.state)}>
              {response.state}
            </StatusBadge>
          )
        },
        { label: "Read error", value: response.readError ?? "-" },
        { label: "Operation", value: response.operationId ?? NOT_REPORTED },
        { label: "Session ID", value: session?.sessionId ?? NOT_REPORTED },
        { label: "Session state", value: session?.state ?? NOT_REPORTED },
        { label: "Scenario", value: session?.scenarioId ?? NOT_REPORTED },
        { label: "Recorders", value: session?.recorderCount ?? NOT_REPORTED },
        { label: "Target", value: session?.targetURL ?? NOT_REPORTED },
        {
          label: "Recovery artifact export",
          value: archiveFinalizationSummary(session)
        },
        {
          label: "Archive updated",
          value: session?.archiveFinalization?.updatedAt ?? NOT_REPORTED
        },
        {
          label: "Archive error",
          value: session?.archiveFinalization?.readError ?? "-"
        },
        { label: "Updated", value: session?.updatedAt ?? NOT_REPORTED }
      ]}
    />
  );
}

function archiveFinalizationSummary(
  session: RuntimeLabSession | null | undefined
) {
  const finalization = session?.archiveFinalization;
  if (!finalization) {
    return NOT_REPORTED;
  }
  return (
    <StatusBadge tone={archiveFinalizationTone(finalization.state)}>
      {finalization.state}
    </StatusBadge>
  );
}

function archiveFinalizationTone(
  state: NonNullable<RuntimeLabSession["archiveFinalization"]>["state"]
): "success" | "warning" | "danger" | "neutral" {
  switch (state) {
    case "exported":
    case "published":
      return "success";
    case "queued":
    case "processing":
    case "retrying":
      return "warning";
    case "failed":
    case "partial":
    case "missing":
      return "danger";
    case "unavailable":
      return "neutral";
  }
}

function labStateTone(
  state: RuntimeLabSessionResponse["state"]
): "success" | "warning" | "danger" | "neutral" {
  switch (state) {
    case "loaded":
      return "success";
    case "failed":
      return "danger";
    case "unavailable":
      return "warning";
  }
}

function labSessionStateTone(
  state: RuntimeLabSession["state"]
): "success" | "warning" | "danger" | "neutral" {
  switch (state) {
    case "running":
      return "success";
    case "accepted":
    case "stopping":
      return "warning";
    case "failed":
      return "danger";
    case "stopped":
    case "finished":
    case "unavailable":
      return "neutral";
  }
}

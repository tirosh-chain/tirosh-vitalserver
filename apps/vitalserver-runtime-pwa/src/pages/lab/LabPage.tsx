import { useEffect, useMemo, useState } from "react";

import {
  useCreateLabBeds,
  useCreateLabRecorders,
  useCreateLabSession,
  useDeleteLabBeds,
  useDeleteLabRecorders,
  useLabBeds,
  useLabRecorders,
  useLabScenarios,
  useLabSession,
  useReplayLabVitalFile,
  useResetLabBeds,
  useResetLabRecorders,
  useRuntimeCapabilities,
  useStartLabSession,
  useStopLabSession
} from "@/console/hooks";
import type {
  RuntimeLabBed,
  RuntimeLabRecorder,
  RuntimeLabScenario,
  RuntimeLabSessionResponse
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";

export function LabPage() {
  const capabilities = useRuntimeCapabilities();
  const scenarios = useLabScenarios();
  const beds = useLabBeds();
  const recorders = useLabRecorders();
  const createBeds = useCreateLabBeds();
  const deleteBeds = useDeleteLabBeds();
  const resetBeds = useResetLabBeds();
  const createRecorders = useCreateLabRecorders();
  const deleteRecorders = useDeleteLabRecorders();
  const resetRecorders = useResetLabRecorders();
  const createSession = useCreateLabSession();
  const startSession = useStartLabSession();
  const stopSession = useStopLabSession();
  const replayVitalFile = useReplayLabVitalFile();

  const [selectedScenarioId, setSelectedScenarioId] = useState("");
  const [sessionName, setSessionName] = useState("Lab session");
  const [recorderCount, setRecorderCount] = useState(1);
  const [selectedSessionId, setSelectedSessionId] = useState("");
  const [bedRoomNames, setBedRoomNames] = useState("Lab-1");
  const [bedPrefix, setBedPrefix] = useState("Lab bed");
  const [deleteBedTargets, setDeleteBedTargets] = useState("");
  const [recorderBedTargets, setRecorderBedTargets] = useState("");
  const [deleteRecorderTargets, setDeleteRecorderTargets] = useState("");
  const [vitalFilePath, setVitalFilePath] = useState("");
  const [vitalReplayName, setVitalReplayName] = useState("Vital file replay");
  const [lastResponse, setLastResponse] =
    useState<RuntimeLabSessionResponse | null>(null);

  const session = useLabSession(selectedSessionId.trim() || null);
  const scenarioOptions = scenarios.data?.scenarios ?? [];
  const selectedScenario = useMemo(
    () => scenarioOptions.find((scenario) => scenario.scenarioId === selectedScenarioId),
    [scenarioOptions, selectedScenarioId]
  );

  useEffect(() => {
    if (
      selectedScenarioId.length === 0 &&
      scenarioOptions.length > 0
    ) {
      setSelectedScenarioId(scenarioOptions[0]?.scenarioId ?? "");
    }
  }, [scenarioOptions, selectedScenarioId]);

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
    replayVitalFile.isPending;
  const latestError =
    scenarios.error ??
    beds.error ??
    recorders.error ??
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
    replayVitalFile.error;
  const labCapability = capabilities.data?.canUseLab;
  const activeResponse = session.data ?? lastResponse;
  const activeSessionId = activeResponse?.session?.sessionId ?? selectedSessionId.trim();
  const canCreate =
    labCapability === true &&
    scenarios.data?.state === "loaded" &&
    selectedScenarioId.trim().length > 0 &&
    recorderCount >= 1 &&
    !isBusy;
  const canControl = labCapability === true && activeSessionId.length > 0 && !isBusy;
  const canReplay = labCapability === true && vitalFilePath.trim().length > 0 && !isBusy;
  const canCreateBeds = labCapability === true && splitList(bedRoomNames).length > 0 && !isBusy;
  const canDeleteBeds = labCapability === true && splitList(deleteBedTargets).length > 0 && !isBusy;
  const canCreateRecorders = labCapability === true && splitList(recorderBedTargets).length > 0 && !isBusy;
  const canDeleteRecorders = labCapability === true && splitList(deleteRecorderTargets).length > 0 && !isBusy;

  const create = () => {
    createSession.mutate(
      {
        scenarioId: selectedScenarioId.trim(),
        name: sessionName.trim() || null,
        recorderCount: Math.max(1, Math.trunc(recorderCount)),
        targetURL: null
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

  const replay = () => {
    replayVitalFile.mutate(
      {
        vitalFilePath: vitalFilePath.trim(),
        sessionName: vitalReplayName.trim() || null,
        targetURL: null
      },
      {
        onSuccess: (response) => {
          setLastResponse(response);
          setSelectedSessionId(response.session?.sessionId ?? "");
        }
      }
    );
  };

  const createManualBeds = () => {
    const roomNames = splitList(bedRoomNames);
    createBeds.mutate({
      count: roomNames.length,
      roomNames,
      prefix: bedPrefix.trim() || null,
      targetURL: null
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
            { label: "Scenarios", value: scenarioOptions.length },
            { label: "Read error", value: scenarios.data?.readError ?? "-" },
            { label: "Selected", value: selectedScenario?.name ?? NOT_REPORTED }
          ]}
        />
        {latestError ? <ErrorState title="Lab operation failed" error={latestError} /> : null}
      </Panel>

      <Panel
        title="Scenario session"
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
        title="Session control"
        actions={
          <>
            <button type="button" disabled={!canControl} onClick={start}>
              Start
            </button>
            <button type="button" disabled={!canControl} onClick={stop}>
              Stop
            </button>
          </>
        }
      >
        <div className="settings-grid">
          <label className="full-width">
            Session ID
            <input
              type="text"
              value={selectedSessionId}
              onChange={(event) => setSelectedSessionId(event.target.value)}
            />
          </label>
        </div>
        <LabResponseSummary response={activeResponse} />
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
        title="Vital file replay"
        actions={
          <button
            type="button"
            className="ui-button-primary"
            disabled={!canReplay}
            onClick={replay}
          >
            Replay
          </button>
        }
      >
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
            Vital file path
            <input
              type="text"
              value={vitalFilePath}
              onChange={(event) => setVitalFilePath(event.target.value)}
            />
          </label>
        </div>
      </Panel>
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
        { label: "Updated", value: session?.updatedAt ?? NOT_REPORTED }
      ]}
    />
  );
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

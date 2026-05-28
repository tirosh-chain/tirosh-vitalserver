import { useEffect, useMemo, useState } from "react";

import {
  useCreateTestKitBeds,
  useDeleteTestKitBeds,
  useDeleteTestKitOrphanVRecorder,
  useResetTestKitBeds,
  useResetTestKitVirtualRecorders,
  useRestartTestKitVirtualRecorders,
  useSessionTestKitAction,
  useStartTestKitVirtualRecorders,
  useTestKitStatus
} from "../../application/runtime-control/queries";
import type { RuntimeTestKitSession } from "../../domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "../../domain/runtime-control/formatting/bytes";
import { ErrorState } from "../../shared/ui/ErrorState";
import { KeyValueRows } from "../../shared/ui/KeyValueRows";
import { Panel } from "../../shared/ui/Panel";

export function TestKitPage() {
  const status = useTestKitStatus();
  const createBeds = useCreateTestKitBeds();
  const deleteBeds = useDeleteTestKitBeds();
  const resetBeds = useResetTestKitBeds();
  const startSession = useStartTestKitVirtualRecorders();
  const restartSession = useRestartTestKitVirtualRecorders();
  const resetSessions = useResetTestKitVirtualRecorders();
  const deleteOrphan = useDeleteTestKitOrphanVRecorder();
  const stopSession = useSessionTestKitAction("stop");
  const pauseSession = useSessionTestKitAction("pause");
  const resumeSession = useSessionTestKitAction("resume");
  const deleteSession = useSessionTestKitAction("delete");

  const [bedCount, setBedCount] = useState(1);
  const [bedPrefix, setBedPrefix] = useState("testkit-bed");
  const [selectedBeds, setSelectedBeds] = useState<string[]>([]);
  const [recorders, setRecorders] = useState(1);
  const [scenario, setScenario] = useState("normal");
  const [signalProfile, setSignalProfile] = useState("normal");
  const [vrcode, setVrcode] = useState(generateVrcode());
  const [intervalSeconds, setIntervalSeconds] = useState(1);
  const [orphanVrcode, setOrphanVrcode] = useState("");

  const beds = status.data?.beds ?? [];
  const sessions = status.data?.sessions ?? [];

  useEffect(() => {
    setSelectedBeds((current) =>
      current.filter((roomName) =>
        beds.some((bed) => bed.roomName === roomName)
      )
    );
  }, [beds]);

  const isBusy =
    createBeds.isPending ||
    deleteBeds.isPending ||
    resetBeds.isPending ||
    startSession.isPending ||
    restartSession.isPending ||
    resetSessions.isPending ||
    deleteOrphan.isPending ||
    stopSession.isPending ||
    pauseSession.isPending ||
    resumeSession.isPending ||
    deleteSession.isPending;

  const latestError =
    status.error ??
    createBeds.error ??
    deleteBeds.error ??
    resetBeds.error ??
    startSession.error ??
    restartSession.error ??
    resetSessions.error ??
    deleteOrphan.error ??
    stopSession.error ??
    pauseSession.error ??
    resumeSession.error ??
    deleteSession.error;

  const canStart = selectedBeds.length >= recorders && !isBusy;

  const start = () => {
    startSession.mutate(
      {
        scenario: scenario as "normal",
        signalProfile: signalProfile as "normal",
        recorders,
        bedRoomNames: selectedBeds.slice(0, recorders),
        vrcode: vrcode.trim() || null,
        version: "testkit",
        intervalSeconds,
        durationSeconds: null,
        maxMessages: null,
        shiftTime: true,
        generateFrames: true
      },
      {
        onSuccess: () => setVrcode(generateVrcode())
      }
    );
  };

  return (
    <div className="page-stack">
      <Panel
        title="TestKit virtual recorders"
        actions={
          <button
            type="button"
            disabled={status.isFetching}
            onClick={() => status.refetch()}
          >
            Refresh
          </button>
        }
      >
        <KeyValueRows
          rows={[
            { label: "Enabled", value: String(status.data?.enabled ?? false) },
            { label: "Status", value: status.data?.state ?? "Unknown" },
            { label: "Service", value: status.data?.serviceName ?? "-" },
            { label: "URL", value: status.data?.apiBaseURL ?? "-" },
            { label: "Target", value: status.data?.recorderTargetURL ?? "-" },
            { label: "Sessions", value: sessions.length },
            { label: "Beds", value: beds.length },
            { label: "Last error", value: status.data?.lastError ?? "-" }
          ]}
        />
        {latestError ? (
          <ErrorState title="TestKit operation failed" error={latestError} />
        ) : null}
      </Panel>

      <Panel
        title="Bed setup"
        actions={
          <>
            <button
              type="button"
              disabled={isBusy}
              onClick={() => createBeds.mutate({ count: bedCount, prefix: bedPrefix })}
            >
              Create
            </button>
            <button
              type="button"
              disabled={isBusy || selectedBeds.length === 0}
              onClick={() => deleteBeds.mutate(selectedBeds)}
            >
              Delete selected
            </button>
            <button
              type="button"
              disabled={isBusy || beds.length === 0}
              onClick={() => resetBeds.mutate(undefined)}
            >
              Reset
            </button>
          </>
        }
      >
        <div className="settings-grid">
          <label>
            Beds
            <input
              type="number"
              min="1"
              value={bedCount}
              onChange={(event) => setBedCount(Number(event.target.value))}
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
        </div>
        <BedSelection
          beds={beds}
          selectedBeds={selectedBeds}
          setSelectedBeds={setSelectedBeds}
        />
      </Panel>

      <Panel title="Virtual VRecorder session">
        <div className="settings-grid">
          <label>
            Scenario
            <select
              value={scenario}
              onChange={(event) => setScenario(event.target.value)}
            >
              {scenarioOptions.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
          </label>
          <label>
            Signal
            <select
              value={signalProfile}
              onChange={(event) => setSignalProfile(event.target.value)}
            >
              {signalOptions.map((option) => (
                <option key={option} value={option}>
                  {option}
                </option>
              ))}
            </select>
          </label>
          <label>
            VRecorders
            <input
              type="number"
              min="1"
              value={recorders}
              onChange={(event) => setRecorders(Number(event.target.value))}
            />
          </label>
          <label>
            Interval seconds
            <input
              type="number"
              min="0.1"
              step="0.1"
              value={intervalSeconds}
              onChange={(event) => setIntervalSeconds(Number(event.target.value))}
            />
          </label>
          <label>
            VRecorder code
            <input
              type="text"
              value={vrcode}
              onChange={(event) => setVrcode(event.target.value)}
            />
          </label>
        </div>
        <div className="action-row">
          <button type="button" disabled={!canStart} onClick={start}>
            Start
          </button>
          <button
            type="button"
            disabled={isBusy || sessions.length === 0}
            onClick={() => resetSessions.mutate(undefined)}
          >
            Reset sessions
          </button>
        </div>
        <p className="muted">
          {selectedBeds.length} selected / {recorders} required / {beds.length}{" "}
          available
        </p>
      </Panel>

      <Panel title="Sessions">
        {sessions.length === 0 ? (
          <p className="empty-state">No virtual recorder sessions.</p>
        ) : (
          <div className="session-list">
            {sessions.map((session) => (
              <SessionRow
                key={session.id}
                session={session}
                selectedBeds={selectedBeds}
                disabled={isBusy}
                onStop={() => stopSession.mutate(session.id)}
                onPause={() => pauseSession.mutate(session.id)}
                onResume={() => resumeSession.mutate(session.id)}
                onRestart={() =>
                  restartSession.mutate({
                    sessionID: session.id,
                    bedRoomNames: selectedBeds.slice(
                      0,
                      Math.max(1, session.recordersRequested)
                    )
                  })
                }
                onDelete={() => deleteSession.mutate(session.id)}
              />
            ))}
          </div>
        )}
      </Panel>

      <Panel title="Orphan cleanup">
        <div className="inline-form">
          <label>
            Orphan VRecorder code
            <input
              type="text"
              value={orphanVrcode}
              onChange={(event) => setOrphanVrcode(event.target.value)}
            />
          </label>
          <button
            type="button"
            disabled={isBusy || !orphanVrcode.trim()}
            onClick={() => deleteOrphan.mutate(orphanVrcode)}
          >
            Delete VRecorder
          </button>
        </div>
      </Panel>
    </div>
  );
}

function BedSelection({
  beds,
  selectedBeds,
  setSelectedBeds
}: {
  beds: Array<{ roomName: string; bedId: string }>;
  selectedBeds: string[];
  setSelectedBeds: (value: string[]) => void;
}) {
  if (beds.length === 0) {
    return <p className="empty-state">Create beds before starting VRecorders.</p>;
  }

  return (
    <div className="check-list">
      {beds.map((bed) => {
        const checked = selectedBeds.includes(bed.roomName);
        return (
          <label key={bed.roomName} className="checkbox-label">
            <input
              type="checkbox"
              checked={checked}
              onChange={(event) => {
                setSelectedBeds(
                  event.target.checked
                    ? [...selectedBeds, bed.roomName]
                    : selectedBeds.filter((roomName) => roomName !== bed.roomName)
                );
              }}
            />
            <span>
              <strong>{bed.roomName}</strong>
              <span className="muted">{bed.bedId}</span>
            </span>
          </label>
        );
      })}
    </div>
  );
}

function SessionRow({
  session,
  selectedBeds,
  disabled,
  onStop,
  onPause,
  onResume,
  onRestart,
  onDelete
}: {
  session: RuntimeTestKitSession;
  selectedBeds: string[];
  disabled: boolean;
  onStop: () => void;
  onPause: () => void;
  onResume: () => void;
  onRestart: () => void;
  onDelete: () => void;
}) {
  const canRestart =
    session.state === "stopped" &&
    selectedBeds.length >= Math.max(1, session.recordersRequested);

  return (
    <div className="session-row">
      <div>
        <strong>{session.vrcode ?? session.id}</strong>
        <span className="muted">
          {session.state} · {session.recordersRequested} recorder(s) ·{" "}
          {formatBytes(session.bytesSent)} · {session.messagesSent} messages
        </span>
        {session.lastError ? (
          <span className="error-state">{session.lastError}</span>
        ) : null}
      </div>
      <div className="action-row">
        <button type="button" disabled={disabled} onClick={onPause}>
          Pause
        </button>
        <button type="button" disabled={disabled} onClick={onResume}>
          Resume
        </button>
        <button type="button" disabled={disabled} onClick={onStop}>
          Stop
        </button>
        <button type="button" disabled={disabled || !canRestart} onClick={onRestart}>
          Restart
        </button>
        <button type="button" disabled={disabled} onClick={onDelete}>
          Delete
        </button>
      </div>
    </div>
  );
}

const scenarioOptions = [
  "normal",
  "multiple_recorders",
  "burst_traffic",
  "disconnect_reconnect",
  "stale_recorder",
  "signal_anomaly"
];

const signalOptions = [
  "normal",
  "tachycardia",
  "desaturation",
  "artifact",
  "device_disconnect"
];

function generateVrcode(): string {
  return `VR_${Math.random().toString(16).slice(2, 10).toUpperCase()}`;
}

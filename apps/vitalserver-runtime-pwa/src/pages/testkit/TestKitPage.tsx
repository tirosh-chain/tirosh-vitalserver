import { useEffect, useState } from "react";

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
} from "@/console/hooks";
import type { RuntimeTestKitSession } from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "@/domain/runtime-control/formatting/bytes";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { Panel } from "@/components/Panel";

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
  const [scenario, setScenario] = useState<TestKitScenario>("normal");
  const [signalProfile, setSignalProfile] = useState<TestKitSignalProfile>("normal");
  const [vrcode, setVrcode] = useState(generateVrcode());
  const [intervalSeconds, setIntervalSeconds] = useState(1);
  const [orphanVrcode, setOrphanVrcode] = useState("");

  const beds = status.data?.beds ?? null;
  const sessions = status.data?.sessions ?? null;

  useEffect(() => {
    if (beds === null) {
      return;
    }
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

  const testKitReady = status.data?.enabled === true && status.data.state === "running";
  const canMutateTestKit = testKitReady && !isBusy;
  const canStart =
    testKitReady &&
    beds !== null &&
    selectedBeds.length >= recorders &&
    !isBusy;

  const start = () => {
    startSession.mutate(
      {
        scenario,
        signalProfile,
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
            { label: "Enabled", value: formatEnabled(status.data?.enabled) },
            { label: "Status", value: status.data?.state ?? NOT_REPORTED },
            { label: "Service", value: status.data?.serviceName ?? NOT_REPORTED },
            { label: "URL", value: status.data?.apiBaseURL ?? NOT_REPORTED },
            { label: "Target", value: status.data?.recorderTargetURL ?? NOT_REPORTED },
            { label: "Sessions", value: sessions?.length ?? NOT_REPORTED },
            { label: "Beds", value: beds?.length ?? NOT_REPORTED },
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
              disabled={!canMutateTestKit}
              onClick={() => createBeds.mutate({ count: bedCount, prefix: bedPrefix })}
            >
              Create
            </button>
            <button
              type="button"
              disabled={!canMutateTestKit || selectedBeds.length === 0}
              onClick={() => deleteBeds.mutate(selectedBeds)}
            >
              Delete selected
            </button>
            <button
              type="button"
              disabled={!canMutateTestKit || beds === null || beds.length === 0}
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
              onChange={(event) => {
                if (isTestKitScenario(event.target.value)) {
                  setScenario(event.target.value);
                }
              }}
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
              onChange={(event) => {
                if (isTestKitSignalProfile(event.target.value)) {
                  setSignalProfile(event.target.value);
                }
              }}
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
            disabled={!canMutateTestKit || sessions === null || sessions.length === 0}
            onClick={() => resetSessions.mutate(undefined)}
          >
            Reset sessions
          </button>
        </div>
        <p className="muted">
          {selectedBeds.length} selected / {recorders} required /{" "}
          {beds === null ? NOT_REPORTED : beds.length} available
        </p>
      </Panel>

      <Panel title="Sessions">
        {sessions === null ? (
          <p className="empty-state">TestKit session state is not reported.</p>
        ) : sessions.length === 0 ? (
          <p className="empty-state">No virtual recorder sessions.</p>
        ) : (
          <div className="session-list">
            {sessions.map((session) => (
              <SessionRow
                key={session.id}
                session={session}
                selectedBeds={selectedBeds}
                disabled={!canMutateTestKit}
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
            disabled={!canMutateTestKit || !orphanVrcode.trim()}
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
  beds: Array<{ roomName: string; bedId: string }> | null;
  selectedBeds: string[];
  setSelectedBeds: (value: string[]) => void;
}) {
  if (beds === null) {
    return <p className="empty-state">TestKit bed state is not reported.</p>;
  }
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
] as const;

type TestKitScenario = (typeof scenarioOptions)[number];

const signalOptions = [
  "normal",
  "tachycardia",
  "desaturation",
  "artifact",
  "device_disconnect"
] as const;

type TestKitSignalProfile = (typeof signalOptions)[number];

function isTestKitScenario(value: string): value is TestKitScenario {
  return scenarioOptions.includes(value as TestKitScenario);
}

function isTestKitSignalProfile(value: string): value is TestKitSignalProfile {
  return signalOptions.includes(value as TestKitSignalProfile);
}

function formatEnabled(value: boolean | null | undefined): string {
  if (value === true) {
    return "true";
  }
  if (value === false) {
    return "false";
  }
  return NOT_REPORTED;
}

function generateVrcode(): string {
  return `VR_${Math.random().toString(16).slice(2, 10).toUpperCase()}`;
}

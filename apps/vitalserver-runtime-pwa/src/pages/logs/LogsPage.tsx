import { useEffect, useRef, useState } from "react";

import {
  useCreatePlatformSupportExport,
  useHostLogs,
  useControlCapabilities,
  usePlatformWorkflow
} from "@/console/hooks";
import type { RuntimeLogSource } from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { ErrorState } from "@/components/ErrorState";
import { Panel } from "@/components/Panel";

const logSources: Array<{ id: RuntimeLogSource; label: string }> = [
  { id: "helperMessage", label: "Helper message" },
  { id: "install", label: "Install log" },
  { id: "command", label: "Command log" },
  { id: "launcher", label: "VM launcher" },
  { id: "vmLaunchOutput", label: "VM launch output" },
  { id: "vmLaunchError", label: "VM launch error" },
  { id: "proxyOutput", label: "Host proxy output" },
  { id: "proxyError", label: "Host proxy error" },
  { id: "watchdog", label: "Watchdog" },
  { id: "updateActivation", label: "Update activation" },
  { id: "containers", label: "Containers" }
];

const lineLimits = [100, 500, 1000];
export function LogsPage() {
  const [source, setSource] = useState<RuntimeLogSource>("containers");
  const [lineLimit, setLineLimit] = useState(500);
  const [live, setLive] = useState(true);
  const outputRef = useRef<HTMLPreElement>(null);

  const capabilities = useControlCapabilities();
  const logs = useHostLogs({ source, lineLimit, live });
  const exportLogs = useCreatePlatformSupportExport();
  const workflow = usePlatformWorkflow();
  const logText = logs.data?.text ?? null;
  const capabilityData = capabilities.data ?? null;
  const canExportLogs =
    !capabilities.isPending &&
    !capabilities.isError &&
    capabilityData !== null &&
    capabilityData.canExportLogs === true;
  const exportCapabilityMissing =
    !capabilities.isPending &&
    !capabilities.isError &&
    (capabilityData === null || capabilityData.canExportLogs === undefined);
  const exportUnsupported =
    !capabilities.isPending &&
    !capabilities.isError &&
    capabilityData !== null &&
    capabilityData.canExportLogs === false;
  const supportOperation =
    workflow.data?.operation?.kind === "support-export"
      ? workflow.data.operation
      : exportLogs.data?.kind === "support-export"
        ? exportLogs.data
        : null;

  useEffect(() => {
    if (live && outputRef.current) {
      outputRef.current.scrollTop = outputRef.current.scrollHeight;
    }
  }, [live, logText]);

  return (
    <div className="page-stack">
      <Panel
        title="Log"
        actions={
          <button
            type="button"
            onClick={() => logs.refetch()}
            disabled={logs.isFetching}
          >
            Refresh
          </button>
        }
      >
        <div className="log-toolbar">
          <label>
            Source
            <select
              value={source}
              onChange={(event) =>
                setSource(event.target.value as RuntimeLogSource)
              }
            >
              {logSources.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>
          <label>
            Lines
            <select
              value={lineLimit}
              onChange={(event) => setLineLimit(Number(event.target.value))}
            >
              {lineLimits.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </label>
          <label className="checkbox-label">
            <input
              type="checkbox"
              checked={live}
              onChange={(event) => setLive(event.target.checked)}
            />
            Live
          </label>
          <span className={live ? "live-state live-state-on" : "live-state"}>
            {live ? "Live" : "Paused"}
          </span>
        </div>

        {logs.isPending ? (
          <p className="empty-state">Loading logs...</p>
        ) : logs.isError ? (
          <ErrorState title="Failed to read logs" error={logs.error} />
        ) : logText === null ? (
          <ErrorState
            title="Log response is incomplete"
            error={new Error("Runtime Control API did not return log text.")}
          />
        ) : (
          <pre ref={outputRef} className="log-output">
            {logText || "No log lines are available for this source."}
          </pre>
        )}
      </Panel>

      <Panel title="Export logs">
        <div className="inline-form">
          <button
            type="button"
            onClick={() => exportLogs.mutate()}
            disabled={exportLogs.isPending || !canExportLogs}
          >
            Create Support Bundle
          </button>
        </div>
        {capabilities.isPending ? (
          <p className="empty-state">Loading export capability...</p>
        ) : null}
        {capabilities.isError ? (
          <ErrorState
            title="Failed to read export capability"
            error={capabilities.error}
          />
        ) : null}
        {exportCapabilityMissing ? (
          <ErrorState
            title="Export capability response is incomplete"
            error={
              new Error(
                "Runtime Control API did not return log export capability."
              )
            }
          />
        ) : null}
        {exportUnsupported ? (
          <p className="muted">
            Log export is not supported by this Runtime Control API.
          </p>
        ) : null}
        {exportLogs.isError ? (
          <ErrorState title="Failed to create support bundle" error={exportLogs.error} />
        ) : null}
        {supportOperation?.state === "completed" && supportOperation.artifact ? (
          <p className="muted">
            Created {supportOperation.artifact.path} ({supportOperation.artifact.sizeBytes} bytes, SHA-256 {supportOperation.artifact.sha256})
          </p>
        ) : supportOperation?.state === "failed" ? (
          <p className="error-state">
            Support export failed: {supportOperation.failure?.message ?? "failure evidence is missing"}
          </p>
        ) : supportOperation ? (
          <p className="muted">
            Support export {supportOperation.state} (operation {supportOperation.operationId}).
          </p>
        ) : (
          <p className="muted">
            The Platform Agent creates the archive in its managed support directory and publishes its path and digest after completion.
          </p>
        )}
      </Panel>
    </div>
  );
}

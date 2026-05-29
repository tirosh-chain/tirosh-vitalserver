import { useEffect, useMemo, useRef, useState } from "react";

import {
  useExportHostLogs,
  useHostLogs,
  useRuntimeCapabilities
} from "@/application/runtime-control/queries";
import type { RuntimeLogSource } from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { ErrorState } from "@/shared/ui/ErrorState";
import { Panel } from "@/shared/ui/Panel";

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
const defaultExportPath = "/tmp/vitalserver-logs.zip";

export function LogsPage() {
  const [source, setSource] = useState<RuntimeLogSource>("containers");
  const [lineLimit, setLineLimit] = useState(500);
  const [live, setLive] = useState(true);
  const [exportPath, setExportPath] = useState(defaultExportPath);
  const outputRef = useRef<HTMLPreElement>(null);

  const capabilities = useRuntimeCapabilities();
  const logs = useHostLogs({ source, lineLimit, live });
  const exportLogs = useExportHostLogs();
  const logText = logs.data?.text ?? "";

  const exportDestination = useMemo(() => {
    const destination = exportLogs.data?.destination;
    return destination ? destination.replace(/^file:\/\//, "") : "";
  }, [exportLogs.data?.destination]);

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

        {logs.isError ? (
          <ErrorState title="Failed to read logs" error={logs.error} />
        ) : (
          <pre ref={outputRef} className="log-output">
            {logText || "No log lines are available for this source."}
          </pre>
        )}
      </Panel>

      <Panel title="Export logs">
        <div className="inline-form">
          <label>
            Destination
            <input
              type="text"
              value={exportPath}
              disabled={capabilities.data?.canExportLogs !== true}
              onChange={(event) => setExportPath(event.target.value)}
            />
          </label>
          <button
            type="button"
            onClick={() => exportLogs.mutate(exportPath)}
            disabled={
              exportLogs.isPending ||
              !exportPath.trim() ||
              capabilities.data?.canExportLogs !== true
            }
          >
            Export Logs
          </button>
        </div>
        {exportLogs.isError ? (
          <ErrorState title="Failed to export logs" error={exportLogs.error} />
        ) : null}
        {exportDestination ? (
          <p className="muted">Exported to {exportDestination}</p>
        ) : (
          <p className="muted">
            The archive is created on the Mac running Runtime Control API. The
            Remote Console cannot open Finder directly; use the exported path on
            the host.
          </p>
        )}
      </Panel>
    </div>
  );
}

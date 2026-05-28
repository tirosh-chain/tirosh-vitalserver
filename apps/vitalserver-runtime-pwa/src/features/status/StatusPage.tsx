import { useRuntimeOverview } from "../../application/runtime-control/queries";
import type { RuntimeControlOverview } from "../../domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "../../domain/runtime-control/formatting/bytes";
import {
  formatRuntimeState,
  runtimeStateTone
} from "../../domain/runtime-control/formatting/runtimeState";
import { formatLocalDateTime, formatUptimeSince } from "../../domain/runtime-control/formatting/time";
import { KeyValueRows } from "../../shared/ui/KeyValueRows";
import { Panel } from "../../shared/ui/Panel";
import { StatusBadge } from "../../shared/ui/StatusBadge";

export function StatusPage() {
  const overviewQuery = useRuntimeOverview();

  if (overviewQuery.isPending) {
    return <Panel title="Status">Loading runtime overview...</Panel>;
  }

  if (overviewQuery.isError) {
    return (
      <Panel title="Status">
        <p className="error-state">
          Runtime Control API is not reachable. Confirm the macOS Helper is
          running on 127.0.0.1:18321.
        </p>
      </Panel>
    );
  }

  return <StatusOverview overview={overviewQuery.data} />;
}

function StatusOverview({ overview }: { overview: RuntimeControlOverview }) {
  const status = overview.status;
  const state = status?.runtimeState;
  const stats = status?.dataDirectoryStats;
  const vitalRecorder = overview.vitalRecorder;

  return (
    <div className="page-stack">
      <Panel title="Runtime">
        <KeyValueRows
          rows={[
            {
              label: "Overall health",
              value: (
                <StatusBadge tone={runtimeStateTone(state)}>
                  {formatRuntimeState(state)}
                </StatusBadge>
              )
            },
            {
              label: "VitalServer",
              value: status?.hostProxyHTTP ?? "Unknown",
              detail: formatUptimeSince(status?.startedAt)
            },
            {
              label: "Data directory",
              value: overview.settings?.vitalFilesDirectory ?? "Unknown",
              detail: stats
                ? `${stats.fileCount ?? 0} files · ${formatBytes(stats.sizeBytes)}`
                : "Unknown"
            },
            {
              label: "Observation updated",
              value: formatLocalDateTime(vitalRecorder?.observedAt)
            }
          ]}
        />
      </Panel>

      <Panel title="Vital Recorder">
        <KeyValueRows
          rows={[
            {
              label: "Active recorder connections",
              value: vitalRecorder?.activeConnections ?? 0
            },
            {
              label: "Known recorders",
              value: vitalRecorder?.knownRecorders ?? 0
            },
            {
              label: "Online recorders",
              value: vitalRecorder?.onlineRecorders ?? 0
            },
            {
              label: "Stale recorders",
              value: vitalRecorder?.staleRecorders ?? 0
            },
            {
              label: "Known beds",
              value: vitalRecorder?.knownBeds ?? 0
            },
            {
              label: "Recorder anomalies",
              value: vitalRecorder?.recorderAnomalies ?? 0
            }
          ]}
        />
      </Panel>

      <Panel title="Resource usage">
        <KeyValueRows
          rows={[
            {
              label: "CPU",
              value:
                status?.cpuUsagePercent === null ||
                status?.cpuUsagePercent === undefined
                  ? "Unknown"
                  : `${Math.round(status.cpuUsagePercent)}%`
            },
            {
              label: "Memory available to VM",
              value: formatResourceUsage(status?.memory)
            },
            {
              label: "VM disk",
              value: formatResourceUsage(status?.systemDisk)
            },
            {
              label: "Data storage",
              value: formatResourceUsage(status?.dataStorage)
            }
          ]}
        />
      </Panel>
    </div>
  );
}

function formatResourceUsage(value: unknown): string {
  if (!value || typeof value !== "object") {
    return "Unknown";
  }

  const record = value as Record<string, unknown>;
  const usedBytes = numberValue(record.usedBytes);
  const totalBytes = numberValue(record.totalBytes);
  const availableBytes = numberValue(record.availableBytes);

  if (usedBytes !== undefined && totalBytes !== undefined) {
    return `${formatBytes(usedBytes)} / ${formatBytes(totalBytes)}`;
  }
  if (availableBytes !== undefined && totalBytes !== undefined) {
    return `${formatBytes(availableBytes)} / ${formatBytes(totalBytes)}`;
  }
  return "Unknown";
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
}

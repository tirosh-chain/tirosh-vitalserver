import { useRuntimeOverview } from "@/console/hooks";
import type { RuntimeControlOverview } from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "@/domain/runtime-control/formatting/bytes";
import {
  formatHTTPStatus,
  runtimeURL,
  sameHostRuntimeURL
} from "@/domain/runtime-control/formatting/http";
import {
  formatRuntimeState,
  runtimeStateTone
} from "@/domain/runtime-control/formatting/runtimeState";
import {
  formatLocalDateTime,
  formatUptimeSince
} from "@/domain/runtime-control/formatting/time";
import {
  formatVitalRecorderConnectionMetric,
  formatVitalRecorderObservationMetric
} from "@/domain/runtime-control/formatting/vitalRecorder";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";

export function StatusPage() {
  const overviewQuery = useRuntimeOverview();

  if (overviewQuery.isPending) {
    return <Panel title="Status">Loading runtime overview...</Panel>;
  }

  if (overviewQuery.isError) {
    return (
      <Panel title="Status">
        <ErrorState error={overviewQuery.error} />
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
  const browserHostname = currentBrowserHostname();
  const vitalServerURL = advertisedVitalServerURL(overview, browserHostname);
  const remoteConsoleURL = advertisedRemoteConsoleURL(overview, browserHostname);

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
            ...(status?.statusDocumentError
              ? [
                  {
                    label: "Status document",
                    value: "Read failed",
                    detail: status.statusDocumentError
                  }
                ]
              : []),
            ...(status?.guestRuntimeStateError
              ? [
                  {
                    label: "Guest runtime state",
                    value: "Read failed",
                    detail: status.guestRuntimeStateError
                  }
                ]
              : []),
            {
              label: "VitalServer",
              value: vitalServerURL ? (
                <a href={vitalServerURL} target="_blank" rel="noreferrer">
                  {vitalServerURL}
                </a>
              ) : (
                NOT_REPORTED
              ),
              detail: serviceStatusDetail(
                status?.hostProxyHTTP,
                status?.startedAt
              )
            },
            {
              label: "Remote Console",
              value: remoteConsoleURL ? (
                <a href={remoteConsoleURL} target="_blank" rel="noreferrer">
                  {remoteConsoleURL}
                </a>
              ) : (
                NOT_REPORTED
              ),
              detail: serviceStatusDetail(
                status?.runtimeControlHTTP,
                status?.runtimeControlStartedAt
              )
            },
            {
              label: "Data directory",
              value: overview.settings?.vitalFilesDirectory ?? NOT_REPORTED,
              detail: formatDataDirectoryStats(
                stats,
                status?.dataDirectoryStatsError
              )
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
              value: formatVitalRecorderConnectionMetric(vitalRecorder)
            },
            {
              label: "Known recorders",
              value: formatVitalRecorderObservationMetric(
                vitalRecorder,
                "knownRecorders"
              )
            },
            {
              label: "Online recorders",
              value: formatVitalRecorderObservationMetric(
                vitalRecorder,
                "onlineRecorders"
              )
            },
            {
              label: "Stale recorders",
              value: formatVitalRecorderObservationMetric(
                vitalRecorder,
                "staleRecorders"
              )
            },
            {
              label: "Known beds",
              value: formatVitalRecorderObservationMetric(
                vitalRecorder,
                "knownBeds"
              )
            },
            {
              label: "Recorder anomalies",
              value: formatVitalRecorderObservationMetric(
                vitalRecorder,
                "recorderAnomalies"
              )
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
                  ? NOT_REPORTED
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

function advertisedVitalServerURL(
  overview: RuntimeControlOverview,
  browserHostname: string | undefined
): string | null {
  const advertised = overview.settings?.vitalServerURL?.trim();
  if (advertised) {
    return advertised;
  }
  if (!overview.settings) {
    return null;
  }
  if (!overview.settings.publicHost.trim()) {
    return sameHostRuntimeURL({
      hostname: browserHostname,
      port: overview.settings.publicPort
    });
  }
  return runtimeURL({
    host: overview.settings.publicHost,
    port: overview.settings.publicPort
  });
}

function advertisedRemoteConsoleURL(
  overview: RuntimeControlOverview,
  browserHostname: string | undefined
): string | null {
  const advertised = overview.settings?.remoteConsoleURL?.trim();
  if (advertised) {
    return advertised;
  }
  if (typeof overview.settings?.runtimeControlPort !== "number") {
    return null;
  }
  return sameHostRuntimeURL({
    hostname: browserHostname,
    port: overview.settings.runtimeControlPort
  });
}

function currentBrowserHostname(): string | undefined {
  return globalThis.location?.hostname;
}

function serviceStatusDetail(
  httpStatus: string | null | undefined,
  startedAt: string | null | undefined
): string {
  return [formatHTTPStatus(httpStatus), formatUptimeSince(startedAt)]
    .filter((part) => part && part !== "-")
    .join(" ");
}

function formatDataDirectoryStats(
  stats: unknown,
  readError: string | null | undefined
): string {
  if (readError) {
    return `Read failed: ${readError}`;
  }
  if (!stats || typeof stats !== "object") {
    return NOT_REPORTED;
  }
  const record = stats as Record<string, unknown>;
  const fileCount = numberValue(record.fileCount);
  const sizeBytes = numberValue(record.sizeBytes);
  const fileCountText =
    fileCount === undefined ? "File count not reported" : `${fileCount} files`;
  const sizeText = sizeBytes === undefined ? "Size not reported" : formatBytes(sizeBytes);
  return `${fileCountText} · ${sizeText}`;
}

function formatResourceUsage(value: unknown): string {
  if (value === null || value === undefined) {
    return NOT_REPORTED;
  }
  if (typeof value !== "object") {
    return "Invalid resource usage";
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
  return "Incomplete resource usage";
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
}

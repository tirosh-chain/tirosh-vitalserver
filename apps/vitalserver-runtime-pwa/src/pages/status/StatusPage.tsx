import {
  usePlatformState,
  useRuntimePlatformSettings,
  useRuntimeProductSettings,
  useRuntimeStack,
  useVitalDBRecorders
} from "@/console/hooks";
import type {
  PlatformState,
  RuntimeProductSettings,
  VitalDBRecorders
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
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
  formatVitalRecorderObservationMetric,
  vitalRecorderSummaryFromHistory
} from "@/domain/runtime-control/formatting/vitalRecorder";
import { formatRecorderIngressStatusReadState } from "@/domain/runtime-control/formatting/recorderIngress";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import { ErrorState } from "@/components/ErrorState";
import { KeyValueRows } from "@/components/KeyValueRows";
import { Panel } from "@/components/Panel";
import { StatusBadge } from "@/components/StatusBadge";

type RuntimeRecorderIngressStatusRead = NonNullable<
  VitalDBRecorders["recorderIngressStatusRead"]
>;
type RuntimeRecorderIngressStatus = NonNullable<
  RuntimeRecorderIngressStatusRead["document"]
>;
type RuntimeRecorderIngressSpool = RuntimeRecorderIngressStatus["spool"];
type RuntimeRecorderIngressReplay = RuntimeRecorderIngressStatus["replay"];
type RuntimeRecorderIngressThroughput = RuntimeRecorderIngressStatus["throughput"];
type RuntimeRecorderIngressRawArchive = RuntimeRecorderIngressStatus["rawArchive"];
type RuntimeRecorderIngressFailure = {
  reason?: string | null;
  message?: string | null;
};

export function StatusPage() {
  const platformStateQuery = usePlatformState();

  if (platformStateQuery.isPending) {
    return <Panel title="Status">Loading platform state...</Panel>;
  }

  if (platformStateQuery.isError) {
    return (
      <Panel title="Status">
        <ErrorState error={platformStateQuery.error} />
      </Panel>
    );
  }

  return <StatusOverview platformState={platformStateQuery.data} />;
}

function StatusOverview({
  platformState
}: {
  platformState: PlatformState;
}) {
  const status = platformState;
  const runtimeStackQuery = useRuntimeStack();
  const runtimeStack = runtimeStackQuery.data;
  const state = status?.platformHealth;
  const stats = status?.dataDirectoryStats;
  const recordersQuery = useVitalDBRecorders();
  const platformSettingsQuery = useRuntimePlatformSettings();
  const platformSettingsRead = platformSettingsQuery.data;
  const runtimeSettingsQuery = useRuntimeProductSettings();
  const runtimeSettings =
    runtimeSettingsQuery.data?.state === "loaded"
      ? runtimeSettingsQuery.data.settings ?? undefined
      : undefined;
  const recorderIngressStatusRead =
    recordersQuery.data?.recorderIngressStatusRead ?? null;
  const recorderIngressStatus = recorderIngressStatusRead?.document ?? null;
  const vitalRecorder = vitalRecorderSummaryFromHistory(recordersQuery.data);
  const browserHostname = currentBrowserHostname();
  const vitalServerURL = advertisedVitalServerURL(runtimeSettings, browserHostname);
  const remoteConsoleURL = advertisedRemoteConsoleURL(runtimeSettings, browserHostname);
  const recorderIngressDetailRows = recorderIngressDetails(recorderIngressStatus);
  const dataDirectory = dataDirectoryPresentation(
    platformSettingsQuery,
    platformSettingsRead
  );

  return (
    <div className="page-stack">
      <Panel title="Runtime">
        <KeyValueRows
          rows={[
            {
              label: "Platform health",
              value: (
                <StatusBadge tone={runtimeStateTone(state)}>
                  {formatRuntimeState(state)}
                </StatusBadge>
              )
            },
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
                status?.publicProxyHTTP,
                status?.platformAPIStartedAt
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
                status?.platformAPIHTTP,
                status?.platformAPIStartedAt
              )
            },
            {
              label: "Data directory",
              value: dataDirectory.value,
              detail: joinDetails(
                dataDirectory.detail,
                formatDataDirectoryStats(
                  stats,
                  status?.dataDirectoryStatsError
                )
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
              label: "Recorder ingress queue",
              value: recorderIngressQueueStatus(recorderIngressStatusRead)
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

      {recorderIngressDetailRows.length > 0 ? (
        <Panel title="Recorder ingress">
          <KeyValueRows rows={recorderIngressDetailRows} />
        </Panel>
      ) : null}

      <Panel title="Resource usage">
        <KeyValueRows
          rows={[
            {
              label: "CPU",
              value:
                runtimeStack?.cpuUsagePercent === null ||
                runtimeStack?.cpuUsagePercent === undefined
                  ? NOT_REPORTED
                  : `${Math.round(runtimeStack.cpuUsagePercent)}%`
            },
            {
              label: "Memory available to VM",
              value: formatResourceUsage(runtimeStack?.memory)
            },
            {
              label: "VM disk",
              value: formatResourceUsage(runtimeStack?.systemDisk)
            },
            {
              label: "Data storage",
              value: formatResourceUsage(status?.dataStorage)
            },
            {
              label: "Runtime stack resource",
              value: runtimeStackQuery.isError
                ? runtimeStackQuery.error.message
                : runtimeStack?.state ?? NOT_REPORTED
            }
          ]}
        />
      </Panel>
    </div>
  );
}

function dataDirectoryPresentation(
  query: ReturnType<typeof useRuntimePlatformSettings>,
  read: ReturnType<typeof useRuntimePlatformSettings>["data"]
): { value: string; detail?: string } {
  if (query.isError) {
    return { value: "Read failed", detail: query.error.message };
  }
  if (!read) {
    return { value: NOT_REPORTED };
  }
  if (read.state === "failed") {
    return { value: "Read failed", detail: read.readError ?? undefined };
  }
  if (read.state === "unavailable") {
    return { value: "Unavailable", detail: read.readError ?? undefined };
  }
  if (!read.settings) {
    return {
      value: "Invalid settings state",
      detail: "Platform settings are loaded without a settings document."
    };
  }
  return { value: read.settings.vitalFilesDirectory };
}

function joinDetails(...details: Array<string | undefined>): string | undefined {
  const values = details.filter((value): value is string => Boolean(value));
  return values.length > 0 ? values.join(" · ") : undefined;
}

function advertisedVitalServerURL(
  settings: RuntimeProductSettings | undefined,
  browserHostname: string | undefined
): string | null {
  const advertised = settings?.vitalServerURL?.trim();
  if (advertised) {
    return advertised;
  }
  if (!settings) {
    return null;
  }
  if (!settings.publicHost.trim()) {
    return sameHostRuntimeURL({
      hostname: browserHostname,
      port: settings.publicPort
    });
  }
  return runtimeURL({
    host: settings.publicHost,
    port: settings.publicPort
  });
}

function advertisedRemoteConsoleURL(
  settings: RuntimeProductSettings | undefined,
  _browserHostname: string | undefined
): string | null {
  const advertised = settings?.remoteConsoleURL?.trim();
  if (advertised) {
    return advertised;
  }
  return null;
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

function recorderIngressDetails(status: RuntimeRecorderIngressStatus | null | undefined) {
  if (!status) {
    return [];
  }
  const spool = status.spool;
  const replay = status.replay;
  const rawArchive = status.rawArchive;
  return [
    {
      label: "Connections",
      value: `${status.activeRecorderConnections} active / ${status.activeWebSockets} WebSockets`
    },
    {
      label: "Queue",
      value: formatRecorderIngressQueueDetail(spool)
    },
    {
      label: "Throughput",
      value: formatRecorderIngressThroughput(status.throughput)
    },
    {
      label: "Raw archive",
      value: formatRecorderIngressRawArchive(rawArchive)
    },
    {
      label: "Raw archive auto export",
      value: formatRecorderIngressRawArchiveAutoExport(rawArchive)
    },
    {
      label: "Oldest pending",
      value: formatDurationSeconds(spool?.oldestPendingAgeSeconds)
    },
    {
      label: "Replay",
      value: replay?.status ?? NOT_REPORTED
    },
    {
      label: "Replay throughput",
      value: formatReplayThroughput(replay)
    },
    {
      label: "In flight",
      value: formatNumber(replay?.inFlightItems)
    },
    {
      label: "Replay lag",
      value: formatDurationSeconds(replay?.replayLagSeconds)
    },
    {
      label: "Backpressure rejected",
      value: formatNumber(spool?.rejectedEvents)
    },
    {
      label: "Retryable failures",
      value: formatNumber(replay?.retryableFailures)
    },
    {
      label: "Dead letters",
      value: formatNumber(replay?.deadLetteredEvents)
    },
    {
      label: "Last failure",
      value: formatRecorderIngressLastFailure(
        spool?.lastFailure,
        replay?.lastFailure,
        rawArchive?.lastFailure,
        rawArchive?.autoExport?.lastFailure
      )
    }
  ];
}

export function recorderIngressQueueStatus(
  read: RuntimeRecorderIngressStatusRead | null | undefined
): string {
  if (!read) {
    return NOT_REPORTED;
  }
  if (read.readState !== "loaded") {
    return formatRecorderIngressStatusReadState(
      read.readState
    );
  }
  const status = read.document;
  if (!status) {
    return NOT_REPORTED;
  }
  const spool = status.spool;
  const replay = status.replay;
  const rawArchive = status.rawArchive;
  if (!spool && !replay && !rawArchive) {
    return "Not reported";
  }
  const pending = spool?.pendingItems ?? replay?.pendingItems;
  const oldest = spool?.oldestPendingAgeSeconds;
  const lag = replay?.replayLagSeconds;
  const rejected = spool?.rejectedEvents ?? 0;
  const retryable = replay?.retryableFailures ?? 0;
  const deadLetters = replay?.deadLetteredEvents ?? 0;
  const writeFailures = spool?.writeFailures ?? 0;
  const rawArchiveWriteFailures = rawArchive?.writeFailures ?? 0;
  const autoExportFailedJobs = rawArchive?.autoExport?.failedJobs ?? 0;
  const state =
    deadLetters > 0 ||
    writeFailures > 0 ||
    rawArchiveWriteFailures > 0 ||
    rawArchive?.status === "failed"
      ? "failed"
      : rejected > 0 || retryable > 0 || autoExportFailedJobs > 0
        ? "degraded"
        : (pending ?? 0) > 0
          ? "draining"
          : "healthy";
  const parts = [state];
  if (pending !== undefined) {
    parts.push(`${pending} pending`);
  }
  if (spool?.pendingBytes !== null && spool?.pendingBytes !== undefined) {
    parts.push(formatBytes(spool.pendingBytes));
  }
  if (oldest !== null && oldest !== undefined) {
    parts.push(`oldest ${formatDurationSeconds(oldest)}`);
  }
  if (lag !== null && lag !== undefined) {
    parts.push(`replay lag ${formatDurationSeconds(lag)}`);
  }
  if (deadLetters > 0) {
    parts.push(`${deadLetters} dead letters`);
  }
  if (rawArchiveWriteFailures > 0) {
    parts.push(`${rawArchiveWriteFailures} raw archive write failures`);
  }
  if (autoExportFailedJobs > 0) {
    parts.push(`${autoExportFailedJobs} auto export failures`);
  }
  return parts.join(", ");
}

function formatRecorderIngressQueueDetail(spool: RuntimeRecorderIngressSpool): string {
  if (!spool) {
    return NOT_REPORTED;
  }
  const parts = [];
  if (spool.pendingItems !== null && spool.pendingItems !== undefined) {
    parts.push(`${spool.pendingItems} pending`);
  }
  if (spool.pendingBytes !== null && spool.pendingBytes !== undefined) {
    parts.push(formatBytes(spool.pendingBytes));
  }
  return parts.length > 0 ? parts.join(" / ") : NOT_REPORTED;
}

function formatRecorderIngressThroughput(
  throughput: RuntimeRecorderIngressThroughput
): string {
  if (!throughput) {
    return NOT_REPORTED;
  }
  const parts = [];
  if (
    throughput.observedBytesPerSecond !== null &&
    throughput.observedBytesPerSecond !== undefined
  ) {
    parts.push(`in ${formatBytesPerSecond(throughput.observedBytesPerSecond)}`);
  }
  if (
    throughput.replayedBytesPerSecond !== null &&
    throughput.replayedBytesPerSecond !== undefined
  ) {
    parts.push(`replay ${formatBytesPerSecond(throughput.replayedBytesPerSecond)}`);
  }
  if (
    throughput.queueGrowthBytesPerSecond !== null &&
    throughput.queueGrowthBytesPerSecond !== undefined
  ) {
    parts.push(`queue ${formatSignedBytesPerSecond(throughput.queueGrowthBytesPerSecond)}`);
  }
  return parts.length > 0 ? parts.join(", ") : NOT_REPORTED;
}

function formatRecorderIngressRawArchive(
  rawArchive: RuntimeRecorderIngressRawArchive
): string {
  if (!rawArchive) {
    return NOT_REPORTED;
  }
  const parts = [rawArchive.status ?? "unknown"];
  if (rawArchive.persistedEvents !== null && rawArchive.persistedEvents !== undefined) {
    parts.push(`${rawArchive.persistedEvents} events`);
  }
  if (rawArchive.persistedBytes !== null && rawArchive.persistedBytes !== undefined) {
    parts.push(formatBytes(rawArchive.persistedBytes));
  }
  if (rawArchive.writeFailures !== null && rawArchive.writeFailures !== undefined) {
    parts.push(`${rawArchive.writeFailures} write failures`);
  }
  if (rawArchive.lastArchivedAt) {
    parts.push(`last ${formatLocalDateTime(rawArchive.lastArchivedAt)}`);
  }
  return parts.join(", ");
}

function formatRecorderIngressRawArchiveAutoExport(
  rawArchive: RuntimeRecorderIngressRawArchive
): string {
  const autoExport = rawArchive?.autoExport;
  if (!autoExport) {
    return NOT_REPORTED;
  }
  const parts = [autoExport.status ?? "unknown"];
  if (autoExport.finalizable === true) {
    parts.push("finalizable");
  }
  if (autoExport.exportedJobs !== null && autoExport.exportedJobs !== undefined) {
    parts.push(`${autoExport.exportedJobs} exported`);
  }
  if (autoExport.failedJobs !== null && autoExport.failedJobs !== undefined) {
    parts.push(`${autoExport.failedJobs} failed`);
  }
  if (autoExport.activeJob?.state) {
    parts.push(`job ${autoExport.activeJob.state}`);
  }
  if (autoExport.reasons?.length) {
    parts.push(autoExport.reasons.join(", "));
  }
  return parts.join(", ");
}

function formatReplayThroughput(replay: RuntimeRecorderIngressReplay): string {
  if (!replay?.maxBytesPerSecond) {
    return NOT_REPORTED;
  }
  const base = formatBytesPerSecond(replay.maxBytesPerSecond);
  const adaptive = replay.adaptive;
  if (
    adaptive?.enabled !== true ||
    adaptive.minBytesPerSecond === null ||
    adaptive.minBytesPerSecond === undefined ||
    adaptive.maxBytesPerSecond === null ||
    adaptive.maxBytesPerSecond === undefined
  ) {
    return base;
  }
  const parts = [
    `${base}, adaptive ${formatBytesPerSecond(
    adaptive.minBytesPerSecond
    )}-${formatBytesPerSecond(adaptive.maxBytesPerSecond)}`,
  ];
  if (adaptive.memoryGuardStatus) {
    parts.push(`guard ${adaptive.memoryGuardStatus}`);
  }
  if (adaptive.currentItemsPerTick !== null && adaptive.currentItemsPerTick !== undefined) {
    parts.push(`${adaptive.currentItemsPerTick} items/tick`);
  }
  if (adaptive.currentConcurrency !== null && adaptive.currentConcurrency !== undefined) {
    parts.push(`concurrency ${adaptive.currentConcurrency}`);
  }
  return parts.join(", ");
}

function formatRecorderIngressLastFailure(
  spoolFailure: RuntimeRecorderIngressFailure | null | undefined,
  replayFailure: RuntimeRecorderIngressFailure | null | undefined,
  rawArchiveFailure?: RuntimeRecorderIngressFailure | null,
  rawArchiveAutoExportFailure?: RuntimeRecorderIngressFailure | null
): string {
  return (
    formatRecorderIngressFailure(rawArchiveAutoExportFailure) ??
    formatRecorderIngressFailure(rawArchiveFailure) ??
    formatRecorderIngressFailure(replayFailure) ??
    formatRecorderIngressFailure(spoolFailure) ??
    "none"
  );
}

function formatRecorderIngressFailure(
  failure: RuntimeRecorderIngressFailure | null | undefined
): string | null {
  if (!failure) {
    return null;
  }
  if (failure.reason && failure.message) {
    return `${failure.reason}: ${failure.message}`;
  }
  return failure.reason ?? failure.message ?? null;
}

function formatDurationSeconds(value: number | null | undefined): string {
  if (value === null || value === undefined) {
    return NOT_REPORTED;
  }
  const seconds = Math.max(0, Math.round(value));
  if (seconds < 60) {
    return `${seconds}s`;
  }
  const minutes = Math.floor(seconds / 60);
  const remainder = seconds % 60;
  if (minutes < 60) {
    return remainder === 0 ? `${minutes}m` : `${minutes}m ${remainder}s`;
  }
  const hours = Math.floor(minutes / 60);
  const minuteRemainder = minutes % 60;
  return minuteRemainder === 0 ? `${hours}h` : `${hours}h ${minuteRemainder}m`;
}

function formatNumber(value: number | null | undefined): string {
  return value === null || value === undefined ? NOT_REPORTED : String(value);
}

function formatBytesPerSecond(value: number): string {
  return `${formatBytes(Math.max(0, Math.round(value)))}/s`;
}

function formatSignedBytesPerSecond(value: number): string {
  if (value > 0) {
    return `+${formatBytesPerSecond(value)}`;
  }
  if (value < 0) {
    return `-${formatBytesPerSecond(Math.abs(value))}`;
  }
  return formatBytesPerSecond(0);
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" ? value : undefined;
}

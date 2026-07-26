import { useMemo, useState } from "react";

import { useVitalDBRecorderActivity } from "@/console/hooks";
import type {
  RuntimeVitalRecorderActivityWindow,
  VitalDBRecorderRecord
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "@/domain/runtime-control/formatting/bytes";
import { ErrorState } from "@/components/ErrorState";
import { MetricStrip } from "@/components/MetricStrip";

const bucketOptions = [
  { label: "1 min", seconds: 60 },
  { label: "5 min", seconds: 300 }
] as const;

const periodOptions = [
  { label: "Last hour", period: "lastHour" },
  { label: "Last 4 hours", period: "last4Hours" },
  { label: "Last 8 hours", period: "last8Hours" },
  { label: "Last 12 hours", period: "last12Hours" },
  { label: "All", period: "all" }
] as const;

type ActivityPeriod = (typeof periodOptions)[number]["period"];

type ChartBucket = {
  startMs: number;
  endMs: number;
  messageCount: number;
  byteCount: number;
};

const chart = {
  width: 900,
  height: 520,
  left: 58,
  right: 24,
  top: 38,
  bottom: 58
};

export function RecorderActivityChart({
  recorder
}: {
  recorder: VitalDBRecorderRecord;
}) {
  const [bucketSeconds, setBucketSeconds] = useState<60 | 300>(60);
  const [period, setPeriod] = useState<ActivityPeriod>("lastHour");
  const [pageIndex, setPageIndex] = useState<number | null>(null);
  const activity = useVitalDBRecorderActivity({
    vrcode: recorder.vrcode,
    bucketSeconds,
    period,
    ...(period === "all" && pageIndex !== null ? { pageIndex } : {})
  });
  const window = activity.data;
  const bucketRead = useMemo(
    () => chartBuckets(window?.buckets ?? []),
    [window?.buckets]
  );
  const buckets = bucketRead.buckets;
  const maxPackets = Math.max(1, ...buckets.map((bucket) => bucket.messageCount));
  const latestBucket = buckets.at(-1);
  const totalPackets = buckets.reduce(
    (total, bucket) => total + bucket.messageCount,
    0
  );
  const totalBytes = buckets.reduce((total, bucket) => total + bucket.byteCount, 0);
  const latestRate = latestBucket
    ? (latestBucket.byteCount /
        Math.max(latestBucket.endMs - latestBucket.startMs, 1)) *
      1_000
    : 0;
  const reported = window?.state === "loaded" || window?.state === "empty";

  return (
    <div className="recorder-activity">
      <div className="chart-toolbar">
        <label>
          Bucket
          <select
            value={bucketSeconds}
            onChange={(event) => {
              setBucketSeconds(Number(event.target.value) as 60 | 300);
              setPageIndex(null);
            }}
          >
            {bucketOptions.map((option) => (
              <option key={option.seconds} value={option.seconds}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        <label>
          Period
          <select
            value={period}
            onChange={(event) => {
              setPeriod(event.target.value as ActivityPeriod);
              setPageIndex(null);
            }}
          >
            {periodOptions.map((option) => (
              <option key={option.period} value={option.period}>
                {option.label}
              </option>
            ))}
          </select>
        </label>
        {window?.latestSampleAt ? (
          <span className="chart-meta">
            Last activity {formatTime(window.latestSampleAt)}
          </span>
        ) : null}
      </div>

      {period === "all" && window ? (
        <ActivityWindowControl window={window} onSelectPage={setPageIndex} />
      ) : null}

      {activity.isError ? (
        <ErrorState title="Recorder activity request failed" error={activity.error} />
      ) : null}
      {window?.readError ? (
        <ErrorState
          title="Recorder activity data is unavailable"
          error={new Error(window.readError)}
        />
      ) : null}
      {bucketRead.issues.length > 0 ? (
        <ErrorState
          title="Recorder activity data is incomplete"
          error={new Error(bucketRead.issues.join("; "))}
        />
      ) : null}

      {activity.isPending ? (
        <p className="empty-state">Loading recorder activity...</p>
      ) : !reported ? (
        <p className="empty-state">Recorder activity is unavailable.</p>
      ) : buckets.length > 0 ? (
        <svg
          className="activity-chart"
          viewBox={`0 0 ${chart.width} ${chart.height}`}
          role="img"
          aria-label={`Packet activity for ${recorder.vrcode}`}
        >
          <Axis maxPackets={maxPackets} buckets={buckets} />
          <Bars buckets={buckets} maxPackets={maxPackets} />
        </svg>
      ) : (
        <p className="empty-state">
          No recent data activity has been observed for this VRecorder.
        </p>
      )}

      {reported ? (
        <MetricStrip
          metrics={[
            { label: "Packets", value: latestBucket?.messageCount ?? 0 },
            { label: "Total packets", value: totalPackets },
            { label: "Total data", value: formatBytes(totalBytes) },
            { label: "Data rate", value: `${formatBytes(latestRate)}/s` }
          ]}
        />
      ) : null}
    </div>
  );
}

function ActivityWindowControl({
  window,
  onSelectPage
}: {
  window: RuntimeVitalRecorderActivityWindow;
  onSelectPage: (page: number) => void;
}) {
  return (
    <div className="activity-window-control">
      <label>
        Window
        <input
          type="range"
          aria-label="Window"
          min={0}
          max={Math.max(window.page.count - 1, 0)}
          value={window.page.index}
          onChange={(event) => onSelectPage(Number(event.target.value))}
          disabled={window.page.count <= 1}
        />
      </label>
      <span className="chart-meta">
        {formatWindow(window.page.windowStartedAt, window.page.windowEndedAt)}
      </span>
    </div>
  );
}

function chartBuckets(
  source: RuntimeVitalRecorderActivityWindow["buckets"]
): { buckets: ChartBucket[]; issues: string[] } {
  const issues: string[] = [];
  const buckets = source.flatMap((bucket, index) => {
    const startMs = timestamp(bucket.bucketStartedAt);
    if (startMs === null || bucket.bucketSeconds <= 0) {
      issues.push(`activity bucket ${index} has invalid time metadata`);
      return [];
    }
    return [{
      startMs,
      endMs: startMs + bucket.bucketSeconds * 1_000,
      messageCount: bucket.messageCount,
      byteCount: bucket.byteCount
    }];
  });
  return { buckets, issues };
}

function Axis({
  maxPackets,
  buckets
}: {
  maxPackets: number;
  buckets: Array<{ startMs: number; endMs: number }>;
}) {
  const plotWidth = chart.width - chart.left - chart.right;
  const plotHeight = chart.height - chart.top - chart.bottom;
  const yTicks = [...new Set([maxPackets, Math.round(maxPackets / 2), 0])];
  const xLabels = xAxisLabels(buckets);

  return (
    <g className="activity-axis">
      {yTicks.map((tick) => {
        const y = chart.top + plotHeight - (tick / maxPackets) * plotHeight;
        return (
          <g key={tick}>
            <line x1={chart.left} x2={chart.left + plotWidth} y1={y} y2={y} className="activity-grid-line" />
            <text x={chart.left - 10} y={y + 5} textAnchor="end">{tick}</text>
          </g>
        );
      })}
      <line x1={chart.left} x2={chart.left} y1={chart.top} y2={chart.top + plotHeight} className="activity-axis-line" />
      <line x1={chart.left} x2={chart.left + plotWidth} y1={chart.top + plotHeight} y2={chart.top + plotHeight} className="activity-axis-line" />
      <text x={chart.left} y={18} className="activity-axis-title">Packets</text>
      <text x={chart.left + plotWidth} y={chart.height - 6} textAnchor="end" className="activity-axis-title">Time</text>
      {xLabels.map((label) => (
        <text key={`${label.value}-${label.x}`} x={label.x} y={chart.height - 22} textAnchor={label.anchor}>
          {formatTime(label.value)}
        </text>
      ))}
    </g>
  );
}

function Bars({
  buckets,
  maxPackets
}: {
  buckets: Array<{ startMs: number; messageCount: number }>;
  maxPackets: number;
}) {
  const plotWidth = chart.width - chart.left - chart.right;
  const plotHeight = chart.height - chart.top - chart.bottom;
  const slotWidth = plotWidth / buckets.length;
  const barWidth = Math.max(4, Math.min(42, slotWidth * 0.58));

  return (
    <g>
      {buckets.map((bucket, index) => {
        const height = (bucket.messageCount / maxPackets) * plotHeight;
        const x = chart.left + index * slotWidth + (slotWidth - barWidth) / 2;
        const y = chart.top + plotHeight - height;
        return (
          <rect key={bucket.startMs} x={x} y={y} width={barWidth} height={Math.max(2, height)} rx="4" className="activity-bar">
            <title>{formatTime(bucket.startMs)}: {bucket.messageCount} packets</title>
          </rect>
        );
      })}
    </g>
  );
}

function xAxisLabels(
  buckets: Array<{ startMs: number; endMs: number }>
): Array<{ value: number; x: number; anchor: "start" | "middle" | "end" }> {
  const plotWidth = chart.width - chart.left - chart.right;
  const first = buckets[0];
  const last = buckets.at(-1);
  if (!first || !last) return [];
  if (buckets.length === 1) {
    return [{ value: first.startMs, x: chart.left, anchor: "start" }];
  }
  if (buckets.length === 2) {
    return [
      { value: first.startMs, x: chart.left, anchor: "start" },
      { value: last.endMs, x: chart.left + plotWidth, anchor: "end" }
    ];
  }
  const middle = buckets[Math.floor((buckets.length - 1) / 2)];
  return [
    { value: first.startMs, x: chart.left, anchor: "start" },
    { value: middle.startMs, x: chart.left + plotWidth / 2, anchor: "middle" },
    { value: last.endMs, x: chart.left + plotWidth, anchor: "end" }
  ];
}

function timestamp(value: string | null | undefined): number | null {
  if (!value) return null;
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? null : parsed;
}

function formatTime(value: string | number | null | undefined): string {
  if (!value) return "-";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "-";
  return new Intl.DateTimeFormat(undefined, {
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

function formatWindow(start: string | null, end: string | null): string {
  if (!start || !end) return "No activity window";
  return `${formatTime(start)} - ${formatTime(end)}`;
}

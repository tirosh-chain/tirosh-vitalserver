import { useEffect, useMemo, useState } from "react";

import type { VitalDBRecorderRecord } from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { formatBytes } from "@/domain/runtime-control/formatting/bytes";
import {
  readRecorderActivityBuckets,
  latestRecorderActivityPoint
} from "@/domain/runtime-control/recorders/recorderActivity";
import { ErrorState } from "@/components/ErrorState";
import { MetricStrip } from "@/components/MetricStrip";

const bucketOptions = [
  { label: "1 min", seconds: 60 },
  { label: "5 min", seconds: 300 }
];

const rangeOptions = [
  { label: "Last hour", seconds: 60 * 60 },
  { label: "Last 4 hours", seconds: 4 * 60 * 60 },
  { label: "Last 8 hours", seconds: 8 * 60 * 60 },
  { label: "Last 12 hours", seconds: 12 * 60 * 60 },
  { label: "All", seconds: null }
];

const allSamplesWindowSeconds = 12 * 60 * 60;
const defaultAllSamplesPageStepHours = 4;
const allSamplesMinPageStepHours = 1;
const allSamplesMaxPageStepHours = 12;

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
  const [bucketSeconds, setBucketSeconds] = useState(60);
  const [rangeSeconds, setRangeSeconds] = useState<number | null>(60 * 60);
  const [allSamplesPageIndex, setAllSamplesPageIndex] = useState<number | null>(null);
  const [allSamplesPageStepHours, setAllSamplesPageStepHours] = useState(
    defaultAllSamplesPageStepHours
  );
  const [nowMs, setNowMs] = useState(() => Date.now());
  const activityTimeline = recorder.activityTimeline;
  const allSamplesMode = rangeSeconds === null;
  const allSamplesPageStepSeconds = allSamplesPageStepHours * 60 * 60;

  useEffect(() => {
    const timer = window.setInterval(() => setNowMs(Date.now()), 30_000);
    return () => window.clearInterval(timer);
  }, []);

  const activityRead = useMemo(
    () =>
      readRecorderActivityBuckets(activityTimeline, {
        bucketSeconds,
        rangeSeconds,
        currentTimeMs: allSamplesMode ? undefined : nowMs,
        activityStartedAt: recorder.firstSeenAt,
        activityEndedAt: recorder.lastSeenAt
      }),
    [
      activityTimeline,
      allSamplesMode,
      bucketSeconds,
      nowMs,
      rangeSeconds,
      recorder.firstSeenAt,
      recorder.lastSeenAt
    ]
  );
  const pagedActivity = useMemo(
    () => allSamplesMode
      ? pagedAllSamples(
          activityRead.buckets,
          bucketSeconds,
          allSamplesPageStepSeconds,
          allSamplesPageIndex
        )
      : null,
    [
      activityRead.buckets,
      allSamplesMode,
      bucketSeconds,
      allSamplesPageStepSeconds,
      allSamplesPageIndex
    ]
  );
  const buckets = pagedActivity?.buckets ?? activityRead.buckets;
  const latestActivity = latestRecorderActivityPoint(activityTimeline);

  const maxPackets = Math.max(
    1,
    ...buckets.map((bucket) => bucket.messageCount)
  );
  const latestBucket =
    buckets.at(-1);
  const totalPackets = buckets.reduce(
    (total, bucket) => total + bucket.messageCount,
    0
  );
  const totalBytes = buckets.reduce((total, bucket) => total + bucket.byteCount, 0);
  const latestRate = latestBucket
    ? (latestBucket.byteCount / Math.max(latestBucket.endMs - latestBucket.startMs, 1)) * 1_000
    : 0;
  const packetCount = latestBucket?.messageCount ?? 0;
  const activityReported = activityTimeline !== undefined;

  return (
    <div className="recorder-activity">
      {activityReported ? (
        <div className="chart-toolbar">
          <label>
            Bucket
            <select
              value={bucketSeconds}
              onChange={(event) => {
                const nextBucketSeconds = Number(event.target.value);
                setBucketSeconds(nextBucketSeconds);
                setAllSamplesPageIndex(null);
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
              value={rangeSeconds ?? "all"}
              onChange={(event) => {
                setRangeSeconds(
                  event.target.value === "all" ? null : Number(event.target.value)
                );
                setAllSamplesPageIndex(null);
              }}
            >
              {rangeOptions.map((option) => (
                <option
                  key={option.label}
                  value={option.seconds ?? "all"}
                >
                  {option.label}
                </option>
              ))}
            </select>
          </label>
          {latestActivity ? (
            <span className="chart-meta">
              Last activity {formatTime(latestActivity.observedAt)}
            </span>
          ) : null}
          {allSamplesMode ? (
            <label>
              Window slide
              <input
                type="range"
                aria-label="Window slide"
                min={allSamplesMinPageStepHours}
                max={allSamplesMaxPageStepHours}
                value={allSamplesPageStepHours}
                onChange={(event) => {
                  const nextStepHours = Number(event.target.value);
                  setAllSamplesPageStepHours(nextStepHours);
                  setAllSamplesPageIndex(null);
                }}
                title={`Window slides by ${formatDurationHours(
                  allSamplesPageStepHours
                )} each move`}
              />
              <span className="chart-meta">
                {formatDurationHours(allSamplesPageStepHours)}
              </span>
            </label>
          ) : null}
        </div>
      ) : null}

      {activityReported && pagedActivity ? (
        <div className="activity-window-control">
          <label>
            Window
            <input
              type="range"
              min={0}
              max={Math.max(pagedActivity.pageCount - 1, 0)}
              value={pagedActivity.pageIndex}
              onChange={(event) => setAllSamplesPageIndex(Number(event.target.value))}
              disabled={pagedActivity.pageCount <= 1}
            />
          </label>
          <span
            className="chart-meta"
            title={`Window slides by ${formatDurationSeconds(
              allSamplesPageStepSeconds
            )} each move`}
          >
            {formatWindow(
              pagedActivity.windowStartMs,
              pagedActivity.windowEndMs,
              allSamplesPageStepSeconds,
              allSamplesMode
            )}
          </span>
        </div>
      ) : null}

      {activityRead.issues.length > 0 ? (
        <ErrorState
          title="Recorder activity data is incomplete"
          error={new Error(activityRead.issues.join("; "))}
        />
      ) : null}

      {!activityReported ? (
        <p className="empty-state">Recorder activity history is not reported.</p>
      ) : buckets.length > 0 ? (
        <svg
          className="activity-chart"
          viewBox={`0 0 ${chart.width} ${chart.height}`}
          role="img"
          aria-label={`Packet activity for ${recorder.vrcode ?? "selected VRecorder"}`}
        >
          <Axis maxPackets={maxPackets} buckets={buckets} />
          <Bars buckets={buckets} maxPackets={maxPackets} />
        </svg>
      ) : (
        <p className="empty-state">
          No recent data activity has been observed for this VRecorder.
        </p>
      )}

      {activityReported ? (
        <MetricStrip
          metrics={[
            { label: "Packets", value: packetCount },
            { label: "Total packets", value: totalPackets },
            { label: "Total data", value: formatBytes(totalBytes) },
            { label: "Data rate", value: `${formatBytes(latestRate)}/s` }
          ]}
        />
      ) : null}
    </div>
  );
}

function pagedAllSamples(
  buckets: ReturnType<typeof readRecorderActivityBuckets>["buckets"],
  bucketSeconds: number,
  pageStepSeconds: number,
  requestedPageIndex: number | null
) {
  const bucketCountPerWindow = Math.max(
    1,
    Math.floor(allSamplesWindowSeconds / bucketSeconds)
  );
  const bucketStepPerWindow = Math.max(
    1,
    Math.floor(pageStepSeconds / bucketSeconds)
  );
  const startIndexMax = Math.max(0, buckets.length - bucketCountPerWindow);
  const steppedPageCount = Math.max(
    1,
    Math.ceil(startIndexMax / bucketStepPerWindow) + 1
  );
  const pageCount = steppedPageCount;
  const latestPageIndex = pageCount - 1;
  const pageIndex = clamp(
    requestedPageIndex ?? latestPageIndex,
    0,
    latestPageIndex
  );
  const start = Math.min(pageIndex * bucketStepPerWindow, startIndexMax);
  const pageBuckets = buckets.slice(
    start,
    Math.min(start + bucketCountPerWindow, buckets.length)
  );
  const firstBucket = pageBuckets.at(0);
  const lastBucket = pageBuckets.at(-1);

  return {
    buckets: pageBuckets,
    pageCount,
    pageIndex,
    windowStartMs: firstBucket?.startMs ?? null,
    windowEndMs: lastBucket?.endMs ?? null
  };
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max);
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
            <line
              x1={chart.left}
              x2={chart.left + plotWidth}
              y1={y}
              y2={y}
              className="activity-grid-line"
            />
            <text x={chart.left - 10} y={y + 5} textAnchor="end">
              {tick}
            </text>
          </g>
        );
      })}
      <line
        x1={chart.left}
        x2={chart.left}
        y1={chart.top}
        y2={chart.top + plotHeight}
        className="activity-axis-line"
      />
      <line
        x1={chart.left}
        x2={chart.left + plotWidth}
        y1={chart.top + plotHeight}
        y2={chart.top + plotHeight}
        className="activity-axis-line"
      />
      <text x={chart.left} y={18} className="activity-axis-title">
        Packets
      </text>
      <text
        x={chart.left + plotWidth}
        y={chart.height - 6}
        textAnchor="end"
        className="activity-axis-title"
      >
        Time
      </text>
      {xLabels.map((label) => (
        <text
          key={`${label.value}-${label.x}`}
          x={label.x}
          y={chart.height - 22}
          textAnchor={label.anchor}
        >
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
          <rect
            key={bucket.startMs}
            x={x}
            y={y}
            width={barWidth}
            height={Math.max(2, height)}
            rx="4"
            className="activity-bar"
          >
            <title>
              {formatTime(bucket.startMs)}: {bucket.messageCount} packets
            </title>
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
  if (!first || !last) {
    return [];
  }
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

function formatTime(value: string | number | null | undefined): string {
  if (!value) {
    return "-";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "-";
  }
  return new Intl.DateTimeFormat(undefined, {
    hour: "2-digit",
    minute: "2-digit"
  }).format(date);
}

function formatWindow(
  startMs: number | null,
  endMs: number | null,
  pageStepSeconds: number,
  allSamplesMode: boolean
) {
  if (startMs === null || endMs === null) {
    return "No activity window";
  }

  const stepText = allSamplesMode
    ? ` • slide ${formatDurationSeconds(pageStepSeconds)}`
    : "";

  return `${formatTime(startMs)} - ${formatTime(endMs)}${stepText}`;
}

function formatDurationHours(hours: number) {
  return `${hours}h`;
}

function formatDurationSeconds(seconds: number) {
  const hours = Math.floor(seconds / 3600);
  const remainingSeconds = seconds % 3600;
  const minutes = Math.floor(remainingSeconds / 60);

  if (minutes === 0) {
    return `${hours}h`;
  }

  return `${hours}h ${minutes}m`;
}

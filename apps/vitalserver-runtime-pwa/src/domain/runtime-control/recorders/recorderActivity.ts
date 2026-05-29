import type { VitalDBRecorderRecord } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export type RecorderActivityPoint = NonNullable<
  VitalDBRecorderRecord["activityTimeline"]
>[number];

type RecorderActivityBucketSample = NonNullable<
  RecorderActivityPoint["buckets"]
>[number];

export type RecorderActivityBucket = {
  startMs: number;
  endMs: number;
  messageCount: number;
  byteCount: number;
  roomCount: number;
};

export type RecorderActivityBucketOptions = {
  bucketSeconds: number;
  rangeSeconds?: number | null;
};

export function buildRecorderActivityBuckets(
  points: RecorderActivityPoint[] | null | undefined,
  options: RecorderActivityBucketOptions
): RecorderActivityBucket[] {
  if (!points?.length || options.bucketSeconds <= 0) {
    return [];
  }

  const parsed = points
    .map((point) => ({
      point,
      observedMs: timestamp(point.observedAt)
    }))
    .filter((sample): sample is { point: RecorderActivityPoint; observedMs: number } =>
      sample.observedMs !== null
    )
    .sort((left, right) => left.observedMs - right.observedMs);

  const latestMs = parsed.at(-1)?.observedMs;
  if (latestMs === undefined) {
    return [];
  }

  const rangeStartMs = options.rangeSeconds
    ? latestMs - options.rangeSeconds * 1_000
    : null;
  const bucketMs = options.bucketSeconds * 1_000;
  const buckets = new Map<number, RecorderActivityBucket>();
  const rawBuckets = activityBuckets(parsed.at(-1)?.point);

  if (rawBuckets.length > 0) {
    for (const rawBucket of rawBuckets) {
      addBucket(
        buckets,
        {
          startedAt: rawBucket.bucketStartedAt,
          messageCount: rawBucket.messageCount,
          byteCount: rawBucket.byteCount,
          roomCount: rawBucket.roomCount
        },
        bucketMs,
        "sum"
      );
    }

    return filledBuckets(buckets, bucketMs, options.rangeSeconds);
  }

  for (const sample of parsed) {
    if (rangeStartMs !== null && sample.observedMs < rangeStartMs) {
      continue;
    }

    addBucket(
      buckets,
      {
        startedAt: sample.point.observedAt,
        messageCount: sample.point.messageCount,
        byteCount: sample.point.byteCount,
        roomCount: sample.point.roomCount
      },
      bucketMs,
      "max"
    );
  }

  return filledBuckets(buckets, bucketMs, options.rangeSeconds);
}

export function latestRecorderActivityPoint(
  points: RecorderActivityPoint[] | null | undefined
): RecorderActivityPoint | undefined {
  return [...(points ?? [])]
    .filter((point) => timestamp(point.observedAt) !== null)
    .sort((left, right) => (timestamp(left.observedAt) ?? 0) - (timestamp(right.observedAt) ?? 0))
    .at(-1);
}

function activityBuckets(
  point: RecorderActivityPoint | undefined
): RecorderActivityBucketSample[] {
  return Array.isArray(point?.buckets) ? point.buckets : [];
}

function addBucket(
  buckets: Map<number, RecorderActivityBucket>,
  rawBucket: {
    startedAt?: string;
    messageCount?: number;
    byteCount?: number;
    roomCount?: number;
  },
  bucketMs: number,
  roomCountMode: "max" | "sum"
) {
  const rawStartMs = timestamp(rawBucket.startedAt);
  if (rawStartMs === null) {
    return;
  }

  const startMs = Math.floor(rawStartMs / bucketMs) * bucketMs;
  const bucket =
    buckets.get(startMs) ??
    {
      startMs,
      endMs: startMs + bucketMs,
      messageCount: 0,
      byteCount: 0,
      roomCount: 0
    };

  bucket.messageCount += rawBucket.messageCount ?? 0;
  bucket.byteCount += rawBucket.byteCount ?? 0;
  bucket.roomCount =
    roomCountMode === "sum"
      ? bucket.roomCount + (rawBucket.roomCount ?? 0)
      : Math.max(bucket.roomCount, rawBucket.roomCount ?? 0);
  buckets.set(startMs, bucket);
}

function filledBuckets(
  buckets: Map<number, RecorderActivityBucket>,
  bucketMs: number,
  rangeSeconds?: number | null
) {
  const bucketStarts = [...buckets.keys()].sort((left, right) => left - right);
  const latestBucketStart = bucketStarts.at(-1);
  if (latestBucketStart === undefined) {
    return [];
  }

  const rangeStartMs = rangeSeconds
    ? latestBucketStart - rangeSeconds * 1_000
    : null;
  const firstBucketStart = rangeStartMs
    ? Math.floor(rangeStartMs / bucketMs) * bucketMs
    : bucketStarts[0];
  const lastBucketStart = Math.floor(latestBucketStart / bucketMs) * bucketMs;

  if (firstBucketStart === undefined) {
    return [];
  }

  const filled: RecorderActivityBucket[] = [];
  for (let startMs = firstBucketStart; startMs <= lastBucketStart; startMs += bucketMs) {
    filled.push(
      buckets.get(startMs) ?? {
        startMs,
        endMs: startMs + bucketMs,
        messageCount: 0,
        byteCount: 0,
        roomCount: 0
      }
    );
  }

  return filled;
}

function timestamp(value: string | null | undefined): number | null {
  if (!value) {
    return null;
  }
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? null : parsed;
}

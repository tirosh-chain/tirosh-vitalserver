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

type RecorderActivityBucketMergeMode = "sum" | "max";
type RecorderActivityRoomCountMode = "sum" | "max";

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
  const rawBuckets = stableActivityBuckets(parsed.map((sample) => sample.point));

  if (rawBuckets.length > 0) {
    for (const rawBucket of rawBuckets) {
      mergeBucketFromTimestamp(
        buckets,
        {
          startedAt: new Date(rawBucket.startMs).toISOString(),
          messageCount: rawBucket.messageCount,
          byteCount: rawBucket.byteCount,
          roomCount: rawBucket.roomCount
        },
        bucketMs,
        "sum",
        "sum"
      );
    }

    return filledBuckets(buckets, bucketMs, options.rangeSeconds);
  }

  for (const sample of parsed) {
    if (rangeStartMs !== null && sample.observedMs < rangeStartMs) {
      continue;
    }

    mergeBucketFromTimestamp(
      buckets,
      {
        startedAt: sample.point.observedAt,
        messageCount: sample.point.messageCount,
        byteCount: sample.point.byteCount,
        roomCount: sample.point.roomCount
      },
      bucketMs,
      "sum",
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

function stableActivityBuckets(
  points: RecorderActivityPoint[]
): RecorderActivityBucket[] {
  const buckets = new Map<string, RecorderActivityBucket>();

  for (const point of points) {
    for (const rawBucket of activityBuckets(point)) {
      const rawBucketMs = Math.max(1, rawBucket.bucketSeconds ?? 60) * 1_000;
      const rawStartMs = timestamp(rawBucket.bucketStartedAt);
      if (rawStartMs === null) {
        continue;
      }
      const startMs = Math.floor(rawStartMs / rawBucketMs) * rawBucketMs;
      mergeBucketByStart(
        buckets,
        `${startMs}:${rawBucketMs}`,
        startMs,
        rawBucketMs,
        {
          messageCount: rawBucket.messageCount,
          byteCount: rawBucket.byteCount,
          roomCount: rawBucket.roomCount
        },
        "max",
        "max"
      );
    }
  }

  return [...buckets.values()].sort((left, right) => left.startMs - right.startMs);
}

function mergeBucketFromTimestamp(
  buckets: Map<number, RecorderActivityBucket>,
  rawBucket: {
    startedAt?: string;
    messageCount?: number;
    byteCount?: number;
    roomCount?: number;
  },
  bucketMs: number,
  mergeMode: RecorderActivityBucketMergeMode,
  roomCountMode: "max" | "sum"
) {
  const rawStartMs = timestamp(rawBucket.startedAt);
  if (rawStartMs === null) {
    return;
  }

  const startMs = Math.floor(rawStartMs / bucketMs) * bucketMs;
  mergeBucketByStart(
    buckets,
    startMs,
    startMs,
    bucketMs,
    rawBucket,
    mergeMode,
    roomCountMode
  );
}

function mergeBucketByStart<Key>(
  buckets: Map<Key, RecorderActivityBucket>,
  key: Key,
  startMs: number,
  bucketMs: number,
  rawBucket: {
    messageCount?: number;
    byteCount?: number;
    roomCount?: number;
  },
  mergeMode: RecorderActivityBucketMergeMode,
  roomCountMode: RecorderActivityRoomCountMode
) {
  const bucket =
    buckets.get(key) ??
    {
      startMs,
      endMs: startMs + bucketMs,
      messageCount: 0,
      byteCount: 0,
      roomCount: 0
    };

  if (mergeMode === "max") {
    bucket.messageCount = Math.max(bucket.messageCount, rawBucket.messageCount ?? 0);
    bucket.byteCount = Math.max(bucket.byteCount, rawBucket.byteCount ?? 0);
  } else {
    bucket.messageCount += rawBucket.messageCount ?? 0;
    bucket.byteCount += rawBucket.byteCount ?? 0;
  }

  bucket.roomCount =
    roomCountMode === "sum"
      ? bucket.roomCount + (rawBucket.roomCount ?? 0)
      : Math.max(bucket.roomCount, rawBucket.roomCount ?? 0);
  buckets.set(key, bucket);
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

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
  synthetic: boolean;
};

export type RecorderActivityBucketOptions = {
  bucketSeconds: number;
  rangeSeconds?: number | null;
  currentTimeMs?: number;
  activityStartedAt?: string | null;
  activityEndedAt?: string | null;
};

export type RecorderActivityRead = {
  buckets: RecorderActivityBucket[];
  issues: string[];
};

type RecorderActivityBucketMergeMode = "sum" | "max";
type RecorderActivityRoomCountMode = "sum" | "max";

export function buildRecorderActivityBuckets(
  points: RecorderActivityPoint[] | null | undefined,
  options: RecorderActivityBucketOptions
): RecorderActivityBucket[] {
  return readRecorderActivityBuckets(points, options).buckets;
}

export function readRecorderActivityBuckets(
  points: RecorderActivityPoint[] | null | undefined,
  options: RecorderActivityBucketOptions
): RecorderActivityRead {
  const issues: string[] = [];
  if (points === null || points === undefined) {
    return {
      buckets: [],
      issues: ["activityTimeline is not reported"]
    };
  }
  if (options.bucketSeconds <= 0) {
    return {
      buckets: [],
      issues: [`bucketSeconds must be positive: ${options.bucketSeconds}`]
    };
  }
  if (points.length === 0) {
    return { buckets: [], issues };
  }

  const parsed = points
    .map((point, index) => {
      const observedMs = timestamp(point.observedAt);
      if (observedMs === null) {
        issues.push(`activity point ${index} has invalid observedAt`);
        return null;
      }
      return { point, index, observedMs };
    })
    .filter((sample): sample is {
      point: RecorderActivityPoint;
      index: number;
      observedMs: number;
    } =>
      sample !== null
    )
    .sort((left, right) => left.observedMs - right.observedMs);

  const latestMs = parsed.at(-1)?.observedMs;
  if (latestMs === undefined) {
    return {
      buckets: [],
      issues: issues.length > 0 ? issues : ["activity has no valid timestamped samples"]
    };
  }

  if (
    options.currentTimeMs !== undefined &&
    (!Number.isFinite(options.currentTimeMs) || options.currentTimeMs < 0)
  ) {
    return {
      buckets: [],
      issues: [`currentTimeMs must be a valid timestamp: ${options.currentTimeMs}`]
    };
  }

  const explicitActivityStartMs = explicitActivityTimestamp(
    options.activityStartedAt,
    "activityStartedAt",
    issues
  );
  const explicitActivityEndMs = explicitActivityTimestamp(
    options.activityEndedAt,
    "activityEndedAt",
    issues
  );
  const earliestObservedMs = parsed[0]?.observedMs ?? null;
  const earliestMs =
    explicitActivityStartMs === null || earliestObservedMs === null
      ? earliestObservedMs
      : Math.min(explicitActivityStartMs, earliestObservedMs);
  const latestActivityMs =
    explicitActivityEndMs === null ? latestMs : Math.max(latestMs, explicitActivityEndMs);
  const rangeEndMs = options.currentTimeMs ?? latestActivityMs;
  const explicitRangeEndMs =
    options.currentTimeMs ?? (explicitActivityEndMs === null ? undefined : latestActivityMs);
  const rangeStartMs = options.rangeSeconds
    ? rangeEndMs - options.rangeSeconds * 1_000
    : null;
  const bucketMs = options.bucketSeconds * 1_000;
  const buckets = new Map<number, RecorderActivityBucket>();
  const hasEmbeddedBucketSource = parsed.some(
    (sample) => activityBuckets(sample.point).length > 0
  );
  const rawRead = stableActivityBuckets(parsed.map((sample) => sample.point));
  issues.push(...rawRead.issues);
  const rawBuckets = rawRead.buckets;

  if (hasEmbeddedBucketSource) {
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

    return {
      buckets: filledBuckets(
        buckets,
        bucketMs,
        earliestMs,
        options.rangeSeconds,
        explicitRangeEndMs
      ),
      issues
    };
  }

  for (const sample of parsed) {
    if (rangeStartMs !== null && sample.observedMs < rangeStartMs) {
      continue;
    }
    const counts = activityCounts(sample.point);
    if (!counts) {
      issues.push(`activity point ${sample.index} has incomplete counts`);
      continue;
    }

    mergeBucketFromTimestamp(
      buckets,
      {
        startedAt: sample.point.observedAt,
        messageCount: counts.messageCount,
        byteCount: counts.byteCount,
        roomCount: counts.roomCount
      },
      bucketMs,
      "sum",
      "max"
    );
  }

  return {
    buckets: filledBuckets(
      buckets,
      bucketMs,
      earliestMs,
      options.rangeSeconds,
      explicitRangeEndMs
    ),
    issues
  };
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
): RecorderActivityRead {
  const buckets = new Map<number, RecorderActivityBucket>();
  const issues: string[] = [];

  for (const [pointIndex, point] of points.entries()) {
    for (const [bucketIndex, rawBucket] of activityBuckets(point).entries()) {
      if (typeof rawBucket.bucketSeconds !== "number" || rawBucket.bucketSeconds <= 0) {
        issues.push(
          `activity point ${pointIndex} bucket ${bucketIndex} has invalid bucketSeconds`
        );
        continue;
      }
      const rawStartMs = timestamp(rawBucket.bucketStartedAt);
      if (rawStartMs === null) {
        issues.push(
          `activity point ${pointIndex} bucket ${bucketIndex} has invalid bucketStartedAt`
        );
        continue;
      }
      const counts = activityCounts(rawBucket);
      if (!counts) {
        issues.push(
          `activity point ${pointIndex} bucket ${bucketIndex} has incomplete counts`
        );
        continue;
      }
      const rawBucketMs = rawBucket.bucketSeconds * 1_000;
      const startMs = Math.floor(rawStartMs / rawBucketMs) * rawBucketMs;
      mergeBucketByStart(
        buckets,
        startMs,
        startMs,
        rawBucketMs,
        {
          messageCount: counts.messageCount,
          byteCount: counts.byteCount,
          roomCount: counts.roomCount
        },
        "max",
        "max"
      );
    }
  }

  return {
    buckets: [...buckets.values()].sort((left, right) => left.startMs - right.startMs),
    issues
  };
}

function mergeBucketFromTimestamp(
  buckets: Map<number, RecorderActivityBucket>,
  rawBucket: {
    startedAt?: string;
    messageCount: number;
    byteCount: number;
    roomCount: number;
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
    messageCount: number;
    byteCount: number;
    roomCount: number;
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
      roomCount: 0,
      synthetic: false
    };

  if (mergeMode === "max") {
    bucket.messageCount = Math.max(bucket.messageCount, rawBucket.messageCount);
    bucket.byteCount = Math.max(bucket.byteCount, rawBucket.byteCount);
  } else {
    bucket.messageCount += rawBucket.messageCount;
    bucket.byteCount += rawBucket.byteCount;
  }

  bucket.roomCount =
    roomCountMode === "sum"
      ? bucket.roomCount + rawBucket.roomCount
      : Math.max(bucket.roomCount, rawBucket.roomCount);
  buckets.set(key, bucket);
}

function filledBuckets(
  buckets: Map<number, RecorderActivityBucket>,
  bucketMs: number,
  earliestMs: number | null,
  rangeSeconds?: number | null,
  rangeEndMs?: number
) {
  const bucketStarts = [...buckets.keys()].sort((left, right) => left - right);
  const latestBucketStart = bucketStarts.at(-1);
  if (latestBucketStart === undefined) {
    return [];
  }

  const endMs = rangeEndMs ?? latestBucketStart;
  const rangeStartMs = rangeSeconds ? endMs - rangeSeconds * 1_000 : null;
  const firstActivityMs =
    earliestMs === null ? bucketStarts[0] : Math.min(earliestMs, bucketStarts[0]);
  const firstBucketStart =
    rangeStartMs !== null && firstActivityMs < rangeStartMs
      ? Math.floor(rangeStartMs / bucketMs) * bucketMs
      : Math.floor(firstActivityMs / bucketMs) * bucketMs;
  const lastBucketStart = Math.floor(endMs / bucketMs) * bucketMs;

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
        roomCount: 0,
        synthetic: true
      }
    );
  }

  return filled;
}

function activityCounts(value: {
  messageCount?: number;
  byteCount?: number;
  roomCount?: number;
}): { messageCount: number; byteCount: number; roomCount: number } | null {
  if (
    typeof value.messageCount !== "number" ||
    typeof value.byteCount !== "number" ||
    typeof value.roomCount !== "number"
  ) {
    return null;
  }
  return {
    messageCount: value.messageCount,
    byteCount: value.byteCount,
    roomCount: value.roomCount
  };
}

function timestamp(value: string | null | undefined): number | null {
  if (!value) {
    return null;
  }
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? null : parsed;
}

function explicitActivityTimestamp(
  value: string | null | undefined,
  label: string,
  issues: string[]
): number | null {
  if (value === null || value === undefined || value === "") {
    return null;
  }
  const parsed = timestamp(value);
  if (parsed === null) {
    issues.push(`${label} has invalid timestamp`);
  }
  return parsed;
}

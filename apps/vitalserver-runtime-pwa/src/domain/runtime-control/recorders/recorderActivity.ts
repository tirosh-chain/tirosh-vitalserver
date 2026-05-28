import type { VitalDBRecorderRecord } from "../contracts/runtimeControlTypes";

export type RecorderActivityPoint = NonNullable<
  VitalDBRecorderRecord["activityTimeline"]
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

  for (const sample of parsed) {
    if (rangeStartMs !== null && sample.observedMs < rangeStartMs) {
      continue;
    }

    const startMs = Math.floor(sample.observedMs / bucketMs) * bucketMs;
    const bucket =
      buckets.get(startMs) ??
      {
        startMs,
        endMs: startMs + bucketMs,
        messageCount: 0,
        byteCount: 0,
        roomCount: 0
      };

    bucket.messageCount += sample.point.messageCount ?? 0;
    bucket.byteCount += sample.point.byteCount ?? 0;
    bucket.roomCount = Math.max(bucket.roomCount, sample.point.roomCount ?? 0);
    buckets.set(startMs, bucket);
  }

  const bucketStarts = [...buckets.keys()].sort((left, right) => left - right);
  const firstBucketStart = rangeStartMs
    ? Math.floor(rangeStartMs / bucketMs) * bucketMs
    : bucketStarts[0];
  const lastBucketStart = Math.floor(latestMs / bucketMs) * bucketMs;

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

export function latestRecorderActivityPoint(
  points: RecorderActivityPoint[] | null | undefined
): RecorderActivityPoint | undefined {
  return [...(points ?? [])]
    .filter((point) => timestamp(point.observedAt) !== null)
    .sort((left, right) => (timestamp(left.observedAt) ?? 0) - (timestamp(right.observedAt) ?? 0))
    .at(-1);
}

function timestamp(value: string | null | undefined): number | null {
  if (!value) {
    return null;
  }
  const parsed = new Date(value).getTime();
  return Number.isNaN(parsed) ? null : parsed;
}

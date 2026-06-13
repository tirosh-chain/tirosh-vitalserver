import { describe, expect, it } from "vitest";

import type { RecorderActivityPoint } from "./recorderActivity";
import {
  buildRecorderActivityBuckets,
  latestRecorderActivityPoint,
  readRecorderActivityBuckets
} from "./recorderActivity";

describe("recorder activity", () => {
  it("groups activity samples into selected packet buckets", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        activityPoint({
          observedAt: "2026-05-28T00:00:10Z",
          messageCount: 3,
          byteCount: 300,
          roomCount: 1
        }),
        activityPoint({
          observedAt: "2026-05-28T00:00:50Z",
          messageCount: 4,
          byteCount: 500,
          roomCount: 2
        }),
        activityPoint({
          observedAt: "2026-05-28T00:01:03Z",
          messageCount: 2,
          byteCount: 100,
          roomCount: 1
        })
      ],
      { bucketSeconds: 60 }
    );

    expect(buckets).toMatchObject([
      {
        messageCount: 7,
        byteCount: 800,
        roomCount: 2
      },
      {
        messageCount: 2,
        byteCount: 100,
        roomCount: 1
      }
    ]);
  });

  it("filters buckets by latest sample relative range", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        activityPoint({
          observedAt: "2026-05-28T00:00:00Z",
          messageCount: 1,
          byteCount: 100,
          roomCount: 1
        }),
        activityPoint({
          observedAt: "2026-05-28T00:10:00Z",
          messageCount: 2,
          byteCount: 200,
          roomCount: 1
        })
      ],
      { bucketSeconds: 60, rangeSeconds: 60 }
    );

    expect(buckets.map((bucket) => bucket.messageCount)).toEqual([0, 2]);
    expect(buckets.map((bucket) => bucket.synthetic)).toEqual([true, false]);
  });

  it("uses explicit current time as the rolling window end", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        activityPoint({
          observedAt: "2026-05-28T00:00:00Z",
          messageCount: 2,
          byteCount: 200,
          roomCount: 1
        })
      ],
      {
        bucketSeconds: 60,
        rangeSeconds: 5 * 60,
        currentTimeMs: Date.parse("2026-05-28T00:03:10Z")
      }
    );

    expect(buckets.map((bucket) => bucket.startMs)).toEqual([
      Date.parse("2026-05-28T00:00:00Z"),
      Date.parse("2026-05-28T00:01:00Z"),
      Date.parse("2026-05-28T00:02:00Z"),
      Date.parse("2026-05-28T00:03:00Z")
    ]);
    expect(buckets.map((bucket) => bucket.messageCount)).toEqual([2, 0, 0, 0]);
    expect(buckets.at(-1)?.synthetic).toBe(true);
  });

  it("starts from earliest sample when requested range is larger than available data", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        activityPoint({
          observedAt: "2026-05-28T00:10:00Z",
          messageCount: 1,
          byteCount: 100,
          roomCount: 1
        })
      ],
      { bucketSeconds: 60, rangeSeconds: 60 * 60 }
    );

    expect(buckets).toEqual([
      {
        messageCount: 1,
        byteCount: 100,
        roomCount: 1,
        synthetic: false,
        startMs: Date.parse("2026-05-28T00:10:00Z"),
        endMs: Date.parse("2026-05-28T00:11:00Z")
      }
    ]);
  });

  it("uses embedded recorder activity buckets from the latest sample", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        activityPointWithBuckets({
          observedAt: "2026-05-28T00:10:10Z",
          messageCount: 99,
          byteCount: 9_999,
          roomCount: 9,
          buckets: [
            {
              bucketStartedAt: "2026-05-28T00:08:00Z",
              bucketSeconds: 60,
              messageCount: 4,
              byteCount: 400,
              roomCount: 1
            },
            {
              bucketStartedAt: "2026-05-28T00:09:00Z",
              bucketSeconds: 60,
              messageCount: 7,
              byteCount: 700,
              roomCount: 2
            }
          ]
        })
      ],
      { bucketSeconds: 60 }
    );

    expect(buckets).toMatchObject([
      {
        messageCount: 4,
        byteCount: 400,
        roomCount: 1
      },
      {
        messageCount: 7,
        byteCount: 700,
        roomCount: 2
      }
    ]);
  });

  it("keeps embedded bucket history when the latest rolling sample drops older buckets", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        activityPointWithBuckets({
          observedAt: "2026-05-28T00:10:10Z",
          buckets: [
            {
              bucketStartedAt: "2026-05-28T00:08:00Z",
              bucketSeconds: 60,
              messageCount: 4,
              byteCount: 400,
              roomCount: 1
            },
            {
              bucketStartedAt: "2026-05-28T00:09:00Z",
              bucketSeconds: 60,
              messageCount: 7,
              byteCount: 700,
              roomCount: 2
            }
          ]
        }),
        activityPointWithBuckets({
          observedAt: "2026-05-28T00:11:10Z",
          buckets: [
            {
              bucketStartedAt: "2026-05-28T00:09:00Z",
              bucketSeconds: 60,
              messageCount: 5,
              byteCount: 500,
              roomCount: 1
            },
            {
              bucketStartedAt: "2026-05-28T00:10:00Z",
              bucketSeconds: 60,
              messageCount: 6,
              byteCount: 600,
              roomCount: 1
            }
          ]
        })
      ],
      { bucketSeconds: 60 }
    );

    expect(buckets.map((bucket) => bucket.messageCount)).toEqual([4, 7, 6]);
    expect(buckets.map((bucket) => bucket.byteCount)).toEqual([400, 700, 600]);
  });

  it("deduplicates repeated embedded bucket snapshots", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        activityPointWithBuckets({
          observedAt: "2026-05-28T00:10:10Z",
          buckets: [
            {
              bucketStartedAt: "2026-05-28T00:09:00Z",
              bucketSeconds: 60,
              messageCount: 7,
              byteCount: 700,
              roomCount: 2
            }
          ]
        }),
        activityPointWithBuckets({
          observedAt: "2026-05-28T00:10:30Z",
          buckets: [
            {
              bucketStartedAt: "2026-05-28T00:09:00Z",
              bucketSeconds: 60,
              messageCount: 7,
              byteCount: 700,
              roomCount: 2
            }
          ]
        })
      ],
      { bucketSeconds: 60 }
    );

    expect(buckets.map((bucket) => bucket.messageCount)).toEqual([7]);
    expect(buckets.map((bucket) => bucket.byteCount)).toEqual([700]);
  });

  it("deduplicates overlapping embedded buckets from different source intervals", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        activityPointWithBuckets({
          observedAt: "2026-05-28T00:10:10Z",
          buckets: [
            {
              bucketStartedAt: "2026-05-28T00:10:00Z",
              bucketSeconds: 60,
              messageCount: 4,
              byteCount: 400,
              roomCount: 1
            },
            {
              bucketStartedAt: "2026-05-28T00:10:00Z",
              bucketSeconds: 300,
              messageCount: 8,
              byteCount: 800,
              roomCount: 2
            }
          ]
        })
      ],
      { bucketSeconds: 60 }
    );

    expect(buckets.map((bucket) => bucket.messageCount)).toEqual([8]);
    expect(buckets.map((bucket) => bucket.byteCount)).toEqual([800]);
    expect(buckets.map((bucket) => bucket.roomCount)).toEqual([2]);
  });

  it("aggregates embedded recorder activity buckets into the selected interval", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        activityPointWithBuckets({
          observedAt: "2026-05-28T00:10:10Z",
          buckets: [
            {
              bucketStartedAt: "2026-05-28T00:05:00Z",
              bucketSeconds: 60,
              messageCount: 3,
              byteCount: 300,
              roomCount: 1
            },
            {
              bucketStartedAt: "2026-05-28T00:06:00Z",
              bucketSeconds: 60,
              messageCount: 5,
              byteCount: 500,
              roomCount: 2
            }
          ]
        })
      ],
      { bucketSeconds: 300 }
    );

    expect(buckets).toMatchObject([
      {
        messageCount: 8,
        byteCount: 800,
        roomCount: 3
      }
    ]);
  });

  it("returns the latest timestamped activity point", () => {
    expect(
      latestRecorderActivityPoint([
        ...malformedActivityPoints([{ messageCount: 99 }]),
        activityPoint({ observedAt: "2026-05-28T00:00:00Z", messageCount: 1 }),
        activityPoint({ observedAt: "2026-05-28T00:00:01Z", messageCount: 2 })
      ])?.messageCount
    ).toBe(2);
  });

  it("reports missing and invalid activity input separately from empty data", () => {
    expect(
      readRecorderActivityBuckets(undefined, { bucketSeconds: 60 })
    ).toMatchObject({
      buckets: [],
      issues: ["activityTimeline is not reported"]
    });

    const invalid = readRecorderActivityBuckets(
      malformedActivityPoints([
        {
          observedAt: "not-a-date",
          messageCount: 1,
          byteCount: 10,
          roomCount: 1
        },
        {
          observedAt: "2026-05-28T00:00:00Z",
          messageCount: 1
        }
      ]),
      { bucketSeconds: 60 }
    );

    expect(invalid.buckets).toEqual([]);
    expect(invalid.issues).toEqual([
      "activity point 0 has invalid observedAt",
      "activity point 1 has incomplete counts"
    ]);
  });

  it("reports invalid embedded bucket contracts without using defaults", () => {
    const read = readRecorderActivityBuckets(
      malformedActivityPoints([
        {
          observedAt: "2026-05-28T00:00:00Z",
          windowSeconds: 60,
          messageCount: 1,
          byteCount: 10,
          roomCount: 1,
          messagesPerSecond: 0.01,
          bytesPerSecond: 10,
          buckets: [
            {
              bucketStartedAt: "2026-05-28T00:00:00Z",
              messageCount: 1,
              byteCount: 10,
              roomCount: 1
            },
            {
              bucketStartedAt: "invalid",
              bucketSeconds: 60,
              messageCount: 1,
              byteCount: 10,
              roomCount: 1
            }
          ]
        }
      ]),
      { bucketSeconds: 60 }
    );

    expect(read.buckets).toEqual([]);
    expect(read.issues).toEqual([
      "activity point 0 bucket 0 has invalid bucketSeconds",
      "activity point 0 bucket 1 has invalid bucketStartedAt"
    ]);
  });
});

function activityPoint(overrides: Partial<RecorderActivityPoint>): RecorderActivityPoint {
  return {
    observedAt: "2026-05-28T00:00:00Z",
    windowSeconds: 60,
    messageCount: 0,
    byteCount: 0,
    roomCount: 0,
    messagesPerSecond: 0,
    bytesPerSecond: 0,
    buckets: [],
    ...overrides
  };
}

function activityPointWithBuckets(
  point: Partial<RecorderActivityPoint> & {
    observedAt: string;
    buckets: RecorderActivityPoint["buckets"];
  }
): RecorderActivityPoint {
  return activityPoint(point);
}

function malformedActivityPoints(points: Array<Record<string, unknown>>): RecorderActivityPoint[] {
  return points as unknown as RecorderActivityPoint[];
}

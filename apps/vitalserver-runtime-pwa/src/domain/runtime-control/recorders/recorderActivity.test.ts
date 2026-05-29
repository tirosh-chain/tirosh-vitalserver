import { describe, expect, it } from "vitest";

import type { RecorderActivityPoint } from "./recorderActivity";
import {
  buildRecorderActivityBuckets,
  latestRecorderActivityPoint
} from "./recorderActivity";

describe("recorder activity", () => {
  it("groups activity samples into selected packet buckets", () => {
    const buckets = buildRecorderActivityBuckets(
      [
        {
          observedAt: "2026-05-28T00:00:10Z",
          messageCount: 3,
          byteCount: 300,
          roomCount: 1
        },
        {
          observedAt: "2026-05-28T00:00:50Z",
          messageCount: 4,
          byteCount: 500,
          roomCount: 2
        },
        {
          observedAt: "2026-05-28T00:01:03Z",
          messageCount: 2,
          byteCount: 100,
          roomCount: 1
        }
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
        { observedAt: "2026-05-28T00:00:00Z", messageCount: 1 },
        { observedAt: "2026-05-28T00:10:00Z", messageCount: 2 }
      ],
      { bucketSeconds: 60, rangeSeconds: 60 }
    );

    expect(buckets.map((bucket) => bucket.messageCount)).toEqual([0, 2]);
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
        { messageCount: 99 },
        { observedAt: "2026-05-28T00:00:00Z", messageCount: 1 },
        { observedAt: "2026-05-28T00:00:01Z", messageCount: 2 }
      ])?.messageCount
    ).toBe(2);
  });
});

function activityPointWithBuckets(
  point: RecorderActivityPoint & {
    buckets: Array<{
      bucketStartedAt: string;
      bucketSeconds: number;
      messageCount: number;
      byteCount: number;
      roomCount: number;
    }>;
  }
): RecorderActivityPoint {
  return point;
}

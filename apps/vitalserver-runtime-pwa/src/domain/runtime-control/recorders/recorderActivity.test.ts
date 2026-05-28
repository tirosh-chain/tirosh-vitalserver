import { describe, expect, it } from "vitest";

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

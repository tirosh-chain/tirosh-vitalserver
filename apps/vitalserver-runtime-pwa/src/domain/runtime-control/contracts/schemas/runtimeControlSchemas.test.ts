import { describe, expect, it } from "vitest";

import {
  runtimeCommandResponseSchema,
  runtimeCapabilitiesSchema,
  runtimeEventHistorySchema,
  runtimeOverviewSchema,
  vitalDBRecordersSchema
} from "./runtimeControlSchemas";

describe("runtime control contract schemas", () => {
  it("accepts a command response from Runtime Control API", () => {
    expect(
      runtimeCommandResponseSchema.parse({
        result: {
          exitCode: 0,
          stdout: "ok",
          stderr: ""
        }
      })
    ).toEqual({
      result: {
        exitCode: 0,
        stdout: "ok",
        stderr: ""
      }
    });
  });

  it("rejects invalid runtime state values in overview responses", () => {
    expect(() =>
      runtimeOverviewSchema.parse({
        status: {
          runtimeState: "surprising"
        }
      })
    ).toThrow();
  });

  it("accepts Remote Console status fields in overview responses", () => {
    expect(
      runtimeOverviewSchema.parse({
        status: {
          runtimeControlHTTP: "200",
          runtimeControlStartedAt: "2026-05-26T04:30:00Z"
        }
      }).status
    ).toMatchObject({
      runtimeControlHTTP: "200",
      runtimeControlStartedAt: "2026-05-26T04:30:00Z"
    });
  });

  it("accepts container log metadata read errors in overview responses", () => {
    expect(
      runtimeOverviewSchema.parse({
        status: {
          containerObservation: {
            containerLogsPresent: true,
            containerLogsBytes: null,
            containerLogsUpdatedAt: null,
            containerLogsMetadataError: "size-read-failed,mtime-read-failed"
          }
        }
      }).status?.containerObservation
    ).toMatchObject({
      containerLogsPresent: true,
      containerLogsMetadataError: "size-read-failed,mtime-read-failed"
    });
  });

  it("accepts recovery-suppressed runtime events from the Helper", () => {
    expect(
      runtimeEventHistorySchema.parse({
        events: [
          {
            id: "event-1",
            eventType: "recovery-suppressed",
            timestamp: "2026-05-29T11:00:00Z",
            status: "critical",
            message: "watchdog recovery suppressed"
          }
        ],
        nextCursor: null,
        matchingCount: 1
      }).events?.[0]?.eventType
    ).toBe("recovery-suppressed");
  });

  it("rejects malformed VRecorder activity samples", () => {
    expect(() =>
      vitalDBRecordersSchema.parse({
        recorders: [
          {
            vrcode: "VR_TEST",
            status: "online",
            activityTimeline: [{ messageCount: "not-a-number" }]
          }
        ]
      })
    ).toThrow();
  });

  it("accepts VRecorder activity bucket samples", () => {
    expect(
      vitalDBRecordersSchema.parse({
        recorders: [
          {
            vrcode: "VR_TEST",
            status: "online",
            activityTimeline: [
              {
                observedAt: "2026-05-28T00:01:00Z",
                messageCount: 2,
                byteCount: 1024,
                buckets: [
                  {
                    bucketStartedAt: "2026-05-28T00:00:00Z",
                    bucketSeconds: 60,
                    messageCount: 2,
                    byteCount: 1024,
                    roomCount: 1
                  }
                ]
              }
            ]
          }
        ]
      }).recorders?.[0]?.activityTimeline?.[0]?.buckets?.[0]
    ).toMatchObject({
      bucketStartedAt: "2026-05-28T00:00:00Z",
      messageCount: 2
    });
  });

  it("accepts test tool capability flags", () => {
    expect(
      runtimeCapabilitiesSchema.parse({
        canUseTestTools: true
      })
    ).toEqual({
      canUseTestTools: true
    });
  });
});

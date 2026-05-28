import { describe, expect, it } from "vitest";

import {
  runtimeCommandResponseSchema,
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
});

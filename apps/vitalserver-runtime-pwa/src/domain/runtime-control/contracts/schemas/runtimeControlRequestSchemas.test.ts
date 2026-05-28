import { describe, expect, it } from "vitest";

import {
  runtimeRepairProxyRequestSchema,
  runtimeTestKitVirtualRecorderStartRequestSchema,
  runtimeUpdateBundleRequestSchema
} from "./runtimeControlRequestSchemas";

describe("runtime control request schemas", () => {
  it("rejects empty update bundle paths", () => {
    expect(() =>
      runtimeUpdateBundleRequestSchema.parse({
        bundle: {
          kind: "localPath",
          value: " "
        }
      })
    ).toThrow();
  });

  it("rejects invalid proxy ports", () => {
    expect(() =>
      runtimeRepairProxyRequestSchema.parse({
        proxyPort: 70_000
      })
    ).toThrow();
  });

  it("requires enough beds for TestKit VRecorders", () => {
    expect(() =>
      runtimeTestKitVirtualRecorderStartRequestSchema.parse({
        scenario: "normal",
        signalProfile: "normal",
        recorders: 2,
        bedRoomNames: ["bed-1"],
        vrcode: null,
        version: "testkit",
        intervalSeconds: 1,
        durationSeconds: null,
        maxMessages: null,
        shiftTime: true,
        generateFrames: true
      })
    ).toThrow();
  });
});

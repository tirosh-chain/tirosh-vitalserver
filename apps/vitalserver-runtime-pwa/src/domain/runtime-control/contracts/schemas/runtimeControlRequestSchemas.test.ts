import { describe, expect, it } from "vitest";

import {
  runtimeRepairProxyRequestSchema,
  runtimeTestKitCreateBedsRequestSchema,
  runtimeTestKitVirtualRecorderStartRequestSchema,
  runtimeLogTextRequestSchema,
  runtimeUninstallRequestSchema,
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

  it("requires proxy ports because the Swift API decoder requires the key", () => {
    expect(() => runtimeRepairProxyRequestSchema.parse({})).toThrow();
  });

  it("requires uninstall clean because the Swift API decoder requires the key", () => {
    expect(() => runtimeUninstallRequestSchema.parse({})).toThrow();
  });

  it("requires complete log text requests because the Swift API decoder requires every key", () => {
    expect(() =>
      runtimeLogTextRequestSchema.parse({
        source: "containers",
        lineLimit: 100
      })
    ).toThrow();
  });

  it("requires TestKit bed defaults that Swift encodes from native UI", () => {
    expect(() =>
      runtimeTestKitCreateBedsRequestSchema.parse({
        count: 1,
        prefix: "testbed"
      })
    ).toThrow();
  });

  it("requires either a TestKit bed count or explicit room names", () => {
    expect(() =>
      runtimeTestKitCreateBedsRequestSchema.parse({
        count: null,
        roomNames: [],
        prefix: "testbed",
        adminUserId: "admin"
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

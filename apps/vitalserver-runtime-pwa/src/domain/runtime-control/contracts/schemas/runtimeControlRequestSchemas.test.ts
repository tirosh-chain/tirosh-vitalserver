import { describe, expect, it } from "vitest";

import {
  runtimeLogTextRequestSchema,
  runtimeUninstallRequestSchema,
  runtimeUpdateBundleRequestSchema,
  vitalDBBedVisibilityRequestSchema,
  vitalDBRecorderVisibilityRequestSchema
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

  it("requires non-empty VitalDB visibility command identity lists", () => {
    expect(() =>
      vitalDBRecorderVisibilityRequestSchema.parse({
        vrcodes: []
      })
    ).toThrow();
    expect(() =>
      vitalDBBedVisibilityRequestSchema.parse({
        bedIDs: []
      })
    ).toThrow();

    expect(
      vitalDBRecorderVisibilityRequestSchema.parse({
        vrcodes: ["VR_A"]
      })
    ).toEqual({
      vrcodes: ["VR_A"]
    });
    expect(
      vitalDBBedVisibilityRequestSchema.parse({
        bedIDs: ["bed-a"]
      })
    ).toEqual({
      bedIDs: ["bed-a"]
    });
  });

});

import { describe, expect, it } from "vitest";

import {
  testKitCreateBedsRequest,
  testKitDeleteBedsRequest,
  testKitSessionSelectionRequest
} from "./requestBuilders";

describe("console request builders", () => {
  it("builds TestKit bed creation requests with Swift decoder defaults", () => {
    expect(testKitCreateBedsRequest(1, "testbed")).toEqual({
      count: 1,
      roomNames: [],
      prefix: "testbed",
      adminUserId: "admin"
    });
  });

  it("trims and validates TestKit bed names before deleting", () => {
    expect(testKitDeleteBedsRequest([" OR-A "])).toEqual({
      roomNames: ["OR-A"]
    });
  });

  it("rejects blank TestKit session ids before sending commands", () => {
    expect(() => testKitSessionSelectionRequest(" ")).toThrow(
      "Console request validation failed"
    );
  });
});

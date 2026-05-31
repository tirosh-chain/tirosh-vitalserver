import { describe, expect, it } from "vitest";

import {
  testKitCreateBedsRequest,
  testKitDeleteBedsRequest,
  testKitSessionSelectionRequest
} from "./requestBuilders";

describe("console request builders", () => {
  it("builds TestKit bed creation requests with Swift decoder defaults", () => {
    expect(testKitCreateBedsRequest(1, "testkit-bed")).toEqual({
      count: 1,
      roomNames: [],
      prefix: "testkit-bed",
      adminUserId: "admin"
    });
  });

  it("trims and validates TestKit bed names before deleting", () => {
    expect(testKitDeleteBedsRequest([" OR-A "])).toEqual({
      roomNames: ["OR-A"]
    });
  });

  it("normalizes blank TestKit session ids to null", () => {
    expect(testKitSessionSelectionRequest(" ")).toEqual({
      sessionID: null
    });
  });
});

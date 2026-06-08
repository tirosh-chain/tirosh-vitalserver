import { describe, expect, it } from "vitest";

import {
  RuntimeControlAPIError,
  RuntimeControlContractError,
  RuntimeControlNetworkError,
  RuntimeControlValidationError,
  summarizeRuntimeControlError
} from "./runtimeControlError";

describe("runtime control error summaries", () => {
  it("summarizes API error responses", () => {
    expect(
      summarizeRuntimeControlError(
        new RuntimeControlAPIError(
          "missing route",
          404,
          JSON.stringify({
            code: "routeNotFound",
            message: "missing route"
          })
        )
      )
    ).toMatchObject({
      kind: "api",
      title: "Runtime Control API returned HTTP 404",
      detail: "routeNotFound: missing route"
    });
  });

  it("summarizes contract validation failures", () => {
    expect(
      summarizeRuntimeControlError(
        new RuntimeControlContractError(
          "/runtime/overview",
          new Error("bad schema")
        )
    )
    ).toMatchObject({
      kind: "contract",
      title: "Runtime Control API contract mismatch"
    });
  });

  it("includes contract issue details in contract summaries", () => {
    const zodLikeError = {
      issues: [
        {
          path: ["status", "runtimeState"],
          message: "Invalid enum value. Expected 'installing' | 'updating' | ...",
          code: "invalid_enum_value"
        }
      ]
    };

    expect(
      summarizeRuntimeControlError(
        new RuntimeControlContractError("/runtime/overview", zodLikeError)
      )
    ).toMatchObject({
      kind: "contract",
      detail: expect.stringContaining("status.runtimeState"),
      title: "Runtime Control API contract mismatch"
    });
  });

  it("summarizes network failures", () => {
    expect(
      summarizeRuntimeControlError(new TypeError("Failed to fetch"))
    ).toMatchObject({
      kind: "network",
      title: "Runtime Control API is unreachable"
    });
  });

  it("includes the attempted URL for Runtime Control network failures", () => {
    expect(
      summarizeRuntimeControlError(
        new RuntimeControlNetworkError(
          "http://127.0.0.1:18321/runtime/overview",
          new TypeError("Failed to fetch")
        )
      )
    ).toMatchObject({
      kind: "network",
      title: "Runtime Control API is unreachable",
      detail:
        "The Remote Console tried http://127.0.0.1:18321/runtime/overview, but the Runtime Control API did not respond. Failed to fetch"
    });
  });

  it("summarizes request validation failures", () => {
    expect(
      summarizeRuntimeControlError(
        new RuntimeControlValidationError("invalid", ["bundle.value is required"])
      )
    ).toMatchObject({
      kind: "validation",
      title: "Invalid request",
      detail: "bundle.value is required"
    });
  });
});

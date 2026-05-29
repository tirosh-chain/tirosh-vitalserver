import { describe, expect, it } from "vitest";

import {
  RuntimeControlValidationError,
  summarizeRuntimeControlError
} from "./runtimeControlError";

describe("runtime control error summaries", () => {
  it("summarizes API error responses", () => {
    expect(
      summarizeRuntimeControlError({
        name: "RuntimeControlAPIError",
        status: 404,
        body: JSON.stringify({
          code: "routeNotFound",
          message: "missing route"
        })
      })
    ).toMatchObject({
      kind: "api",
      title: "Runtime Control API returned HTTP 404",
      detail: "routeNotFound: missing route"
    });
  });

  it("summarizes contract validation failures", () => {
    expect(
      summarizeRuntimeControlError({
        name: "RuntimeControlContractError",
        path: "/runtime/overview"
      })
    ).toMatchObject({
      kind: "contract",
      title: "Runtime Control API contract mismatch"
    });
  });

  it("summarizes network failures", () => {
    expect(summarizeRuntimeControlError(new TypeError("Failed to fetch"))).toMatchObject({
      kind: "network",
      title: "Runtime Control API is unreachable"
    });
  });

  it("includes the attempted URL for Runtime Control network failures", () => {
    expect(
      summarizeRuntimeControlError({
        name: "RuntimeControlNetworkError",
        url: "http://127.0.0.1:18321/runtime/overview",
        cause: new TypeError("Failed to fetch")
      })
    ).toMatchObject({
      kind: "network",
      title: "Runtime Control API is unreachable",
      detail:
        "The PWA tried http://127.0.0.1:18321/runtime/overview, but the local Runtime Control API did not respond. Failed to fetch"
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

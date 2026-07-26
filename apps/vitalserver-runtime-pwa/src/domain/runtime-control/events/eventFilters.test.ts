import { describe, expect, it } from "vitest";

import { runtimeEventTypes, sinceForPeriod } from "./eventFilters";

describe("runtime event filters", () => {
  it("derives a since timestamp from the selected period", () => {
    expect(sinceForPeriod("1h", new Date("2026-05-29T00:00:00.000Z"))).toBe(
      "2026-05-28T23:00:00.000Z"
    );
  });

  it("uses the 24h period for unknown values from persisted UI state", () => {
    expect(
      sinceForPeriod(
        "unexpected" as "24h",
        new Date("2026-05-29T00:00:00.000Z")
      )
    ).toBe("2026-05-28T00:00:00.000Z");
  });

  it("uses the contract event type list for UI filters", () => {
    expect(runtimeEventTypes).toEqual([
      "operation-accepted",
      "operation-running",
      "operation-completed",
      "operation-failed",
      "operation-cancelled",
      "operation-interrupted"
    ]);
  });
});

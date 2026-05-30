import { describe, expect, it } from "vitest";
import { formatVitalRecorderObservationMetric } from "@/domain/runtime-control/formatting/vitalRecorder";

describe("formatVitalRecorderObservationMetric", () => {
  it("does not display unavailable VitalDB observation metrics as zero", () => {
    expect(
      formatVitalRecorderObservationMetric(
        {
          source: "unavailable",
          activeConnections: 2,
          knownRecorders: 0
        },
        "knownRecorders"
      )
    ).toBe("Not reported");
  });

  it("displays metrics owned by VitalDB observation", () => {
    expect(
      formatVitalRecorderObservationMetric(
        {
          source: "vitalDBObservation",
          knownRecorders: 2
        },
        "knownRecorders"
      )
    ).toBe(2);
  });
});

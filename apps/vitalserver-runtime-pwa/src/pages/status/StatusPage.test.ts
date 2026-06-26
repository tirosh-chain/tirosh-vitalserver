import { describe, expect, it } from "vitest";
import {
  formatVitalRecorderConnectionMetric,
  formatVitalRecorderObservationMetric
} from "@/domain/runtime-control/formatting/vitalRecorder";
import { recorderIngressQueueStatus } from "./StatusPage";

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
    ).toBe("VitalDB observation unavailable");
  });

  it("keeps missing Vital Recorder summary source distinct from unavailable source", () => {
    expect(
      formatVitalRecorderObservationMetric(
        {
          knownRecorders: 0
        } as unknown as Parameters<typeof formatVitalRecorderObservationMetric>[0],
        "knownRecorders"
      )
    ).toBe("Vital Recorder source not reported");
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

  it("does not display missing active recorder connections as zero", () => {
    expect(
      formatVitalRecorderConnectionMetric({
        source: "vitalDBObservation"
      })
    ).toBe("Not reported");
  });

  it("displays active recorder connections when reported by recorder ingress", () => {
    expect(
      formatVitalRecorderConnectionMetric({
        source: "unavailable",
        activeConnections: 2
      })
    ).toBe(2);
  });
});

describe("recorderIngressQueueStatus", () => {
  it("does not expose raw command failure text while recorder ingress is not ready", () => {
    expect(
      recorderIngressQueueStatus({
        recorderIngressHTTP: "failed",
        recorderIngressStatus: null,
        recorderIngressStatusReadState: "commandFailed",
        recorderIngressStatusReadError:
          "command-failed-7 exitCode=7 stderr=curl: (7) Failed to connect to 127.0.0.1 port 80"
      } as Parameters<typeof recorderIngressQueueStatus>[0])
    ).toBe("Not ready");
  });

  it("uses read state instead of inferring readiness from read error text", () => {
    expect(
      recorderIngressQueueStatus({
        recorderIngressHTTP: "failed",
        recorderIngressStatus: null,
        recorderIngressStatusReadState: "commandFailed",
        recorderIngressStatusReadError: null
      } as Parameters<typeof recorderIngressQueueStatus>[0])
    ).toBe("Not ready");
  });
});

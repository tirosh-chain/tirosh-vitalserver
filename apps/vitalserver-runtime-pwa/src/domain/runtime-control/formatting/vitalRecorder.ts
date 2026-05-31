import type { RuntimeControlOverview } from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";

type RuntimeVitalRecorderSummary = NonNullable<
  RuntimeControlOverview["vitalRecorder"]
>;

type VitalRecorderObservationMetric = keyof Pick<
  RuntimeVitalRecorderSummary,
  | "knownRecorders"
  | "onlineRecorders"
  | "staleRecorders"
  | "knownBeds"
  | "recorderAnomalies"
>;

export function formatVitalRecorderObservationMetric(
  recorder: RuntimeVitalRecorderSummary | null | undefined,
  key: VitalRecorderObservationMetric
): number | string {
  if (recorder?.source !== "vitalDBObservation") {
    return NOT_REPORTED;
  }
  return recorder[key] ?? NOT_REPORTED;
}

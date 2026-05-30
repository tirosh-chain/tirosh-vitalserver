import type { RuntimeControlOverview } from "@/domain/runtime-control/contracts/runtimeControlTypes";

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
    return "Not reported";
  }
  return recorder[key] ?? "Not reported";
}

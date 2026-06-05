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

const VITALDB_OBSERVATION_UNAVAILABLE = "VitalDB observation unavailable";
const VITAL_RECORDER_SOURCE_NOT_REPORTED = "Vital Recorder source not reported";

export function formatVitalRecorderObservationMetric(
  recorder: RuntimeVitalRecorderSummary | null | undefined,
  key: VitalRecorderObservationMetric
): number | string {
  if (!recorder?.source) {
    return VITAL_RECORDER_SOURCE_NOT_REPORTED;
  }
  if (recorder.source === "unavailable") {
    return VITALDB_OBSERVATION_UNAVAILABLE;
  }
  if (recorder.source !== "vitalDBObservation") {
    return NOT_REPORTED;
  }
  return recorder[key] ?? NOT_REPORTED;
}

export function formatVitalRecorderConnectionMetric(
  recorder: RuntimeVitalRecorderSummary | null | undefined
): number | string {
  return recorder?.activeConnections ?? NOT_REPORTED;
}

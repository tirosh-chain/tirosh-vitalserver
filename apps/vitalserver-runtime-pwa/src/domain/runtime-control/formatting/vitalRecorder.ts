import { NOT_REPORTED } from "@/domain/runtime-control/formatting/reported";
import type { VitalDBRecorders } from "@/domain/runtime-control/contracts/runtimeControlTypes";

export type RuntimeVitalRecorderSummary = {
  source: "vitalDBObservation" | "unavailable";
  activeConnections?: number | null;
  knownRecorders?: number | null;
  onlineRecorders?: number | null;
  staleRecorders?: number | null;
  knownBeds?: number | null;
  recorderAnomalies?: number | null;
  observedAt?: string | null;
};

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

export function vitalRecorderSummaryFromHistory(
  history: VitalDBRecorders | undefined
): RuntimeVitalRecorderSummary | undefined {
  if (!history) {
    return undefined;
  }
  const ingress = history.recorderIngressStatusRead?.document;
  if (history.state === "readFailed") {
    return {
      source: "unavailable",
      activeConnections: ingress?.activeRecorderConnections ?? null,
      knownRecorders: null,
      onlineRecorders: null,
      staleRecorders: null,
      knownBeds: null,
      recorderAnomalies: null,
      observedAt: null
    };
  }
  return {
    source: "vitalDBObservation",
    activeConnections: ingress?.activeRecorderConnections ?? null,
    knownRecorders: history.summary.knownRecorders,
    onlineRecorders: history.summary.onlineRecorders,
    staleRecorders: history.summary.staleRecorders,
    knownBeds: history.summary.knownBeds,
    recorderAnomalies: history.summary.recorderAnomalies,
    observedAt: history.updatedAt
  };
}

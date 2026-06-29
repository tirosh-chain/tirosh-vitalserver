export const recorderIngressReplayMemoryGuardStatusValues = Object.freeze([
  "healthy",
  "warm",
  "hot",
  "critical",
  "missing",
  "stale",
  "invalid",
  "failed",
  "unavailable",
  "disabled",
]);

export type RuntimeMemoryGuardReadStatus =
  | "loaded"
  | "missing"
  | "stale"
  | "invalid"
  | "failed"
  | "unavailable";

export type VitalServerMemoryGuard = {
  memoryUsedBytes: number;
  memoryLimitBytes: number;
  usageRatio: number;
  observedAt: string;
};

export type RuntimeMemoryGuardRead =
  | {
      status: "loaded";
      vitalServer: VitalServerMemoryGuard;
    }
  | {
      status: Exclude<RuntimeMemoryGuardReadStatus, "loaded">;
      message: string;
    };

export const runtimeEventTypeValues = [
  "status-changed",
  "progress-updated",
  "health-observed",
  "recovery-triggered",
  "recovery-completed",
  "recovery-suppressed",
  "recovery-deferred",
  "domain-error-observed",
  "vm-error-observed",
  "container-observed",
  "audit-proxy-observed",
  "vitaldb-observed",
  "vitaldb-observer-unhealthy",
  "vitaldb-anomaly-detected",
  "watchdog-skipped",
  "recovery-planned",
  "service-restart-dispatched",
  "observability-store-failed",
  "runtime-status-observed",
  "guest-state-observed",
  "runtime-command-started",
  "runtime-command-completed",
  "runtime-command-failed"
] as const;

export type RuntimeEventTypeValue = (typeof runtimeEventTypeValues)[number];

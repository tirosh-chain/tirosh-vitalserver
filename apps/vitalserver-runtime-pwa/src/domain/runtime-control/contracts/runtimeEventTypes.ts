export const runtimeEventTypeValues = [
  "operation-accepted",
  "operation-running",
  "operation-completed",
  "operation-failed",
  "operation-cancelled"
] as const;

export type RuntimeEventTypeValue = (typeof runtimeEventTypeValues)[number];

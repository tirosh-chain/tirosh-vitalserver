export type SendDataPayloadSummary = {
  bytes?: number;
  vrcode?: string;
  [key: string]: unknown;
};

export type SendDataContext = {
  request_id?: string;
  connection_id?: string;
  joined_vrcode?: string | null;
  pending_binary_event?: unknown;
  last_command?: unknown;
  metrics_vrcode?: string | null;
  ip?: Record<string, unknown>;
  [key: string]: unknown;
};

export type SendDataFailureRecord = {
  reason: string;
  message: string;
  occurredAt?: string;
};

export type SendDataSpoolItemState =
  | "pending"
  | "in_flight"
  | "replayed"
  | "retryable_failed"
  | "dead_lettered";

export type SendDataSpoolItem = {
  schemaVersion: 1;
  id: string;
  state: SendDataSpoolItemState;
  vrcode: string | null;
  connectionId: string | null | undefined;
  requestId: string | null | undefined;
  receivedAt: string | null;
  payloadEncoding: "binary" | "string" | null;
  payloadBytes: number;
  payloadBase64: string | null;
  payloadSummary: SendDataPayloadSummary | null;
  attemptCount: number;
  lastAttemptAt: string | null;
  lastFailure: SendDataFailureRecord | null;
  replayedAt?: string;
  deadLetteredAt?: string;
  rawDocument?: string | null;
};

export type SendDataSpoolItemResult =
  | {
      ok: true;
      item: SendDataSpoolItem;
    }
  | {
      ok: false;
      reason: string;
      message: string;
    };

export type SendDataSpoolConfig = {
  enabled: boolean;
  mode: string;
  storage?: string;
  listKey?: string;
  inFlightListKey?: string;
  replayedListKey?: string;
  deadLetterListKey?: string;
  maxPendingItems: number;
  maxPendingBytes: number;
  maxPayloadBytes: number;
  replay?: SendDataReplayConfig;
};

export type SendDataReplayConfig = {
  enabled?: boolean;
  intervalMs?: number;
  batchSize?: number;
  maxAttempts?: number;
  maxBytesPerSecond?: number;
  targetTimeoutMs?: number;
  adaptive?: SendDataReplayAdaptiveConfig;
};

export type SendDataReplayAdaptiveConfig = {
  enabled?: boolean;
  minBytesPerSecond?: number;
  maxBytesPerSecond?: number;
};

export type SendDataReplayAttemptOptions = {
  now?: () => Date;
};

export type SendDataReplayAttemptResult =
  | {
      ok: true;
      item: SendDataSpoolItem;
    }
  | {
      ok: false;
      reason: string;
      message: string;
    };

export type SendDataReplayCompletionAction = "mark_replayed" | "dead_letter" | "requeue";

export type SendDataReplayCompletionResult = {
  action: SendDataReplayCompletionAction;
  item: SendDataSpoolItem;
};

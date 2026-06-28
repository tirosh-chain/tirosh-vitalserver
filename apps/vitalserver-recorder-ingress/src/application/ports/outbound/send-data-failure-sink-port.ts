export type SendDataFailureLogEvent = {
  schemaVersion: 1;
  observedAt: string;
  kind: string;
  reason: string;
  message: string;
  itemId?: string | null;
  state?: string | null;
  vrcode?: string | null;
  connectionId?: string | null;
  requestId?: string | null;
  receivedAt?: string | null;
  payloadEncoding?: string | null;
  payloadBytes?: number;
  payloadSha256?: string | null;
  rawDocumentBytes?: number;
  rawDocumentSha256?: string | null;
  attemptCount?: number;
  lastAttemptAt?: string | null;
  replayedAt?: string | null;
  deadLetteredAt?: string | null;
};

export type SendDataFailureSinkPort = {
  record(event: SendDataFailureLogEvent): void;
};

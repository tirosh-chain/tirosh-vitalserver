export type SendDataRawArchiveFinalizationTrigger =
  | "inactivity"
  | "shutdown"
  | "explicit";

export type SendDataRawArchiveExportJob = {
  schemaVersion: 2;
  jobId: string;
  requestId: string | null;
  trigger: SendDataRawArchiveFinalizationTrigger;
  vrcode: string;
  archivePath: string;
  startOffset: number;
  endOffset: number;
  state: "pending" | "running" | "uploaded" | "retryable_failed" | "failed";
  attempts: number;
  maxAttempts: number;
  createdAt: string;
  updatedAt: string;
  startedAt: string | null;
  completedAt: string | null;
  nextAttemptAt: string | null;
  lastFailure: { reason: string; message: string; occurredAt: string } | null;
  result: unknown | null;
};

export type SendDataRawArchiveExportCheckpoint = {
  vrcode: string;
  archivePath: string;
  endOffset: number;
  jobId: string;
  requestId?: string | null;
  completedAt: string;
};

export type SendDataRawArchiveExportObservedCursor = {
  vrcode: string;
  archivePath: string;
  endOffset: number;
  observedAt: string;
};

export type SendDataRawArchiveFinalizationRequest = {
  requestId: string;
  vrcode: string;
  reason: "lab_session_finished";
  requestedAt: string;
};

export type SendDataRawArchiveExportStateDocument = {
  schemaVersion: 2;
  updatedAt: string;
  observedByVrcode: Record<string, SendDataRawArchiveExportObservedCursor>;
  checkpointsByVrcode: Record<string, SendDataRawArchiveExportCheckpoint>;
  pendingFinalizations: SendDataRawArchiveFinalizationRequest[];
  activeJob: SendDataRawArchiveExportJob | null;
  history: SendDataRawArchiveExportJob[];
};

export type SendDataRawArchiveExportJobStorePort = {
  read(): SendDataRawArchiveExportStateDocument;
  write(document: SendDataRawArchiveExportStateDocument): void;
};

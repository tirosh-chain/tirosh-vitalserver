export type SendDataRawArchiveExportJob = {
  schemaVersion: 1;
  jobId: string;
  archivePath: string;
  archiveCursor: number;
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
  archivePath: string;
  archiveCursor: number;
  jobId: string;
  completedAt: string;
};

export type SendDataRawArchiveExportObservedCursor = {
  archivePath: string;
  archiveCursor: number;
  observedAt: string;
};

export type SendDataRawArchiveExportStateDocument = {
  schemaVersion: 1;
  updatedAt: string;
  lastObserved: SendDataRawArchiveExportObservedCursor | null;
  checkpoint: SendDataRawArchiveExportCheckpoint | null;
  activeJob: SendDataRawArchiveExportJob | null;
  history: SendDataRawArchiveExportJob[];
};

export type SendDataRawArchiveExportJobStorePort = {
  read(): SendDataRawArchiveExportStateDocument;
  write(document: SendDataRawArchiveExportStateDocument): void;
};

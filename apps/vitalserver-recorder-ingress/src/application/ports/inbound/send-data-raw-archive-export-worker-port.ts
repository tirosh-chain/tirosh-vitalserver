export type SendDataRawArchiveExportWorkerRunResult = {
  ok: boolean;
  state: string;
  disabled?: boolean;
  reason?: string;
  message?: string;
  jobId?: string;
};

export type SendDataRawArchiveExportWorkerRunOptions = {
  trigger?: "inactivity" | "shutdown" | "explicit";
};

export type SendDataRawArchiveFinalizationRequestInput = {
  vrcodes: string[];
  reason: "lab_session_finished";
};

export type SendDataRawArchiveFinalizationRequestResult = {
  ok: boolean;
  state: "accepted" | "rejected";
  requestIds?: string[];
  reason?: string;
  message?: string;
};

export type SendDataRawArchiveFinalizationStatusReadResult = {
  ok: boolean;
  state: "loaded" | "rejected";
  finalization?: {
    state: "queued" | "processing" | "retrying" | "exported" | "published" | "failed" | "partial" | "missing";
    requests: Array<{
      requestId: string;
      vrcode: string | null;
      state: "queued" | "processing" | "retrying" | "exported" | "published" | "failed" | "missing";
      attempts: number;
      maxAttempts: number | null;
      requestedAt: string | null;
      updatedAt: string | null;
      startedAt: string | null;
      completedAt: string | null;
      nextAttemptAt: string | null;
      failure: { reason: string; message: string; occurredAt: string } | null;
    }>;
    updatedAt: string | null;
  };
  reason?: string;
  message?: string;
};

export type SendDataRawArchiveExportWorkerPort = {
  start(): void;
  stop(): void;
  runOnce(options?: SendDataRawArchiveExportWorkerRunOptions): Promise<SendDataRawArchiveExportWorkerRunResult>;
  requestFinalization(input: SendDataRawArchiveFinalizationRequestInput): Promise<SendDataRawArchiveFinalizationRequestResult>;
  finalizationStatus(requestIds: string[]): SendDataRawArchiveFinalizationStatusReadResult;
};

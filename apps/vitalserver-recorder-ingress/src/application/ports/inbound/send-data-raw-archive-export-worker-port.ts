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
  reason: "lab_session_stopped" | "lab_recorder_stopped";
};

export type SendDataRawArchiveFinalizationRequestResult = {
  ok: boolean;
  state: "accepted" | "rejected";
  requestIds?: string[];
  reason?: string;
  message?: string;
};

export type SendDataRawArchiveExportWorkerPort = {
  start(): void;
  stop(): void;
  runOnce(options?: SendDataRawArchiveExportWorkerRunOptions): Promise<SendDataRawArchiveExportWorkerRunResult>;
  requestFinalization(input: SendDataRawArchiveFinalizationRequestInput): Promise<SendDataRawArchiveFinalizationRequestResult>;
};

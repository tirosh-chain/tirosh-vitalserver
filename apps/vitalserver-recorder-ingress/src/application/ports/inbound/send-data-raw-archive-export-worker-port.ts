export type SendDataRawArchiveExportWorkerRunResult = {
  ok: boolean;
  state: string;
  disabled?: boolean;
  reason?: string;
  message?: string;
  jobId?: string;
};

export type SendDataRawArchiveExportWorkerRunOptions = {
  trigger?: "inactivity" | "shutdown";
};

export type SendDataRawArchiveExportWorkerPort = {
  start(): void;
  stop(): void;
  runOnce(options?: SendDataRawArchiveExportWorkerRunOptions): Promise<SendDataRawArchiveExportWorkerRunResult>;
};

export type SendDataReplayWorkerRunResult =
  | {
      ok: true;
      processed: number;
      disabled?: boolean;
    }
  | {
      ok: false;
      processed: number;
      reason: "already_running" | "spool_unavailable" | "spool_write_failed";
      message?: string;
    };

export type SendDataReplayWorkerPort = {
  start(): void;
  stop(): void;
  runOnce(): Promise<SendDataReplayWorkerRunResult>;
};

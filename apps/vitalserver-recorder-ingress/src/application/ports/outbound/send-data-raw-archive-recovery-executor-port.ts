export type SendDataRawArchiveRecoveryRequest = {
  rawArchivePath: string;
  outputDir: string;
  vitalserverUrl: string;
  endpoint: string;
  timeoutMs: number;
  vrcode: string;
  startOffset: number;
  endOffset: number;
};

export type SendDataRawArchiveRecoveryResult =
  | {
      ok: true;
      statusCode: number;
      response: unknown;
    }
  | {
      ok: false;
      reason: "not_configured" | "request_failed" | "http_failed" | "invalid_response";
      message: string;
      statusCode?: number;
      response?: unknown;
    };

export type SendDataRawArchiveRecoveryExecutorPort = {
  recover(request: SendDataRawArchiveRecoveryRequest): Promise<SendDataRawArchiveRecoveryResult>;
};

import type { RecoveryArtifactReceipt } from "./send-data-raw-archive-export-job-store-port";

export type SendDataRawArchiveExportRequest = {
  rawArchivePath: string;
  outputDir: string;
  timeoutMs: number;
  vrcode: string;
  startOffset: number;
  endOffset: number;
};

export type SendDataRawArchiveExportResult =
  | {
      ok: true;
      statusCode: number;
      artifacts: RecoveryArtifactReceipt[];
      response: { operation: "export"; artifacts: RecoveryArtifactReceipt[] };
    }
  | {
      ok: false;
      reason: "not_configured" | "request_failed" | "http_failed" | "invalid_response";
      message: string;
      statusCode?: number;
      response?: unknown;
    };

export type SendDataRawArchiveExporterPort = {
  export(request: SendDataRawArchiveExportRequest): Promise<SendDataRawArchiveExportResult>;
};

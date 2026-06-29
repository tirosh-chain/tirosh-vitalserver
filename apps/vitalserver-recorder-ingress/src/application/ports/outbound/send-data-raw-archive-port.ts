import type { SendDataSpoolItem } from "../../../domain/send-data-spool-types";

export type SendDataRawArchiveAppendResult =
  | {
      ok: true;
      archiveId: string;
      path: string;
      offset: number;
      bytes: number;
    }
  | {
      ok: false;
      reason?: string;
      message?: string;
      error?: Error;
    };

export type SendDataRawArchivePort = {
  append(item: SendDataSpoolItem): SendDataRawArchiveAppendResult | Promise<SendDataRawArchiveAppendResult>;
};

import type {
  SendDataContext,
  SendDataPayloadSummary,
  SendDataSpoolItem,
} from "../../../domain/send-data-spool-types";

export type SendDataIngressResult =
  | {
      ok: true;
      outcome: "accepted" | "spooled";
      mode?: string;
      item?: SendDataSpoolItem;
    }
  | {
      ok: false;
      outcome: "invalid_payload" | "rejected" | "raw_archive_write_failed" | "spool_write_failed";
      reason: string;
      message: string;
    };

export type SendDataIngressPort = {
  record(
    payload: unknown,
    context: SendDataContext,
    payloadSummary: SendDataPayloadSummary
  ): Promise<SendDataIngressResult>;
};

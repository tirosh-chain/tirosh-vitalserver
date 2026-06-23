export type SendDataIngressResult =
  | {
      ok: true;
      outcome: "accepted" | "spooled";
      mode?: string;
      item?: unknown;
    }
  | {
      ok: false;
      outcome: "invalid_payload" | "rejected" | "spool_write_failed";
      reason: string;
      message: string;
    };

export type SendDataIngressPort = {
  record(payload: unknown, context: Record<string, any>, payloadSummary: Record<string, any>): Promise<SendDataIngressResult>;
};

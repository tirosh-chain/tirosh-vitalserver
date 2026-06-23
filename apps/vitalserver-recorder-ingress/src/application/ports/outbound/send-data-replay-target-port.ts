import type { SendDataSpoolItem } from "../../../domain/send-data-spool-types";

export type SendDataReplayTargetResult =
  | {
      ok: true;
    }
  | {
      ok: false;
      reason: string;
      message: string;
    };

export type SendDataReplayTargetPort = {
  send(item: SendDataSpoolItem | Partial<SendDataSpoolItem>): Promise<SendDataReplayTargetResult> | SendDataReplayTargetResult;
};

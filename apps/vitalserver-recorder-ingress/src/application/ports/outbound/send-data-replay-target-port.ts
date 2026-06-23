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
  send(item: Record<string, any>): Promise<SendDataReplayTargetResult> | SendDataReplayTargetResult;
};

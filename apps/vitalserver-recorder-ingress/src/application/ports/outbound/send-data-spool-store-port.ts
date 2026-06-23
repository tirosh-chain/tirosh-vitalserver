export type SendDataSpoolStoreClaim = {
  raw?: string;
  inFlightKey?: string;
};

export type SendDataSpoolStoreWriteResult = {
  ok: boolean;
  depth?: number | null;
  error?: Error;
  message?: string;
};

export type SendDataSpoolStoreClaimResult = {
  ok: boolean;
  item?: Record<string, any> | null;
  claim?: SendDataSpoolStoreClaim | null;
  reason?: string;
  message?: string;
  error?: Error;
  raw?: string;
};

export type SendDataSpoolAppendPort = {
  append(item: Record<string, any>): Promise<SendDataSpoolStoreWriteResult> | SendDataSpoolStoreWriteResult;
};

export type SendDataSpoolReplayPort = {
  claim(): Promise<SendDataSpoolStoreClaimResult> | SendDataSpoolStoreClaimResult;
  requeue(
    item: Record<string, any>,
    claim?: SendDataSpoolStoreClaim | null
  ): Promise<SendDataSpoolStoreWriteResult> | SendDataSpoolStoreWriteResult;
  markReplayed(
    item: Record<string, any>,
    claim?: SendDataSpoolStoreClaim | null
  ): Promise<SendDataSpoolStoreWriteResult> | SendDataSpoolStoreWriteResult;
  deadLetter(
    item: Record<string, any>,
    claim?: SendDataSpoolStoreClaim | null
  ): Promise<SendDataSpoolStoreWriteResult> | SendDataSpoolStoreWriteResult;
};

export type SendDataSpoolStorePort = SendDataSpoolAppendPort & SendDataSpoolReplayPort;

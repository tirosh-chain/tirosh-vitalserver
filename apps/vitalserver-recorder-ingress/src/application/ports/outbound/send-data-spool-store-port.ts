import type { SendDataSpoolItem } from "../../../domain/send-data-spool-types";

export type SendDataSpoolStoreClaim = {
  raw?: string;
  inFlightKey?: string;
};

export type SendDataSpoolStoreWriteResult = {
  ok: boolean;
  depth?: number | null;
  reason?: string;
  error?: Error;
  message?: string;
};

export type SendDataSpoolStoreClaimResult = {
  ok: boolean;
  item?: SendDataSpoolItem | null;
  claim?: SendDataSpoolStoreClaim | null;
  reason?: string;
  message?: string;
  error?: Error;
  raw?: string;
};

export type SendDataSpoolAppendPort = {
  append(item: SendDataSpoolItem): Promise<SendDataSpoolStoreWriteResult> | SendDataSpoolStoreWriteResult;
};

export type SendDataSpoolReplayPort = {
  claim(): Promise<SendDataSpoolStoreClaimResult> | SendDataSpoolStoreClaimResult;
  requeue(
    item: SendDataSpoolItem,
    claim?: SendDataSpoolStoreClaim | null
  ): Promise<SendDataSpoolStoreWriteResult> | SendDataSpoolStoreWriteResult;
  markReplayed(
    item: SendDataSpoolItem,
    claim?: SendDataSpoolStoreClaim | null
  ): Promise<SendDataSpoolStoreWriteResult> | SendDataSpoolStoreWriteResult;
  deadLetter(
    item: SendDataSpoolItem,
    claim?: SendDataSpoolStoreClaim | null
  ): Promise<SendDataSpoolStoreWriteResult> | SendDataSpoolStoreWriteResult;
};

export type SendDataSpoolStorePort = SendDataSpoolAppendPort & SendDataSpoolReplayPort;

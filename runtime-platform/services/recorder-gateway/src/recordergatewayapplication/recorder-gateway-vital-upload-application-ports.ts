import type { IncomingHttpHeaders } from "node:http";
import type { Readable } from "node:stream";

import type {
  RecorderVitalUploadDispatch,
  RecorderVitalUploadPublishOutcome,
  RecorderVitalUploadSourceReceipt,
} from "../recordergatewaydomain/recorder-gateway-vital-upload-contracts.js";

export interface RecorderVitalUploadMultipartSource {
  headers: IncomingHttpHeaders;
  body: Readable;
  receivedAt: string;
}

export interface RecorderVitalUploadSpool {
  initializeRecorderVitalUploadSpool(): Promise<void>;
  admitRecorderVitalUpload(
    source: RecorderVitalUploadMultipartSource,
  ): Promise<RecorderVitalUploadSourceReceipt>;
  readRecorderVitalUploadSourceReceipt(
    receiptId: string,
  ): Promise<RecorderVitalUploadSourceReceipt>;
  openRecorderVitalUploadContent(receiptId: string): Promise<Readable>;
  readRecorderVitalUploadDispatch(receiptId: string): Promise<RecorderVitalUploadDispatch>;
  commitRecorderVitalUploadDispatch(
    expectedRevision: number,
    next: RecorderVitalUploadDispatch,
  ): Promise<void>;
  listRecoverableRecorderVitalUploadDispatches(
    limit: number,
  ): Promise<RecorderVitalUploadDispatch[]>;
}

export interface RecorderVitalUploadArchivePublisher {
  publishRecorderVitalUpload(
    source: RecorderVitalUploadSourceReceipt,
    requestId: string,
    content: Readable,
  ): Promise<RecorderVitalUploadPublishOutcome>;
}

export interface RecorderVitalUploadClock {
  now(): string;
}

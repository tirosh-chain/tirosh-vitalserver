import type {
  RecorderObservabilityResourceType,
} from "../../../domain/recorder-observability";

export type RecorderObservabilityDisposition = "accepted" | "quarantined";

export type RecorderObservabilityLedgerRecord = {
  schemaVersion: 1;
  requestId: string;
  lineNumber: number;
  disposition: RecorderObservabilityDisposition;
  resourceType: RecorderObservabilityResourceType;
  vrcode: string;
  requestDeviceId: string;
  documentDeviceId: string | null;
  eventId: string | null;
  contentHash: string;
  rawDocument: string;
  receivedAt: string;
  sourceIp: string;
  quarantineReason: string | null;
};

export type RecorderObservabilityLedgerBatch = {
  schemaVersion: 1;
  requestId: string;
  receivedAt: string;
  records: RecorderObservabilityLedgerRecord[];
};

export type RecorderObservabilityAcceptedIdentity = {
  contentHash: string;
};

export interface RecorderObservabilityLedgerPort {
  findAccepted(
    vrcode: string,
    eventId: string,
  ): RecorderObservabilityAcceptedIdentity | null;
  persist(batch: RecorderObservabilityLedgerBatch): void;
}

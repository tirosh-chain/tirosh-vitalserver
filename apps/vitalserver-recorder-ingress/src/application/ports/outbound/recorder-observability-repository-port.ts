import type {
  CurrentProjection,
  ProjectionCandidate,
  RecorderObservabilityDocumentIdentity,
  RecorderObservabilityResourceType,
} from "../../../domain/recorder-observability";

export type PreparedRecorderObservabilityLine = {
  lineNumber: number;
  rawDocument: string;
  rawSha256: string;
  document: Record<string, unknown> | null;
  canonicalSha256: string | null;
  identity: Partial<RecorderObservabilityDocumentIdentity>;
  contractReceipt: string | null;
  failureCode: string | null;
  failureDetail: string | null;
};

export type RecorderObservabilityAdmissionBatch = {
  requestId: string;
  resourceType: RecorderObservabilityResourceType;
  vrcode: string;
  requestDeviceId: string;
  sourceIp: string;
  receivedAt: string;
  lines: PreparedRecorderObservabilityLine[];
};

export type RecorderObservabilityAdmissionCounts = {
  accepted: number;
  duplicates: number;
  quarantined: number;
};

export interface RecorderObservabilityRepositoryPort {
  ping(): Promise<void>;
  admit(
    batch: RecorderObservabilityAdmissionBatch,
  ): Promise<RecorderObservabilityAdmissionCounts>;
  listPendingProjection(limit: number): Promise<ProjectionCandidate[]>;
  readCurrent(
    vrcode: string,
    resourceType: RecorderObservabilityResourceType,
  ): Promise<CurrentProjection | null>;
  applyProjection(
    candidate: ProjectionCandidate,
    replaceCurrent: boolean,
  ): Promise<void>;
  failProjection(recordId: string, error: string): Promise<void>;
  listCurrentRecorders(): Promise<Array<Record<string, unknown>>>;
  readRecorderObservability(
    vrcode: string,
  ): Promise<Array<Record<string, unknown>>>;
  close(): Promise<void>;
}

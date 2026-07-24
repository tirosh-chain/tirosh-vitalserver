import type {
  CurrentProjection,
  ProjectionCandidate,
  RecorderObservabilityDocumentIdentity,
  RecorderObservabilityResourceType,
} from "../../../domain/recorder-observability";
import type {
  RecorderObservabilityExpectationCommand,
  RecorderObservabilityExpectationDecision,
} from "../../../domain/recorder-observability-expectation";
import type {
  RecorderObservabilityReportState,
  RecorderObservabilitySupportState,
} from "../../../domain/recorder-observability";
import type {
  RecorderOperationalHealthState,
} from "../../../domain/recorder-operational-health";
import type {
  RecorderObservabilityIncidentQuery,
  RecorderObservabilityIncidentRow,
  RecorderObservabilityTimelineQuery,
  RecorderObservabilityTimelineReadModel,
} from "../../../domain/recorder-observability-history";

export type RecorderObservabilitySummaryReadModel = {
  vrcode: string;
  supportState: RecorderObservabilitySupportState;
  supportSource: string | null;
  reportState: RecorderObservabilityReportState;
  profileState: string | null;
  collectionState: string | null;
  latestObservationReceivedAt: string | null;
  lastBootStartedAt: string | null;
  readIssueCount: number;
  operationalHealthState: RecorderOperationalHealthState;
  operationalIssueCount: number;
  expectedSince: string | null;
  recorderVersion: string | null;
  producerVersion: string | null;
  protocolVersion: string | null;
};

export type RecorderObservabilityDetailReadModel =
  RecorderObservabilitySummaryReadModel & {
    resources: Record<string, unknown> | null;
  };

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
  applyExpectationCommand(
    command: RecorderObservabilityExpectationCommand,
  ): Promise<RecorderObservabilityExpectationDecision>;
  listCurrentRecorders(): Promise<RecorderObservabilitySummaryReadModel[]>;
  readRecorderObservability(
    vrcode: string,
  ): Promise<RecorderObservabilityDetailReadModel[]>;
  readRecorderObservabilityTimeline(
    query: RecorderObservabilityTimelineQuery,
  ): Promise<RecorderObservabilityTimelineReadModel>;
  readRecorderObservabilityIncidents(
    query: RecorderObservabilityIncidentQuery,
  ): Promise<RecorderObservabilityIncidentRow[]>;
  close(): Promise<void>;
}

export type SendDataRawArchiveFinalizationTrigger =
  | "inactivity"
  | "shutdown"
  | "explicit";

export type RecoveryArtifactOrigin = "coldPathRecovery" | "productLabGenerated";

export type RecoveryArtifactReceipt = {
  artifactId: string;
  origin: RecoveryArtifactOrigin;
  producer: string;
  writerVersion: string;
  vrcode: string;
  roomNames: string[];
  sourceArchiveId: string;
  sourceStartOffset: number;
  sourceEndOffset: number;
  coverageStartedAt: number;
  coverageEndedAt: number;
  formatVersion: 3;
  sha256: string;
  filename: string;
  sizeBytes: number;
  createdAt: number;
  trackCount: number;
};

export type RecoveryArtifactPublishState =
  | "notRequested"
  | "published"
  | "unknownLegacy";

export type SendDataRawArchiveExportJob = {
  schemaVersion: 3;
  jobId: string;
  requestId: string | null;
  trigger: SendDataRawArchiveFinalizationTrigger;
  vrcode: string;
  archivePath: string;
  startOffset: number;
  endOffset: number;
  origin: RecoveryArtifactOrigin;
  state:
    | "export_pending"
    | "exporting"
    | "exported"
    | "export_retryable_failed"
    | "export_failed";
  publishState: RecoveryArtifactPublishState;
  artifacts: RecoveryArtifactReceipt[];
  attempts: number;
  maxAttempts: number;
  createdAt: string;
  updatedAt: string;
  startedAt: string | null;
  completedAt: string | null;
  nextAttemptAt: string | null;
  lastFailure: {
    stage: "export" | "unknownLegacyStage";
    reason: string;
    message: string;
    occurredAt: string;
  } | null;
  result: unknown | null;
};

export type SendDataRawArchiveExportCheckpoint = {
  origin: RecoveryArtifactOrigin;
  vrcode: string;
  archivePath: string;
  endOffset: number;
  jobId: string;
  requestId?: string | null;
  completedAt: string;
  artifactIds: string[];
  publishState: RecoveryArtifactPublishState;
};

export type SendDataRawArchiveExportObservedCursor = {
  vrcode: string;
  archivePath: string;
  endOffset: number;
  observedAt: string;
};

export type SendDataRawArchiveFinalizationRequest = {
  requestId: string;
  vrcode: string;
  reason: "lab_session_finished";
  requestedAt: string;
};

export type SendDataRawArchiveExportStateDocument = {
  schemaVersion: 3;
  updatedAt: string;
  observedByVrcode: Record<string, SendDataRawArchiveExportObservedCursor>;
  checkpointsByVrcode: Record<string, SendDataRawArchiveExportCheckpoint>;
  pendingFinalizations: SendDataRawArchiveFinalizationRequest[];
  activeJob: SendDataRawArchiveExportJob | null;
  history: SendDataRawArchiveExportJob[];
};

export type SendDataRawArchiveExportJobStorePort = {
  read(): SendDataRawArchiveExportStateDocument;
  write(document: SendDataRawArchiveExportStateDocument): void;
};

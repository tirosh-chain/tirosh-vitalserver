export type RecorderObservationPresentation = {
  readonly id?: string;
  readonly occurredAt?: unknown;
  readonly runtimeState?: unknown;
  readonly runtimeVersion?: unknown;
  readonly timeState?: unknown;
  readonly bootId?: unknown;
  readonly sequence?: unknown;
  readonly receivedAt?: unknown;
};

export type RecorderIncidentPresentation = {
  readonly id?: string;
  readonly code?: unknown;
  readonly message?: unknown;
  readonly occurredAt?: unknown;
  readonly dependency?: unknown;
  readonly retryable?: unknown;
  readonly receivedAt?: unknown;
};

export type RecorderArtifactPresentation = {
  readonly id?: string;
  readonly originalFileName?: unknown;
  readonly finalizationState?: unknown;
  readonly finalizedAt?: unknown;
  readonly byteSize?: unknown;
  readonly reportedBedName?: unknown;
  readonly attributionOutcome?: unknown;
  readonly uploadAttemptCount?: number;
  readonly indexingReceiptCount?: number;
};

export function presentRecorderObservation(
  item: unknown,
): RecorderObservationPresentation | undefined {
  if (!isRecord(item) || !isRecord(item.envelope)) {
    return undefined;
  }
  const runtime = isRecord(item.envelope.runtime)
    ? item.envelope.runtime
    : undefined;
  const recorderTime = isRecord(item.envelope.time)
    ? item.envelope.time
    : undefined;
  return {
    ...(typeof item.id === "string" && item.id !== "" ? { id: item.id } : {}),
    occurredAt: item.envelope.occurredAt,
    runtimeState: runtime?.state,
    runtimeVersion: runtime?.version,
    timeState: recorderTime?.state,
    bootId: item.envelope.bootId,
    sequence: item.envelope.sequence,
    receivedAt: item.receivedAt,
  };
}

export function presentRecorderIncident(
  item: unknown,
): RecorderIncidentPresentation | undefined {
  if (!isRecord(item) || !isRecord(item.runtimeIssue)) {
    return undefined;
  }
  return {
    ...(typeof item.id === "string" && item.id !== "" ? { id: item.id } : {}),
    code: item.runtimeIssue.code,
    message: item.runtimeIssue.message,
    occurredAt: item.occurredAt,
    dependency: item.runtimeIssue.dependency,
    retryable: item.runtimeIssue.retryable,
    receivedAt: item.receivedAt,
  };
}

export function presentRecorderArtifact(
  item: unknown,
): RecorderArtifactPresentation | undefined {
  if (
    !isRecord(item)
    || !isRecord(item.artifact)
    || !isRecord(item.attribution)
  ) {
    return undefined;
  }
  return {
    ...(typeof item.artifact.artifactId === "string"
      && item.artifact.artifactId !== ""
      ? { id: item.artifact.artifactId }
      : {}),
    originalFileName: item.artifact.originalFileName,
    finalizationState: item.artifact.finalizationState,
    finalizedAt: item.artifact.finalizedAt,
    byteSize: item.artifact.byteSize,
    reportedBedName: item.attribution.reportedBedName,
    attributionOutcome: item.attribution.outcome,
    ...(Array.isArray(item.uploadAttempts)
      ? { uploadAttemptCount: item.uploadAttempts.length }
      : {}),
    ...(Array.isArray(item.indexingReceipts)
      ? { indexingReceiptCount: item.indexingReceipts.length }
      : {}),
  };
}

export function displayByteSize(value: unknown): string {
  if (
    typeof value !== "number"
    || !Number.isSafeInteger(value)
    || value < 0
  ) {
    return "Not provided by owner";
  }
  if (value < 1024) {
    return `${value} B`;
  }
  if (value < 1024 * 1024) {
    return `${(value / 1024).toFixed(1)} KiB (${value} B)`;
  }
  return `${(value / (1024 * 1024)).toFixed(1)} MiB (${value} B)`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

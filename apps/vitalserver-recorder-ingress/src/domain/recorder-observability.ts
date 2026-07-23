export const recorderObservabilityResourceTypes = {
  observations: "observation",
  "diagnostic-events": "diagnosticEvent",
  "kernel-incidents": "kernelIncident",
  profiles: "recorderProfile",
  "boot-events": "bootEvent",
} as const;

export type RecorderObservabilityResourceType =
  (typeof recorderObservabilityResourceTypes)[keyof typeof recorderObservabilityResourceTypes];

export type RecorderObservabilityDocumentIdentity = {
  eventId: string;
  deviceId: string;
  schemaVersion: string;
  kind: string;
  siteId: string | null;
  bootId: string | null;
  sequence: number | null;
  deviceObservedAt: string | null;
  deviceTimeState: string | null;
};

export type RecorderObservabilityValidation =
  | {
      kind: "valid";
      identity: RecorderObservabilityDocumentIdentity;
      contractReceipt: string;
    }
  | {
      kind: "invalid";
      identity: Partial<RecorderObservabilityDocumentIdentity>;
      reason: string;
      detail: string | null;
      contractReceipt: string | null;
    };

export type ProjectionCandidate = {
  recordId: string;
  vrcode: string;
  resourceType: RecorderObservabilityResourceType;
  document: Record<string, unknown>;
  deviceId: string;
  siteId: string | null;
  bootId: string | null;
  sequence: number | null;
  deviceObservedAt: string | null;
  deviceTimeState: string | null;
  receivedAt: string;
  projectionVersion: number;
};

export type CurrentProjection = ProjectionCandidate & {
  associatedProfileRecordId: string | null;
};

export type CurrentProjectionDocument = Record<string, any>;

export type RecorderObservabilitySupportState =
  | "supported"
  | "unsupported"
  | "unknown";

export type RecorderObservabilityReportState =
  | "notEvaluated"
  | "awaitingFirstReport"
  | "current"
  | "stale"
  | "missing"
  | "readFailed";

export type RecorderObservabilityExpectation = {
  supportState: "supported" | "unsupported";
  source: "deployment_assignment" | "version_catalog" | "manual";
  recorderVersion: string | null;
  producerVersion: string | null;
  protocolVersion: string | null;
  catalogRevision: string | null;
  expectedSince: string | null;
};

export type RecorderObservabilityEvaluation = {
  supportState: RecorderObservabilitySupportState;
  supportSource: "accepted_report" | RecorderObservabilityExpectation["source"] | null;
  reportState: RecorderObservabilityReportState;
};

export function evaluateRecorderObservability(input: {
  currentReportState: "current" | "stale" | "missing" | "readFailed" | null;
  expectation: RecorderObservabilityExpectation | null;
  now: string;
  firstReportGraceSeconds: number;
}): RecorderObservabilityEvaluation {
  if (input.currentReportState !== null) {
    return {
      supportState: "supported",
      supportSource: "accepted_report",
      reportState: input.currentReportState,
    };
  }
  if (!input.expectation) {
    return {
      supportState: "unknown",
      supportSource: null,
      reportState: "notEvaluated",
    };
  }
  if (input.expectation.supportState === "unsupported") {
    return {
      supportState: "unsupported",
      supportSource: input.expectation.source,
      reportState: "notEvaluated",
    };
  }
  const expectedSince = input.expectation.expectedSince
    ? Date.parse(input.expectation.expectedSince)
    : Number.NaN;
  const evaluatedAt = Date.parse(input.now);
  if (!Number.isFinite(expectedSince) || !Number.isFinite(evaluatedAt)) {
    return {
      supportState: "supported",
      supportSource: input.expectation.source,
      reportState: "readFailed",
    };
  }
  return {
    supportState: "supported",
    supportSource: input.expectation.source,
    reportState: evaluatedAt < (
      expectedSince + input.firstReportGraceSeconds * 1000
    )
      ? "awaitingFirstReport"
      : "missing",
  };
}

export function mergeCurrentProjection(
  current: CurrentProjectionDocument,
  candidate: ProjectionCandidate,
): CurrentProjectionDocument {
  const next = { ...current };
  if (candidate.resourceType === "recorderProfile") {
    next.recorderProfile = {
      ...(next.recorderProfile || {}),
      latest: { ...candidate },
    };
    return next;
  }
  if (candidate.resourceType !== "bootEvent") {
    next[candidate.resourceType] = { ...candidate };
    return next;
  }
  const key = candidate.document.eventType === "boot-started"
    ? "started"
    : "shutdown";
  next.bootEvent = {
    ...(next.bootEvent || {}),
    [key]: { ...candidate },
  };
  return next;
}

export function summarizeCurrentProjection(
  document: CurrentProjectionDocument,
): {
  reportState: "current" | "missing" | "readFailed";
  collectionState: string | null;
  severity: "unknown";
  lastBootStartedAt: string | null;
  readIssueCount: number;
} {
  const health = document.observation;
  const profile = document.recorderProfile?.associated;
  const readIssues = health?.document?.readIssues;
  const associated = Boolean(
    health
    && profile
    && health.associatedProfileRecordId === profile.recordId,
  );
  const interval = profile?.document?.collection?.observationIntervalSeconds;
  return {
    reportState: !health || !associated
      ? "missing"
      : typeof interval === "number" && interval > 0
        ? "current"
        : "readFailed",
    collectionState: health
      ? String(health.document.collectionState)
      : null,
    // Incident evidence is not an active alarm without an approved recency
    // and clearing policy.
    severity: "unknown",
    lastBootStartedAt: document.bootEvent?.started?.deviceObservedAt || null,
    readIssueCount: Array.isArray(readIssues) ? readIssues.length : 0,
  };
}

export function reportStateAt(
  document: CurrentProjectionDocument,
  now: string,
  {
    toleranceMultiplier,
    allowanceSeconds,
  }: {
    toleranceMultiplier: number;
    allowanceSeconds: number;
  },
): "current" | "stale" | "missing" | "readFailed" {
  const health = document.observation;
  if (!health) return "missing";
  const profile = document.recorderProfile?.associated;
  if (
    !profile
    || health.associatedProfileRecordId !== profile.recordId
  ) {
    return "missing";
  }
  const interval = profile.document?.collection?.observationIntervalSeconds;
  const receivedAt = Date.parse(health.receivedAt);
  const evaluatedAt = Date.parse(now);
  if (
    typeof interval !== "number"
    || !Number.isFinite(interval)
    || interval <= 0
    || !Number.isFinite(receivedAt)
    || !Number.isFinite(evaluatedAt)
  ) {
    return "readFailed";
  }
  const toleranceMs = (
    interval * toleranceMultiplier + allowanceSeconds
  ) * 1000;
  return evaluatedAt > receivedAt + toleranceMs ? "stale" : "current";
}

export function shouldReplaceCurrent(
  candidate: ProjectionCandidate,
  current: CurrentProjection | null,
): boolean {
  if (!current) return true;
  if (
    (
      candidate.resourceType === "observation"
      || candidate.resourceType === "recorderProfile"
    )
    && candidate.bootId
    && candidate.bootId === current.bootId
    && candidate.sequence !== null
    && current.sequence !== null
  ) {
    return candidate.sequence > current.sequence;
  }
  const sameBoot = Boolean(
    candidate.bootId
    && current.bootId
    && candidate.bootId === current.bootId,
  );
  const candidateObserved = candidate.deviceObservedAt
    ? Date.parse(candidate.deviceObservedAt)
    : Number.NaN;
  const currentObserved = current.deviceObservedAt
    ? Date.parse(current.deviceObservedAt)
    : Number.NaN;
  if (
    sameBoot
    && trustworthyDeviceTime(candidate.deviceTimeState)
    && trustworthyDeviceTime(current.deviceTimeState)
    && Number.isFinite(candidateObserved)
    && Number.isFinite(currentObserved)
    && candidateObserved !== currentObserved
  ) {
    return candidateObserved > currentObserved;
  }
  if (candidate.receivedAt !== current.receivedAt) {
    return candidate.receivedAt > current.receivedAt;
  }
  return BigInt(candidate.recordId) > BigInt(current.recordId);
}

function trustworthyDeviceTime(state: string | null): boolean {
  return state === "synchronized" || state === "trusted";
}

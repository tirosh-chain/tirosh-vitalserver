export type NativeVitalUploadState =
  | "receiving"
  | "reconciling"
  | "indexed"
  | "failed";

export type NativeVitalUploadFailureStage =
  | "clientStream"
  | "upstreamUpload"
  | "indexVerification"
  | "processInterrupted";

export type NativeVitalUploadFailure = {
  stage: NativeVitalUploadFailureStage;
  code: string;
  message: string;
  occurredAt: string;
};

export type NativeVitalUploadMetadata = {
  uploadId: string;
  bedName: string;
  declaredVrcode: string | null;
  filename: string;
  declaredSizeBytes: number;
};

export type NativeVitalUploadIndexEvidence = {
  filename: string;
  sizeBytes: number;
  recordingStartedAt: number | string | null;
  recordingEndedAt: number | string | null;
  uploadedAt: number | string | null;
};

export type NativeVitalUploadRecord = NativeVitalUploadMetadata & {
  schemaVersion: 1;
  origin: "nativeRecorderUpload";
  state: NativeVitalUploadState;
  receivedAt: string;
  upstreamAcceptedAt: string | null;
  indexedAt: string | null;
  reconciliationAttempts: number;
  lastReconciliationAt: string | null;
  indexEvidence: NativeVitalUploadIndexEvidence | null;
  failure: NativeVitalUploadFailure | null;
};

export function beginNativeVitalUpload(
  metadata: NativeVitalUploadMetadata,
  receivedAt: string,
): NativeVitalUploadRecord {
  validateMetadata(metadata);
  requiredTimestamp(receivedAt, "receivedAt");
  return {
    schemaVersion: 1,
    origin: "nativeRecorderUpload",
    ...metadata,
    state: "receiving",
    receivedAt,
    upstreamAcceptedAt: null,
    indexedAt: null,
    reconciliationAttempts: 0,
    lastReconciliationAt: null,
    indexEvidence: null,
    failure: null,
  };
}

export function reconcileNativeVitalUpload(
  record: NativeVitalUploadRecord,
  result: {
    upstreamStatusCode: number;
    upstreamResponse: string;
    occurredAt: string;
  },
): NativeVitalUploadRecord {
  requireState(record, "receiving");
  if (
    !Number.isInteger(result.upstreamStatusCode)
    || result.upstreamStatusCode < 200
    || result.upstreamStatusCode >= 300
    || result.upstreamResponse.trim() !== "success"
  ) {
    throw new TypeError("upstream upload result is not an explicit success");
  }
  requiredTimestamp(result.occurredAt, "occurredAt");
  return {
    ...record,
    state: "reconciling",
    upstreamAcceptedAt: result.occurredAt,
    failure: null,
  };
}

export function indexedNativeVitalUpload(
  record: NativeVitalUploadRecord,
  evidence: NativeVitalUploadIndexEvidence,
  indexedAt: string,
): NativeVitalUploadRecord {
  requireState(record, "reconciling");
  if (evidence.filename !== record.filename) {
    throw new TypeError("indexed filename does not match upload metadata");
  }
  if (evidence.sizeBytes !== record.declaredSizeBytes) {
    throw new TypeError("indexed file size does not match upload metadata");
  }
  requiredTimestamp(indexedAt, "indexedAt");
  return {
    ...record,
    state: "indexed",
    indexedAt,
    lastReconciliationAt: indexedAt,
    reconciliationAttempts: record.reconciliationAttempts + 1,
    indexEvidence: { ...evidence },
    failure: null,
  };
}

export function attemptedNativeVitalUploadReconciliation(
  record: NativeVitalUploadRecord,
  occurredAt: string,
): NativeVitalUploadRecord {
  requireState(record, "reconciling");
  requiredTimestamp(occurredAt, "occurredAt");
  return {
    ...record,
    reconciliationAttempts: record.reconciliationAttempts + 1,
    lastReconciliationAt: occurredAt,
  };
}

export function failNativeVitalUpload(
  record: NativeVitalUploadRecord,
  failure: NativeVitalUploadFailure,
): NativeVitalUploadRecord {
  if (record.state === "indexed" || record.state === "failed") {
    throw new TypeError(`cannot fail native upload from ${record.state}`);
  }
  validateFailure(failure);
  return {
    ...record,
    state: "failed",
    failure: { ...failure },
  };
}

export function nativeVitalUploadRecordFromDocument(
  value: unknown,
): NativeVitalUploadRecord {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError("native upload record must be an object");
  }
  const record = value as NativeVitalUploadRecord;
  if (record.schemaVersion !== 1 || record.origin !== "nativeRecorderUpload") {
    throw new TypeError("native upload record contract version is invalid");
  }
  validateMetadata(record);
  if (!["receiving", "reconciling", "indexed", "failed"].includes(record.state)) {
    throw new TypeError("native upload state is invalid");
  }
  requiredTimestamp(record.receivedAt, "receivedAt");
  optionalTimestamp(record.upstreamAcceptedAt, "upstreamAcceptedAt");
  optionalTimestamp(record.indexedAt, "indexedAt");
  optionalTimestamp(record.lastReconciliationAt, "lastReconciliationAt");
  if (
    !Number.isInteger(record.reconciliationAttempts)
    || record.reconciliationAttempts < 0
  ) {
    throw new TypeError("reconciliationAttempts must be a non-negative integer");
  }
  if (record.failure !== null) validateFailure(record.failure);
  if (record.state === "indexed") {
    if (!record.indexEvidence || record.indexedAt === null) {
      throw new TypeError("indexed native upload lacks index evidence");
    }
    if (
      record.indexEvidence.filename !== record.filename
      || record.indexEvidence.sizeBytes !== record.declaredSizeBytes
    ) {
      throw new TypeError("indexed native upload evidence does not match metadata");
    }
  } else if (record.indexEvidence !== null || record.indexedAt !== null) {
    throw new TypeError("non-indexed native upload contains index evidence");
  }
  if (record.state === "failed" && record.failure === null) {
    throw new TypeError("failed native upload lacks failure evidence");
  }
  if (record.state !== "failed" && record.failure !== null) {
    throw new TypeError("non-failed native upload contains failure evidence");
  }
  return {
    ...record,
    indexEvidence: record.indexEvidence ? { ...record.indexEvidence } : null,
    failure: record.failure ? { ...record.failure } : null,
  };
}

function validateMetadata(metadata: NativeVitalUploadMetadata): void {
  requiredString(metadata.uploadId, "uploadId");
  requiredString(metadata.bedName, "bedName");
  if (metadata.declaredVrcode !== null) {
    requiredString(metadata.declaredVrcode, "declaredVrcode");
  }
  requiredString(metadata.filename, "filename");
  if (
    !Number.isSafeInteger(metadata.declaredSizeBytes)
    || metadata.declaredSizeBytes <= 0
  ) {
    throw new TypeError("declaredSizeBytes must be a positive integer");
  }
}

function validateFailure(failure: NativeVitalUploadFailure): void {
  if (
    ![
      "clientStream",
      "upstreamUpload",
      "indexVerification",
      "processInterrupted",
    ].includes(failure.stage)
  ) {
    throw new TypeError("native upload failure stage is invalid");
  }
  requiredString(failure.code, "failure.code");
  requiredString(failure.message, "failure.message");
  requiredTimestamp(failure.occurredAt, "failure.occurredAt");
}

function requireState(
  record: NativeVitalUploadRecord,
  expected: NativeVitalUploadState,
): void {
  if (record.state !== expected) {
    throw new TypeError(
      `native upload state must be ${expected}; actual=${record.state}`,
    );
  }
}

function requiredString(value: unknown, field: string): asserts value is string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new TypeError(`${field} must be a non-empty string`);
  }
}

function requiredTimestamp(value: unknown, field: string): asserts value is string {
  requiredString(value, field);
  if (Number.isNaN(Date.parse(value))) {
    throw new TypeError(`${field} must be an ISO timestamp`);
  }
}

function optionalTimestamp(value: unknown, field: string): void {
  if (value !== null) requiredTimestamp(value, field);
}

import { createHash } from "node:crypto";

import { isRecorderGatewayIdentifier, recorderGatewaySchemaVersion, type RecorderGatewayIssue } from "./recorder-gateway-ingress-and-cold-path-contracts.js";

export interface RecorderVitalUploadSourceReceipt {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  id: string;
  sourceKind: "recorder-upload";
  uploadId: string;
  originalFileName: string;
  mediaType: "application/x-vital";
  byteSize: number;
  sha256: string;
  reportedBedName: string;
  declaredRecorderId?: string;
  declaredRecorderCode?: string;
  state: "admitted";
  contentReference: {
    resourceType: "recorder-vital-upload-content";
    resourceId: string;
  };
  receivedAt: string;
  finalizedAt: string;
}

export interface RecorderVitalUploadAdmissionOutcome {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  state: "admitted" | "rejected" | "failed";
  observedAt: string;
  receipt?: RecorderVitalUploadSourceReceipt;
  admissionState?: "not-admitted" | "unknown";
  issue?: RecorderGatewayIssue;
}

export interface ArchiveSourceAdmissionReceipt {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  requestId: string;
  outcome: "accepted" | "duplicate" | "quarantined";
  artifactReference?: {
    resourceType: "archive-artifact";
    resourceId: string;
  };
  receivedAt: string;
  persistedAt: string;
  issue?: RecorderGatewayIssue;
}

export type RecorderVitalUploadDispatchState =
  | "pending"
  | "dispatching"
  | "archive-admitted"
  | "quarantined"
  | "rejected"
  | "unknown";

export interface RecorderVitalUploadDispatch {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  sourceReceiptId: string;
  requestId: string;
  revision: number;
  attempt: number;
  state: RecorderVitalUploadDispatchState;
  archiveAdmissionReceipt?: ArchiveSourceAdmissionReceipt;
  issue?: RecorderGatewayIssue;
  updatedAt: string;
}

export type RecorderVitalUploadPublishOutcome =
  | { state: "admitted"; receipt: ArchiveSourceAdmissionReceipt }
  | { state: "quarantined"; receipt: ArchiveSourceAdmissionReceipt }
  | { state: "rejected"; issue: RecorderGatewayIssue }
  | { state: "unknown"; issue: RecorderGatewayIssue };

export function validateRecorderVitalUploadSourceReceipt(
  receipt: RecorderVitalUploadSourceReceipt,
): void {
  if (
    receipt.schemaVersion !== recorderGatewaySchemaVersion
    || !isRecorderGatewayIdentifier(receipt.id)
    || receipt.sourceKind !== "recorder-upload"
    || !isRecorderGatewayIdentifier(receipt.uploadId)
    || !validVitalFileName(receipt.originalFileName)
    || receipt.mediaType !== "application/x-vital"
    || !Number.isSafeInteger(receipt.byteSize)
    || receipt.byteSize < 1
    || !/^[a-f0-9]{64}$/.test(receipt.sha256)
    || receipt.reportedBedName.trim() === ""
    || receipt.reportedBedName.length > 255
    || receipt.state !== "admitted"
    || receipt.contentReference.resourceType !== "recorder-vital-upload-content"
    || receipt.contentReference.resourceId !== receipt.id
    || receipt.receivedAt === ""
    || receipt.finalizedAt === ""
    || (receipt.declaredRecorderId !== undefined && !isRecorderGatewayIdentifier(receipt.declaredRecorderId))
    || (receipt.declaredRecorderCode !== undefined && receipt.declaredRecorderCode.trim() === "")
  ) {
    throw new TypeError("Recorder Vital upload source receipt is invalid");
  }
}

export function archiveSourceAdmissionRequestId(sourceReceiptId: string): string {
  if (!isRecorderGatewayIdentifier(sourceReceiptId)) {
    throw new TypeError("Recorder Vital upload source receipt identity is invalid");
  }
  const digest = createHash("sha256").update(sourceReceiptId, "utf8").digest("hex");
  return `archive-source-request-${digest.slice(0, 32)}`;
}

export function initialRecorderVitalUploadDispatch(
  sourceReceipt: RecorderVitalUploadSourceReceipt,
): RecorderVitalUploadDispatch {
  validateRecorderVitalUploadSourceReceipt(sourceReceipt);
  return {
    schemaVersion: recorderGatewaySchemaVersion,
    sourceReceiptId: sourceReceipt.id,
    requestId: archiveSourceAdmissionRequestId(sourceReceipt.id),
    revision: 0,
    attempt: 0,
    state: "pending",
    updatedAt: sourceReceipt.finalizedAt,
  };
}

export function beginRecorderVitalUploadDispatch(
  current: RecorderVitalUploadDispatch,
  at: string,
): RecorderVitalUploadDispatch {
  validateRecorderVitalUploadDispatch(current);
  if (
    current.state !== "pending"
    && current.state !== "dispatching"
    && current.state !== "unknown"
  ) {
    throw new TypeError("terminal Recorder Vital upload dispatch cannot begin again");
  }
  const next: RecorderVitalUploadDispatch = {
    schemaVersion: recorderGatewaySchemaVersion,
    sourceReceiptId: current.sourceReceiptId,
    requestId: current.requestId,
    revision: current.revision + 1,
    attempt: current.attempt + 1,
    state: "dispatching",
    updatedAt: at,
  };
  validateRecorderVitalUploadDispatch(next);
  return next;
}

export function completeRecorderVitalUploadDispatch(
  current: RecorderVitalUploadDispatch,
  outcome: RecorderVitalUploadPublishOutcome,
  at: string,
): RecorderVitalUploadDispatch {
  validateRecorderVitalUploadDispatch(current);
  if (current.state !== "dispatching") {
    throw new TypeError("Recorder Vital upload dispatch completion requires dispatching state");
  }
  const base = {
    schemaVersion: recorderGatewaySchemaVersion,
    sourceReceiptId: current.sourceReceiptId,
    requestId: current.requestId,
    revision: current.revision + 1,
    attempt: current.attempt,
    updatedAt: at,
  } as const;
  let next: RecorderVitalUploadDispatch;
  switch (outcome.state) {
    case "admitted":
      next = { ...base, state: "archive-admitted", archiveAdmissionReceipt: outcome.receipt };
      break;
    case "quarantined":
      next = { ...base, state: "quarantined", archiveAdmissionReceipt: outcome.receipt };
      break;
    case "rejected":
      next = { ...base, state: "rejected", issue: outcome.issue };
      break;
    case "unknown":
      next = { ...base, state: "unknown", issue: outcome.issue };
      break;
  }
  validateRecorderVitalUploadDispatch(next);
  return next;
}

export function validateRecorderVitalUploadDispatch(
  dispatch: RecorderVitalUploadDispatch,
): void {
  if (
    dispatch.schemaVersion !== recorderGatewaySchemaVersion
    || !isRecorderGatewayIdentifier(dispatch.sourceReceiptId)
    || dispatch.requestId !== archiveSourceAdmissionRequestId(dispatch.sourceReceiptId)
    || !Number.isSafeInteger(dispatch.revision)
    || dispatch.revision < 0
    || !Number.isSafeInteger(dispatch.attempt)
    || dispatch.attempt < 0
    || dispatch.updatedAt === ""
  ) {
    throw new TypeError("Recorder Vital upload dispatch is invalid");
  }
  switch (dispatch.state) {
    case "pending":
      if (
        dispatch.revision !== 0
        || dispatch.attempt !== 0
        || dispatch.archiveAdmissionReceipt !== undefined
        || dispatch.issue !== undefined
      ) {
        throw new TypeError("pending Recorder Vital upload dispatch is invalid");
      }
      break;
    case "dispatching":
      if (
        dispatch.attempt < 1
        || dispatch.archiveAdmissionReceipt !== undefined
        || dispatch.issue !== undefined
      ) {
        throw new TypeError("dispatching Recorder Vital upload dispatch is invalid");
      }
      break;
    case "archive-admitted":
      if (
        dispatch.archiveAdmissionReceipt === undefined
        || !["accepted", "duplicate"].includes(dispatch.archiveAdmissionReceipt.outcome)
        || dispatch.issue !== undefined
      ) {
        throw new TypeError("admitted Recorder Vital upload dispatch is invalid");
      }
      validateArchiveSourceAdmissionReceipt(
        dispatch.archiveAdmissionReceipt,
        dispatch.requestId,
      );
      break;
    case "quarantined":
      if (
        dispatch.archiveAdmissionReceipt?.outcome !== "quarantined"
        || dispatch.issue !== undefined
      ) {
        throw new TypeError("quarantined Recorder Vital upload dispatch is invalid");
      }
      validateArchiveSourceAdmissionReceipt(
        dispatch.archiveAdmissionReceipt,
        dispatch.requestId,
      );
      break;
    case "rejected":
    case "unknown":
      if (
        dispatch.archiveAdmissionReceipt !== undefined
        || dispatch.issue === undefined
        || !isRecorderGatewayIdentifier(dispatch.issue.code)
      ) {
        throw new TypeError("failed Recorder Vital upload dispatch is invalid");
      }
      break;
  }
}

export function validateArchiveSourceAdmissionReceipt(
  receipt: ArchiveSourceAdmissionReceipt,
  requestId: string,
): void {
  if (
    receipt.schemaVersion !== recorderGatewaySchemaVersion
    || receipt.requestId !== requestId
    || receipt.receivedAt === ""
    || receipt.persistedAt === ""
  ) {
    throw new TypeError("Archive source admission receipt is invalid");
  }
  if (receipt.outcome === "accepted" || receipt.outcome === "duplicate") {
    if (
      receipt.artifactReference?.resourceType !== "archive-artifact"
      || !isRecorderGatewayIdentifier(receipt.artifactReference.resourceId)
      || receipt.issue !== undefined
    ) {
      throw new TypeError("successful Archive source admission receipt is invalid");
    }
    return;
  }
  if (
    receipt.artifactReference !== undefined
    || receipt.issue === undefined
    || !isRecorderGatewayIdentifier(receipt.issue.code)
  ) {
    throw new TypeError("quarantined Archive source admission receipt is invalid");
  }
}

export function validVitalFileName(value: string): boolean {
  return (
    value.length > 0
    && value.length <= 255
    && !value.includes("/")
    && !value.includes("\\")
    && value.toLowerCase().endsWith(".vital")
  );
}

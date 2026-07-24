import { createHash } from "node:crypto";

import {
  isLabRecorderRunnerIdentifier,
  labRecorderRunnerSchemaVersion,
  type LabRecorderRunnerIssue,
} from "./lab-recorder-run-contracts.js";

export interface LabReplayFrameTrack {
  outputTrackId: number;
  sourceTrackId: number;
  kind: 1 | 2;
  name: string;
  deviceName: string;
  unit: string;
  monitorType: number;
  sampleRate?: number;
  minimumDisplay?: number;
  maximumDisplay?: number;
  waveformValues?: number[];
  numericValue?: number;
}

export interface LabReplayFrame {
  offsetSeconds: number;
  outputTime: number;
  tracks: LabReplayFrameTrack[];
}

export interface PrepareLabReplayCommand {
  schemaVersion: string;
  replayId: string;
  recorderGatewayRecorderCode: string;
  spoolDatabaseSha256: string;
  frameCount: number;
}

export interface SendLabReplayBatchCommand {
  schemaVersion: string;
  replayId: string;
  runnerSessionId: string;
  batchId: string;
  startOffsetSecond: number;
  frames: LabReplayFrame[];
  finalBatch: boolean;
}

export interface ConfirmLabReplayUpstreamCommand {
  schemaVersion: string;
  replayId: string;
  runnerSessionId: string;
  expectedFrameCount: number;
}

export interface LabReplayPreparationReceipt {
  schemaVersion: "v1";
  replayId: string;
  runnerSessionId: string;
  spoolDatabaseSha256: string;
  frameCount: number;
  outputStartedAt: number;
  preparedAt: string;
}

export interface LabReplayMessageBatchReceipt {
  schemaVersion: "v1";
  replayId: string;
  runnerSessionId: string;
  batchId: string;
  startOffsetSecond: number;
  frameCount: number;
  finalBatch: boolean;
  acceptedAt: string;
}

export interface LabReplayUpstreamDeliveryReceipt {
  schemaVersion: "v1";
  replayId: string;
  runnerSessionId: string;
  deliveryReceiptId: string;
  deliveredFrameCount: number;
  deliveryConfirmedAt: string;
}

export interface LabReplayStoredBatch {
  commandDigest: string;
  receipt: LabReplayMessageBatchReceipt;
  ingressReceiptIds: string[];
}

export interface LabReplaySession {
  schemaVersion: "v1";
  preparationReceipt: LabReplayPreparationReceipt;
  recorderGatewayRecorderCode: string;
  batches: LabReplayStoredBatch[];
  upstreamDeliveryReceipt?: LabReplayUpstreamDeliveryReceipt;
}

export type LabReplayCommandResult<T> =
  | { state: "accepted"; receipt: T }
  | { state: "rejected"; issue: LabRecorderRunnerIssue }
  | { state: "failed"; issue: LabRecorderRunnerIssue };

export function validatePrepareLabReplayCommand(
  command: PrepareLabReplayCommand,
): LabRecorderRunnerIssue | undefined {
  if (
    command.schemaVersion !== labRecorderRunnerSchemaVersion ||
    !isLabRecorderRunnerIdentifier(command.replayId) ||
    !isLabRecorderRunnerIdentifier(command.recorderGatewayRecorderCode) ||
    !/^[a-f0-9]{64}$/.test(command.spoolDatabaseSha256) ||
    !Number.isSafeInteger(command.frameCount) ||
    command.frameCount < 1
  ) {
    return {
      code: "invalid-lab-replay-preparation-command",
      message: "replay identity, recorder code, spool digest, and positive frame count are required",
    };
  }
  return undefined;
}

export function validateSendLabReplayBatchCommand(
  command: SendLabReplayBatchCommand,
): LabRecorderRunnerIssue | undefined {
  if (
    command.schemaVersion !== labRecorderRunnerSchemaVersion ||
    !isLabRecorderRunnerIdentifier(command.replayId) ||
    !isLabRecorderRunnerIdentifier(command.runnerSessionId) ||
    !isLabRecorderRunnerIdentifier(command.batchId) ||
    !Number.isSafeInteger(command.startOffsetSecond) ||
    command.startOffsetSecond < 0 ||
    command.frames.length < 1 ||
    command.frames.length > 60 ||
    labReplayBatchId(command.replayId, command.startOffsetSecond, command.frames.length) !== command.batchId ||
    command.frames.some((frame, index) => !validLabReplayFrame(frame, command.startOffsetSecond + index))
  ) {
    return {
      code: "invalid-lab-replay-message-batch",
      message: "batch identity, contiguous offset, and one to sixty complete replay frames are required",
    };
  }
  return undefined;
}

export function validateConfirmLabReplayUpstreamCommand(
  command: ConfirmLabReplayUpstreamCommand,
): LabRecorderRunnerIssue | undefined {
  if (
    command.schemaVersion !== labRecorderRunnerSchemaVersion ||
    !isLabRecorderRunnerIdentifier(command.replayId) ||
    !isLabRecorderRunnerIdentifier(command.runnerSessionId) ||
    !Number.isSafeInteger(command.expectedFrameCount) ||
    command.expectedFrameCount < 1
  ) {
    return {
      code: "invalid-lab-replay-upstream-confirmation-command",
      message: "replay identity, Runner session, and positive expected frame count are required",
    };
  }
  return undefined;
}

export function labReplayBatchId(
  replayId: string,
  startOffsetSecond: number,
  frameCount: number,
): string {
  const digest = createHash("sha256")
    .update(`${replayId}:${startOffsetSecond}:${frameCount}`, "utf8")
    .digest("hex");
  return `replay-batch-${digest}`;
}

export function labReplayFrameIdentity(
  replayId: string,
  offsetSeconds: number,
  encodedFrame: Uint8Array,
): {
  receiptId: string;
  requestId: string;
  deliveryRequestId: string;
  packetId: string;
  durableIngressStateReceiptId: string;
} {
  const digest = createHash("sha256")
    .update(replayId, "utf8")
    .update(":", "utf8")
    .update(String(offsetSeconds), "utf8")
    .update(":", "utf8")
    .update(encodedFrame)
    .digest("hex");
  return {
    receiptId: `lab-ingress-${digest}`,
    requestId: `lab-request-${digest}`,
    deliveryRequestId: `lab-delivery-${digest}`,
    packetId: `lab-packet-${digest}`,
    durableIngressStateReceiptId: `lab-durable-${digest}`,
  };
}

export function stableLabReplayBatchCommandDigest(
  command: SendLabReplayBatchCommand,
): string {
  return createHash("sha256").update(JSON.stringify(command), "utf8").digest("hex");
}

function validLabReplayFrame(frame: LabReplayFrame, expectedOffset: number): boolean {
  return Number.isSafeInteger(frame.offsetSeconds) &&
    frame.offsetSeconds === expectedOffset &&
    Number.isFinite(frame.outputTime) &&
    frame.outputTime > 0 &&
    frame.tracks.length > 0 &&
    frame.tracks.every(validLabReplayFrameTrack);
}

function validLabReplayFrameTrack(track: LabReplayFrameTrack): boolean {
  const common = Number.isSafeInteger(track.outputTrackId) &&
    track.outputTrackId > 0 &&
    Number.isSafeInteger(track.sourceTrackId) &&
    track.sourceTrackId > 0 &&
    (track.kind === 1 || track.kind === 2) &&
    track.name !== "" &&
    track.deviceName !== "" &&
    Number.isSafeInteger(track.monitorType) &&
    track.monitorType > 0;
  if (!common) {
    return false;
  }
  if (track.kind === 1) {
    return Number.isFinite(track.sampleRate) &&
      (track.sampleRate ?? 0) > 0 &&
      Array.isArray(track.waveformValues) &&
      track.waveformValues.length === Math.round(track.sampleRate ?? 0) &&
      track.waveformValues.every(Number.isFinite) &&
      track.numericValue === undefined;
  }
  return Number.isFinite(track.numericValue) &&
    track.waveformValues === undefined &&
    track.sampleRate === undefined;
}

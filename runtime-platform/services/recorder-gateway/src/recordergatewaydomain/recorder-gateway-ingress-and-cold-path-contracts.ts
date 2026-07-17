import { createHash } from "node:crypto";

// Pure Recorder Gateway contract models. These types mirror the versioned
// JSON contracts without reading storage, clocks, sockets, or upstream state.
// The private durable-record models deliberately keep delivery replay and
// cold-path capture separate: a succeeded replay may release only its replay
// payload; it may never erase a retained cold-path packet capture.

export const recorderGatewaySchemaVersion = "v1" as const;

export interface RecorderGatewayIssue {
  code: string;
  message?: string;
  retryable?: boolean;
  dependency?: string;
}

export interface RecorderGatewayReadResult<T> {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  state: "available" | "missing" | "invalid" | "unavailable" | "failed" | "stale" | "empty" | "unsupported";
  observedAt: string;
  value?: T;
  issue?: RecorderGatewayIssue;
  sourceRevision?: number;
}

export interface RecorderGatewayResourceReference {
  resourceType: string;
  resourceId: string;
}

export interface RecorderGatewayConnection {
  sessionId: string;
  protocolVersion: "v2";
  bootId?: string;
}

export interface RecorderIngressPacket {
  packetId: string;
  byteCount: number;
  payloadDigest: string;
  receivedAt: string;
  parseState: "accepted";
}

export interface RecorderColdPathCaptureReference extends RecorderGatewayResourceReference {
  resourceType: "recorder-cold-path-capture";
}

export interface RecorderIngressReceipt {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  id: string;
  requestId: string;
  recorderId: string;
  connection: RecorderGatewayConnection;
  packet: RecorderIngressPacket;
  ingressState: "accepted";
  durableIngressStateHandoff: {
    state: "stored";
    durableIngressStateReceiptId: string;
    persistedAt: string;
  };
  // The optional field makes an explicit upgrade distinction: a legacy
  // delivery-only record remains replayable, but it is never presented as a
  // cold-path source. Every newly admitted record must carry this fact.
  coldPathCapture?: {
    state: "captured";
    captureReference: RecorderColdPathCaptureReference;
    persistedAt: string;
  };
  delivery: {
    state: "requested";
    requestId: string;
  };
  recordedAt: string;
}

export type DeliveryOutcomeState = "succeeded" | "failed" | "unavailable" | "unsupported" | "unknown";

export interface VitalServerDeliveryAttemptOutcome {
  state: DeliveryOutcomeState;
  issue?: RecorderGatewayIssue;
}

export interface VitalServerDeliveryReceipt {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  id: string;
  deliveryRequestId: string;
  ingressReceiptReference: {
    resourceType: "ingress-receipt";
    resourceId: string;
  };
  provider: {
    kind: string;
    id: string;
    capabilityRevision: number;
  };
  attempt: number;
  outcome: VitalServerDeliveryAttemptOutcome;
  retry: {
    state: "not-scheduled" | "scheduled" | "exhausted";
    nextAttemptAt?: string;
  };
  completedAt: string;
}

export type RecorderGatewayDeliveryReplayState = "pending" | "delivering" | "delivered" | "terminal-failed";

// RecorderGatewayDeliveryReplay owns the *temporary* payload needed for a
// selected VitalServer delivery retry. This state is intentionally not the
// cold-path archive source.
export interface RecorderGatewayDeliveryReplay {
  payloadBase64?: string;
  payloadEncoding?: "binary" | "binary-string";
  attempt: number;
  state: RecorderGatewayDeliveryReplayState;
  nextAttemptAt?: string;
  leaseExpiresAt?: string;
}

// RecorderColdPathPacketCapture retains the accepted raw packet bytes for a
// separately finalized archive source. It stays private to the Gateway durable
// state boundary and is never returned by a public receipt/read route.
export interface RecorderColdPathPacketCapture {
  captureReference: RecorderColdPathCaptureReference;
  payloadBase64: string;
  payloadEncoding: "binary" | "binary-string";
  capturedAt: string;
}

// RecorderGatewayIngressDurableRecord is Gateway-private persisted state.
// It is one atomic ingress admission record containing two independent
// retention lifecycles: delivery replay and cold-path capture.
export interface RecorderGatewayIngressDurableRecord {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  receipt: RecorderIngressReceipt;
  deliveryReplay: RecorderGatewayDeliveryReplay;
  coldPathPacketCapture?: RecorderColdPathPacketCapture;
}

export interface RecorderGatewayDeliveryReplayUsage {
  pendingItems: number;
  pendingBytes: number;
}

export interface RecorderColdPathCaptureUsage {
  retainedPacketCount: number;
  retainedPayloadBytes: number;
}

export interface RecorderColdPathCapture {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  id: string;
  recorderId: string;
  connection: RecorderGatewayConnection;
  resourceRevision: number;
  state: "capturing" | "finalized";
  openedAt: string;
  finalizationReceipt?: RecorderColdPathCaptureFinalizationReceipt;
}

export interface RecorderColdPathCaptureFinalizationCommand {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  requestId: string;
  coldPathCaptureId: string;
  expectedCaptureRevision: number;
}

export interface RecorderColdPathCapturedPacket {
  ingressReceiptReference: {
    resourceType: "ingress-receipt";
    resourceId: string;
  };
  packet: RecorderIngressPacket;
  payloadEncoding: "binary" | "binary-string";
  payloadBase64: string;
}

export interface RecorderColdPathPacketSequence {
  resourceType: "recorder-cold-path-packet-sequence";
  resourceId: string;
  format: "recorder-gateway-cold-path-packet-sequence-v1";
  mediaType: "application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl";
  packetCount: number;
  payloadByteCount: number;
  sha256: string;
}

// RecorderColdPathCaptureFinalizationReceipt attests only to the immutable raw
// packet sequence that Recorder Gateway owns. It is deliberately not an
// ArtifactManifest or ExportReceipt, so callers cannot mistake it for valid
// .vital formation, upload, or indexing success.
export interface RecorderColdPathCaptureFinalizationReceipt {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  id: string;
  requestId: string;
  captureReference: RecorderColdPathCaptureReference;
  expectedCaptureRevision: number;
  finalizedCaptureRevision: number;
  recorderId: string;
  connection: RecorderGatewayConnection;
  finalizedPacketSequence: RecorderColdPathPacketSequence;
  finalizedAt: string;
}

export interface RecorderColdPathCaptureOpenInput {
  recorderId: string;
  connection: RecorderGatewayConnection;
}

export interface RecorderPacketIngressInput {
  recorderId: string;
  connection: RecorderGatewayConnection;
  coldPathCaptureId: string;
  payload: Uint8Array;
  payloadEncoding: "binary" | "binary-string";
}

export interface RecorderIngressAcknowledgement {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  state: "accepted" | "rejected" | "failed" | "unsupported";
  receiptId?: string;
  sessionId?: string;
  coldPathCaptureId?: string;
  issue?: RecorderGatewayIssue;
}

export function recorderGatewayTimestamp(value: Date): string {
  return value.toISOString();
}

const identifierPattern = /^[A-Za-z0-9][A-Za-z0-9._:-]*$/;

export function isRecorderGatewayIdentifier(value: string): boolean {
  return value.length > 0 && value.length <= 128 && identifierPattern.test(value);
}

export function encodeRecorderColdPathPacketSequence(capturedPackets: readonly RecorderColdPathCapturedPacket[]): Uint8Array {
  const normalizedPackets = [...capturedPackets].sort((left, right) => {
    const receivedAtComparison = left.packet.receivedAt.localeCompare(right.packet.receivedAt);
    return receivedAtComparison === 0
      ? left.ingressReceiptReference.resourceId.localeCompare(right.ingressReceiptReference.resourceId)
      : receivedAtComparison;
  });
  const lines = normalizedPackets.map((capturedPacket) => JSON.stringify({
    ingressReceiptId: capturedPacket.ingressReceiptReference.resourceId,
    packetId: capturedPacket.packet.packetId,
    receivedAt: capturedPacket.packet.receivedAt,
    payloadEncoding: capturedPacket.payloadEncoding,
    payloadBase64: capturedPacket.payloadBase64,
  }));
  return Buffer.from(lines.length === 0 ? "" : `${lines.join("\n")}\n`, "utf8");
}

export function finalizeRecorderColdPathCapturePacketSequence(
  receiptId: string,
  command: RecorderColdPathCaptureFinalizationCommand,
  capture: RecorderColdPathCapture,
  capturedPackets: readonly RecorderColdPathCapturedPacket[],
  finalizedAt: string,
): RecorderColdPathCaptureFinalizationReceipt {
  if (
    !isRecorderGatewayIdentifier(receiptId) ||
    !isRecorderGatewayIdentifier(command.requestId) ||
    !isRecorderGatewayIdentifier(command.coldPathCaptureId) ||
    !isRecorderGatewayIdentifier(capture.id) ||
    capture.id !== command.coldPathCaptureId ||
    capture.resourceRevision !== command.expectedCaptureRevision ||
    capture.state !== "capturing" ||
    !isRecorderGatewayIdentifier(capture.recorderId) ||
    !isRecorderGatewayIdentifier(capture.connection.sessionId) ||
    finalizedAt === ""
  ) {
    throw new Error("Recorder Cold-Path Capture finalization input is invalid");
  }
  if (capturedPackets.length === 0) {
    throw new Error("Recorder Cold-Path Capture has no accepted packet to finalize");
  }
  const uniqueIngressReceiptIDs = new Set<string>();
  let payloadByteCount = 0;
  for (const capturedPacket of capturedPackets) {
    if (
      capturedPacket.ingressReceiptReference.resourceType !== "ingress-receipt" ||
      !isRecorderGatewayIdentifier(capturedPacket.ingressReceiptReference.resourceId) ||
      !isRecorderGatewayIdentifier(capturedPacket.packet.packetId) ||
      capturedPacket.packet.byteCount < 0 ||
      capturedPacket.packet.receivedAt === "" ||
      typeof capturedPacket.payloadBase64 !== "string" ||
      !isRecorderGatewayIdentifier(capturedPacket.payloadEncoding)
    ) {
      throw new Error("Recorder Cold-Path Capture contains an invalid captured packet");
    }
    if (uniqueIngressReceiptIDs.has(capturedPacket.ingressReceiptReference.resourceId)) {
      throw new Error("Recorder Cold-Path Capture contains a duplicate ingress receipt");
    }
    uniqueIngressReceiptIDs.add(capturedPacket.ingressReceiptReference.resourceId);
    payloadByteCount += capturedPacket.packet.byteCount;
  }
  const encodedPacketSequence = encodeRecorderColdPathPacketSequence(capturedPackets);
  const sha256 = createHash("sha256").update(encodedPacketSequence).digest("hex");
  return {
    schemaVersion: recorderGatewaySchemaVersion,
    id: receiptId,
    requestId: command.requestId,
    captureReference: { resourceType: "recorder-cold-path-capture", resourceId: capture.id },
    expectedCaptureRevision: command.expectedCaptureRevision,
    finalizedCaptureRevision: capture.resourceRevision + 1,
    recorderId: capture.recorderId,
    connection: capture.connection,
    finalizedPacketSequence: {
      resourceType: "recorder-cold-path-packet-sequence",
      resourceId: capture.id,
      format: "recorder-gateway-cold-path-packet-sequence-v1",
      mediaType: "application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl",
      packetCount: capturedPackets.length,
      payloadByteCount,
      sha256,
    },
    finalizedAt,
  };
}

export function unavailableRecorderGatewayRead<T>(observedAt: string, issue: RecorderGatewayIssue): RecorderGatewayReadResult<T> {
  return { schemaVersion: recorderGatewaySchemaVersion, state: "unavailable", observedAt, issue };
}

export function failedRecorderGatewayRead<T>(observedAt: string, issue: RecorderGatewayIssue): RecorderGatewayReadResult<T> {
  return { schemaVersion: recorderGatewaySchemaVersion, state: "failed", observedAt, issue };
}

export function missingRecorderGatewayRead<T>(observedAt: string, issue: RecorderGatewayIssue): RecorderGatewayReadResult<T> {
  return { schemaVersion: recorderGatewaySchemaVersion, state: "missing", observedAt, issue };
}

export function invalidRecorderGatewayRead<T>(observedAt: string, issue: RecorderGatewayIssue): RecorderGatewayReadResult<T> {
  return { schemaVersion: recorderGatewaySchemaVersion, state: "invalid", observedAt, issue };
}

import type {
  RecorderColdPathCapture,
  RecorderColdPathCapturedPacket,
  RecorderColdPathCaptureFinalizationReceipt,
  RecorderColdPathCaptureUsage,
  RecorderGatewayDeliveryReplayUsage,
  RecorderGatewayIngressDurableRecord,
  RecorderIngressReceipt,
  VitalServerDeliveryAttemptOutcome,
  VitalServerDeliveryReceipt,
} from "../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";
import type { RecorderGatewayDeliveryReplayClaimSettlement } from "../recordergatewaydomain/recorder-gateway-vital-server-delivery-replay-policy.js";

export class RecorderGatewayIngressDurableStateResourceNotFoundError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "RecorderGatewayIngressDurableStateResourceNotFoundError";
  }
}

export class RecorderGatewayIngressDurableStateRevisionConflictError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "RecorderGatewayIngressDurableStateRevisionConflictError";
  }
}

// RecorderGatewayIngressDurableStateStore owns one Gateway-private durable
// record for each accepted packet plus explicit cold-path capture aggregates.
// Its interface separates delivery replay from raw capture so an application
// caller cannot accidentally equate upstream acknowledgement with archive
// preservation or finalization.
export interface RecorderGatewayIngressDurableStateStore {
  initializeRecorderGatewayIngressDurableState(): Promise<void>;
  readRecorderGatewayDeliveryReplayUsage(): Promise<RecorderGatewayDeliveryReplayUsage>;
  readRecorderColdPathCaptureUsage(): Promise<RecorderColdPathCaptureUsage>;
  persistAcceptedRecorderGatewayIngressDurableRecord(record: RecorderGatewayIngressDurableRecord): Promise<void>;
  readRecorderIngressReceipt(receiptId: string): Promise<RecorderIngressReceipt>;
  readVitalServerDeliveryReceipt(receiptId: string): Promise<VitalServerDeliveryReceipt>;
  listExpiredRecorderGatewayDeliveryReplayClaims(now: Date): Promise<RecorderGatewayIngressDurableRecord[]>;
  findVitalServerDeliveryReceiptForAttempt(deliveryRequestId: string, attempt: number): Promise<VitalServerDeliveryReceipt | undefined>;
  claimNextDueRecorderGatewayDeliveryReplayRecord(now: Date, leaseExpiresAt: Date): Promise<RecorderGatewayIngressDurableRecord | undefined>;
  persistVitalServerDeliveryReceipt(receipt: VitalServerDeliveryReceipt): Promise<void>;
  settleRecorderGatewayDeliveryReplayClaim(receiptId: string, attempt: number, settlement: RecorderGatewayDeliveryReplayClaimSettlement): Promise<void>;
  createRecorderColdPathCapture(capture: RecorderColdPathCapture): Promise<void>;
  readRecorderColdPathCapture(captureId: string): Promise<RecorderColdPathCapture>;
  readRecorderColdPathCaptureFinalizationReceipt(receiptId: string): Promise<RecorderColdPathCaptureFinalizationReceipt>;
  findRecorderColdPathCaptureFinalizationReceiptByRequestId(requestId: string): Promise<RecorderColdPathCaptureFinalizationReceipt | undefined>;
  readRecorderColdPathCapturedPackets(captureId: string): Promise<RecorderColdPathCapturedPacket[]>;
  commitRecorderColdPathCaptureFinalization(
    captureId: string,
    expectedCaptureRevision: number,
    receipt: RecorderColdPathCaptureFinalizationReceipt,
  ): Promise<void>;
}

// VitalServerPacketDeliveryInput is one Recorder Gateway-owned packet delivery
// attempt toward the specifically configured VitalServer provider. It is not
// an arbitrary "upstream" message: this boundary exists only for VitalServer
// `send_data` acknowledgement semantics.
export interface VitalServerPacketDeliveryInput {
  deliveryRequestId: string;
  ingressReceiptId: string;
  attempt: number;
  payload: Uint8Array;
  payloadEncoding: "binary" | "binary-string";
}

export interface VitalServerPacketDeliveryPort {
  deliverRecorderPacketToVitalServer(input: VitalServerPacketDeliveryInput): Promise<VitalServerDeliveryAttemptOutcome>;
}

export interface RecorderGatewayClock {
  now(): Date;
}

export class SystemRecorderGatewayClock implements RecorderGatewayClock {
  public now(): Date {
    return new Date();
  }
}

export interface RecorderGatewayIdentifierGenerator {
  newRecorderGatewayIdentifier(prefix: string): string;
}

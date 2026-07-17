import type {
  RecorderColdPathCaptureUsage,
  RecorderGatewayDeliveryReplayState,
  RecorderGatewayDeliveryReplayUsage,
  RecorderGatewayIssue,
  VitalServerDeliveryAttemptOutcome,
  VitalServerDeliveryReceipt,
} from "./recorder-gateway-ingress-and-cold-path-contracts.js";

// RecorderGatewayIngressAdmissionLimits bound the replay queue that protects
// the configured VitalServer delivery path. They do not describe retained
// cold-path archive bytes.
export interface RecorderGatewayIngressAdmissionLimits {
  maxPendingItems: number;
  maxPendingBytes: number;
}

// RecorderColdPathCaptureLimits protect archive-source retention separately
// from delivery replay. If this limit is reached, Gateway rejects a new packet
// instead of accepting it while silently losing its cold-path representation.
export interface RecorderColdPathCaptureLimits {
  maxRetainedPackets: number;
  maxRetainedPayloadBytes: number;
}

export interface VitalServerDeliveryReplayLimits {
  maxAttempts: number;
  retryDelayMs: number;
}

export interface RecorderGatewayDeliveryReplayClaimSettlement {
  state: RecorderGatewayDeliveryReplayState;
  clearReplayPayload: boolean;
  nextAttemptAt?: string;
}

export function canAdmitRecorderIngressPacket(
  replayUsage: RecorderGatewayDeliveryReplayUsage,
  packetByteCount: number,
  limits: RecorderGatewayIngressAdmissionLimits,
): boolean {
  return replayUsage.pendingItems < limits.maxPendingItems && replayUsage.pendingBytes + packetByteCount <= limits.maxPendingBytes;
}

export function canRetainRecorderColdPathPacket(
  captureUsage: RecorderColdPathCaptureUsage,
  packetByteCount: number,
  limits: RecorderColdPathCaptureLimits,
): boolean {
  return (
    captureUsage.retainedPacketCount < limits.maxRetainedPackets &&
    captureUsage.retainedPayloadBytes + packetByteCount <= limits.maxRetainedPayloadBytes
  );
}

export function decideVitalServerDeliveryRetryDisposition(
  outcome: VitalServerDeliveryAttemptOutcome,
  attempt: number,
  limits: VitalServerDeliveryReplayLimits,
  completedAt: Date,
): VitalServerDeliveryReceipt["retry"] {
  if (outcome.state === "succeeded" || outcome.state === "unsupported") {
    return { state: "not-scheduled" };
  }
  const retryable = outcome.issue?.retryable !== false;
  if (!retryable || attempt >= limits.maxAttempts) {
    return { state: "exhausted" };
  }
  const nextAttemptAt = new Date(completedAt.getTime() + limits.retryDelayMs * attempt).toISOString();
  return { state: "scheduled", nextAttemptAt };
}

export function deriveRecorderGatewayDeliveryReplayClaimSettlementFromReceipt(receipt: VitalServerDeliveryReceipt): RecorderGatewayDeliveryReplayClaimSettlement {
  if (receipt.retry.state === "scheduled") {
    return {
      state: "pending",
      clearReplayPayload: false,
      nextAttemptAt: receipt.retry.nextAttemptAt,
    };
  }
  if (receipt.outcome.state === "succeeded") {
    return { state: "delivered", clearReplayPayload: true };
  }
  return { state: "terminal-failed", clearReplayPayload: false };
}

// normalizeVitalServerDeliveryAttemptOutcome validates an adapter result while preserving the
// concrete VitalServer provider that the Gateway configuration selected. A
// generic fallback such as "bundled" would turn a provider contract
// failure into an invented topology.
export function normalizeVitalServerDeliveryAttemptOutcome(candidate: VitalServerDeliveryAttemptOutcome, vitalServerProviderID: string): VitalServerDeliveryAttemptOutcome {
  const supported = new Set<VitalServerDeliveryAttemptOutcome["state"]>([
    "succeeded",
    "failed",
    "unavailable",
    "unsupported",
    "unknown",
  ]);
  if (!supported.has(candidate.state)) {
    return failedVitalServerDeliveryAttemptOutcome("vitalserver-delivery-outcome-invalid", "VitalServer delivery adapter returned an unknown delivery outcome", false, vitalServerProviderID);
  }
  if (candidate.state === "succeeded") {
    return { state: "succeeded" };
  }
  if (candidate.issue === undefined) {
    return failedVitalServerDeliveryAttemptOutcome("vitalserver-delivery-outcome-invalid", "VitalServer delivery adapter omitted the required delivery issue", false, vitalServerProviderID);
  }
  return candidate;
}

export function failedVitalServerDeliveryAttemptOutcome(code: string, message: string, retryable: boolean, vitalServerProviderID: string): VitalServerDeliveryAttemptOutcome {
  if (vitalServerProviderID === "") {
    throw new Error("VitalServer provider id is required for a delivery failure");
  }
  const issue: RecorderGatewayIssue = { code, message, retryable, dependency: vitalServerProviderID };
  return { state: "failed", issue };
}

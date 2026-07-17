import assert from "node:assert/strict";
import test from "node:test";

import {
  canAdmitRecorderIngressPacket,
  canRetainRecorderColdPathPacket,
  decideVitalServerDeliveryRetryDisposition,
  deriveRecorderGatewayDeliveryReplayClaimSettlementFromReceipt,
} from "../../recordergatewaydomain/recorder-gateway-vital-server-delivery-replay-policy.js";
import type { VitalServerDeliveryReceipt } from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";

test("admission capacity is bounded by both item and byte limits", () => {
  assert.equal(canAdmitRecorderIngressPacket({ pendingItems: 0, pendingBytes: 9 }, 1, { maxPendingItems: 1, maxPendingBytes: 10 }), true);
  assert.equal(canAdmitRecorderIngressPacket({ pendingItems: 1, pendingBytes: 0 }, 1, { maxPendingItems: 1, maxPendingBytes: 10 }), false);
  assert.equal(canAdmitRecorderIngressPacket({ pendingItems: 0, pendingBytes: 10 }, 1, { maxPendingItems: 2, maxPendingBytes: 10 }), false);
});

test("cold-path capture capacity is independent from delivery replay capacity", () => {
  assert.equal(
    canRetainRecorderColdPathPacket(
      { retainedPacketCount: 0, retainedPayloadBytes: 9 },
      1,
      { maxRetainedPackets: 1, maxRetainedPayloadBytes: 10 },
    ),
    true,
  );
  assert.equal(
    canRetainRecorderColdPathPacket(
      { retainedPacketCount: 1, retainedPayloadBytes: 0 },
      1,
      { maxRetainedPackets: 2, maxRetainedPayloadBytes: 10 },
    ),
    true,
  );
  assert.equal(
    canRetainRecorderColdPathPacket(
      { retainedPacketCount: 2, retainedPayloadBytes: 0 },
      1,
      { maxRetainedPackets: 2, maxRetainedPayloadBytes: 10 },
    ),
    false,
  );
});

test("unknown delivery outcomes are retried until the configured attempt limit", () => {
  const completedAt = new Date("2026-07-17T00:00:00.000Z");
  const scheduled = decideVitalServerDeliveryRetryDisposition(
    { state: "unknown", issue: { code: "ack-lost", retryable: true } },
    1,
    { maxAttempts: 3, retryDelayMs: 1000 },
    completedAt,
  );
  assert.deepEqual(scheduled, { state: "scheduled", nextAttemptAt: "2026-07-17T00:00:01.000Z" });
  assert.deepEqual(
    decideVitalServerDeliveryRetryDisposition(
      { state: "unknown", issue: { code: "ack-lost", retryable: true } },
      3,
      { maxAttempts: 3, retryDelayMs: 1000 },
      completedAt,
    ),
    { state: "exhausted" },
  );
});

test("only a succeeded receipt clears a delivery replay payload", () => {
  const receipt: VitalServerDeliveryReceipt = {
    schemaVersion: "v1",
    id: "delivery-receipt-1",
    deliveryRequestId: "delivery-request-1",
    ingressReceiptReference: { resourceType: "ingress-receipt", resourceId: "ingress-receipt-1" },
    provider: { kind: "vitalserver", id: "vitalserver-policy-fixture", capabilityRevision: 1 },
    attempt: 1,
    outcome: { state: "succeeded" },
    retry: { state: "not-scheduled" },
    completedAt: "2026-07-17T00:00:00.000Z",
  };
  assert.deepEqual(deriveRecorderGatewayDeliveryReplayClaimSettlementFromReceipt(receipt), { state: "delivered", clearReplayPayload: true });
  assert.deepEqual(
    deriveRecorderGatewayDeliveryReplayClaimSettlementFromReceipt({
      ...receipt,
      outcome: { state: "unavailable", issue: { code: "upstream-unavailable", retryable: true } },
      retry: { state: "scheduled", nextAttemptAt: "2026-07-17T00:00:01.000Z" },
    }),
    { state: "pending", clearReplayPayload: false, nextAttemptAt: "2026-07-17T00:00:01.000Z" },
  );
});

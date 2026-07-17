import { createHash, randomUUID } from "node:crypto";

import type {
  RecorderGatewayClock,
  RecorderGatewayIdentifierGenerator,
  RecorderGatewayIngressDurableStateStore,
  VitalServerPacketDeliveryPort,
} from "./recorder-gateway-ingress-and-cold-path-application-ports.js";
import {
  RecorderGatewayIngressDurableStateResourceNotFoundError,
  RecorderGatewayIngressDurableStateRevisionConflictError,
} from "./recorder-gateway-ingress-and-cold-path-application-ports.js";
import { RecorderGatewayIngressDurableStateOperationMutex } from "./recorder-gateway-ingress-durable-state-operation-mutex.js";
import {
  failedRecorderGatewayRead,
  finalizeRecorderColdPathCapturePacketSequence,
  invalidRecorderGatewayRead,
  isRecorderGatewayIdentifier,
  missingRecorderGatewayRead,
  recorderGatewaySchemaVersion,
  recorderGatewayTimestamp,
  type RecorderColdPathCapture,
  type RecorderColdPathCaptureFinalizationCommand,
  type RecorderColdPathCaptureFinalizationReceipt,
  type RecorderColdPathCaptureUsage,
  type RecorderColdPathCaptureOpenInput,
  type RecorderGatewayDeliveryReplayUsage,
  type RecorderGatewayIngressDurableRecord,
  type RecorderGatewayIssue,
  type RecorderGatewayReadResult,
  type RecorderIngressAcknowledgement,
  type RecorderIngressReceipt,
  type RecorderPacketIngressInput,
  type VitalServerDeliveryAttemptOutcome,
  type VitalServerDeliveryReceipt,
} from "../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";
import {
  canAdmitRecorderIngressPacket,
  canRetainRecorderColdPathPacket,
  decideVitalServerDeliveryRetryDisposition,
  deriveRecorderGatewayDeliveryReplayClaimSettlementFromReceipt,
  normalizeVitalServerDeliveryAttemptOutcome,
  type RecorderColdPathCaptureLimits,
  type RecorderGatewayIngressAdmissionLimits,
  type VitalServerDeliveryReplayLimits,
} from "../recordergatewaydomain/recorder-gateway-vital-server-delivery-replay-policy.js";

export interface RecorderGatewayIngressAndColdPathServiceConfiguration {
  ingressAdmission: RecorderGatewayIngressAdmissionLimits;
  coldPathCapture: RecorderColdPathCaptureLimits;
  replay: VitalServerDeliveryReplayLimits & {
    leaseDurationMs: number;
  };
  provider: {
    kind: string;
    id: string;
    capabilityRevision: number;
  };
}

export interface RecorderGatewayPacketAdmission {
  acknowledgement: RecorderIngressAcknowledgement;
  receipt?: RecorderIngressReceipt;
}

export interface RecorderColdPathCaptureOpenResult {
  state: "opened" | "rejected" | "failed";
  capture?: RecorderColdPathCapture;
  issue?: RecorderGatewayIssue;
}

export interface RecorderColdPathCaptureFinalizationResult {
  state: "finalized" | "rejected" | "failed";
  observedAt: string;
  receipt?: RecorderColdPathCaptureFinalizationReceipt;
  issue?: RecorderGatewayIssue;
  admissionState?: "not-admitted" | "unknown";
}

export interface RecorderGatewayDeliveryReplayRunResult {
  state: "idle" | "completed" | "failed";
  deliveryReceipt?: VitalServerDeliveryReceipt;
  issue?: RecorderGatewayIssue;
}

export class CryptoRecorderGatewayIdentifierGenerator implements RecorderGatewayIdentifierGenerator {
  public newRecorderGatewayIdentifier(prefix: string): string {
    if (!isRecorderGatewayIdentifier(prefix)) {
      throw new Error("identifier prefix must be a valid v1 identifier");
    }
    return `${prefix}-${randomUUID()}`;
  }
}

// RecorderGatewayIngressAndColdPathApplicationService sequences the two
// related Gateway aggregates. It owns no transport, filesystem, provider, or
// clock fact; every effect is delegated to a named port and any failed read or
// write remains a typed result rather than a fabricated ingress/archive state.
export class RecorderGatewayIngressAndColdPathApplicationService {
  private readonly durableStateOperationMutex = new RecorderGatewayIngressDurableStateOperationMutex();

  public constructor(
    private readonly durableStateStore: RecorderGatewayIngressDurableStateStore,
    private readonly vitalServerPacketDelivery: VitalServerPacketDeliveryPort,
    private readonly clock: RecorderGatewayClock,
    private readonly identifiers: RecorderGatewayIdentifierGenerator,
    private readonly configuration: RecorderGatewayIngressAndColdPathServiceConfiguration,
  ) {
    validateRecorderGatewayIngressAndColdPathServiceConfiguration(configuration);
  }

  public async initializeRecorderGatewayIngressDurableState(): Promise<void> {
    await this.durableStateStore.initializeRecorderGatewayIngressDurableState();
  }

  // Socket.IO join_vr is the explicit recorder-connection boundary that opens
  // a capture. A later packet is rejected unless this durable aggregate exists
  // and remains capturing; the Gateway never guesses capture identity from a
  // recorder code, log, or Socket.IO disconnect.
  public async openRecorderColdPathCapture(input: RecorderColdPathCaptureOpenInput): Promise<RecorderColdPathCaptureOpenResult> {
    return this.durableStateOperationMutex.runExclusiveRecorderGatewayIngressDurableStateOperation(async () => {
      if (!isRecorderGatewayIdentifier(input.recorderId) || !isRecorderGatewayIdentifier(input.connection.sessionId)) {
        return {
          state: "rejected",
          issue: { code: "invalid-recorder-cold-path-capture-reference", message: "recorder id and connection session id must be v1 identifiers" },
        };
      }
      let capture: RecorderColdPathCapture;
      try {
        capture = {
          schemaVersion: recorderGatewaySchemaVersion,
          id: this.identifiers.newRecorderGatewayIdentifier("recorder-cold-path-capture"),
          recorderId: input.recorderId,
          connection: input.connection,
          resourceRevision: 1,
          state: "capturing",
          openedAt: recorderGatewayTimestamp(this.clock.now()),
        };
      } catch {
        return {
          state: "failed",
          issue: {
            code: "recorder-cold-path-capture-identity-allocation-failed",
            message: "Recorder Gateway could not allocate an explicit identity for the cold-path capture",
            retryable: true,
            dependency: "recorder-gateway-identity",
          },
        };
      }
      try {
        await this.durableStateStore.createRecorderColdPathCapture(capture);
      } catch {
        return {
          state: "failed",
          issue: {
            code: "recorder-cold-path-capture-open-outcome-unknown",
            message: "Recorder Gateway could not determine whether the cold-path capture was durably opened",
            retryable: true,
            dependency: "gateway-ingress-durable-state",
          },
        };
      }
      return { state: "opened", capture };
    });
  }

  // A packet acknowledgement is sent only after the one Gateway durable record
  // contains both the replay payload and the cold-path capture payload. A
  // storage error is intentionally reported as an unknown admission outcome,
  // never as a false rejection or a synthetic receipt.
  public async admitRecorderPacket(input: RecorderPacketIngressInput): Promise<RecorderGatewayPacketAdmission> {
    return this.durableStateOperationMutex.runExclusiveRecorderGatewayIngressDurableStateOperation(async () => {
      const inputIssue = validateRecorderPacketIngressInput(input);
      if (inputIssue !== undefined) {
        return { acknowledgement: rejectedRecorderIngressAcknowledgement(inputIssue.code, inputIssue.message) };
      }
      const now = this.clock.now();
      let capture: RecorderColdPathCapture;
      try {
        capture = await this.durableStateStore.readRecorderColdPathCapture(input.coldPathCaptureId);
      } catch (error) {
        if (error instanceof RecorderGatewayIngressDurableStateResourceNotFoundError) {
          return {
            acknowledgement: rejectedRecorderIngressAcknowledgement("recorder-cold-path-capture-missing", "send_data requires an open Recorder Gateway cold-path capture"),
          };
        }
        return {
          acknowledgement: failedRecorderIngressAcknowledgement(undefined, {
            code: "recorder-cold-path-capture-read-failed",
            message: "Recorder Gateway could not read the required cold-path capture",
            retryable: true,
            dependency: "gateway-ingress-durable-state",
          }),
        };
      }
      if (
        capture.state !== "capturing" ||
        capture.recorderId !== input.recorderId ||
        capture.connection.sessionId !== input.connection.sessionId ||
        capture.connection.protocolVersion !== input.connection.protocolVersion
      ) {
        return {
          acknowledgement: rejectedRecorderIngressAcknowledgement("recorder-cold-path-capture-not-active-for-connection", "send_data capture identity does not describe an active recorder connection"),
        };
      }

      let deliveryReplayUsage: RecorderGatewayDeliveryReplayUsage;
      let coldPathCaptureUsage: RecorderColdPathCaptureUsage;
      try {
        [deliveryReplayUsage, coldPathCaptureUsage] = await Promise.all([
          this.durableStateStore.readRecorderGatewayDeliveryReplayUsage(),
          this.durableStateStore.readRecorderColdPathCaptureUsage(),
        ]);
      } catch {
        return {
          acknowledgement: {
            schemaVersion: recorderGatewaySchemaVersion,
            state: "failed",
            issue: {
              code: "recorder-gateway-ingress-durable-state-unavailable",
              message: "Recorder Gateway could not read durable delivery replay or cold-path capture capacity",
              retryable: true,
              dependency: "gateway-ingress-durable-state",
            },
          },
        };
      }
      if (!canAdmitRecorderIngressPacket(deliveryReplayUsage, input.payload.byteLength, this.configuration.ingressAdmission)) {
        return {
          acknowledgement: rejectedRecorderIngressAcknowledgement("vitalserver-delivery-replay-capacity-reached", "Recorder Gateway delivery replay reached its configured capacity", true, "gateway-delivery-replay"),
        };
      }
      if (!canRetainRecorderColdPathPacket(coldPathCaptureUsage, input.payload.byteLength, this.configuration.coldPathCapture)) {
        return {
          acknowledgement: rejectedRecorderIngressAcknowledgement("recorder-cold-path-capture-capacity-reached", "Recorder Gateway cold-path capture reached its configured retention capacity", true, "gateway-cold-path-capture"),
        };
      }

      let receiptId: string;
      let requestId: string;
      let deliveryRequestId: string;
      let packetId: string;
      let durableIngressStateReceiptId: string;
      try {
        receiptId = this.identifiers.newRecorderGatewayIdentifier("ingress-receipt");
        requestId = this.identifiers.newRecorderGatewayIdentifier("ingress-request");
        deliveryRequestId = this.identifiers.newRecorderGatewayIdentifier("delivery-request");
        packetId = this.identifiers.newRecorderGatewayIdentifier("packet");
        durableIngressStateReceiptId = this.identifiers.newRecorderGatewayIdentifier("durable-ingress-state-receipt");
      } catch {
        return {
          acknowledgement: failedRecorderIngressAcknowledgement(undefined, {
            code: "recorder-ingress-identity-allocation-failed",
            message: "Recorder Gateway could not allocate explicit ingress identities",
            retryable: true,
            dependency: "recorder-gateway-identity",
          }),
        };
      }
      const at = recorderGatewayTimestamp(now);
      const packetDigest = createHash("sha256").update(input.payload).digest("hex");

      const receipt: RecorderIngressReceipt = {
        schemaVersion: recorderGatewaySchemaVersion,
        id: receiptId,
        requestId,
        recorderId: input.recorderId,
        connection: input.connection,
        packet: {
          packetId,
          byteCount: input.payload.byteLength,
          payloadDigest: packetDigest,
          receivedAt: at,
          parseState: "accepted",
        },
        ingressState: "accepted",
        durableIngressStateHandoff: {
          state: "stored",
          durableIngressStateReceiptId,
          persistedAt: at,
        },
        coldPathCapture: {
          state: "captured",
          captureReference: { resourceType: "recorder-cold-path-capture", resourceId: capture.id },
          persistedAt: at,
        },
        delivery: {
          state: "requested",
          requestId: deliveryRequestId,
        },
        recordedAt: at,
      };
      const payloadBase64 = Buffer.from(input.payload).toString("base64");
      const record: RecorderGatewayIngressDurableRecord = {
        schemaVersion: recorderGatewaySchemaVersion,
        receipt,
        deliveryReplay: {
          payloadBase64,
          payloadEncoding: input.payloadEncoding,
          attempt: 0,
          state: "pending",
        },
        coldPathPacketCapture: {
          captureReference: { resourceType: "recorder-cold-path-capture", resourceId: capture.id },
          payloadBase64,
          payloadEncoding: input.payloadEncoding,
          capturedAt: at,
        },
      };
      try {
        await this.durableStateStore.persistAcceptedRecorderGatewayIngressDurableRecord(record);
      } catch {
        return {
          acknowledgement: failedRecorderIngressAcknowledgement(receiptId, {
            code: "ingress-admission-outcome-unknown",
            message: "Recorder Gateway could not determine whether the packet was durably admitted",
            retryable: true,
            dependency: "gateway-ingress-durable-state",
          }),
        };
      }
      return {
        acknowledgement: { schemaVersion: recorderGatewaySchemaVersion, state: "accepted", receiptId },
        receipt,
      };
    });
  }

  public async readRecorderIngressReceipt(receiptId: string): Promise<RecorderGatewayReadResult<RecorderIngressReceipt>> {
    return this.durableStateOperationMutex.runExclusiveRecorderGatewayIngressDurableStateOperation(async () => {
      const at = recorderGatewayTimestamp(this.clock.now());
      if (!isRecorderGatewayIdentifier(receiptId)) {
        return invalidRecorderGatewayRead(at, { code: "invalid-ingress-receipt-id", message: "receiptId must be a v1 identifier" });
      }
      try {
        const receipt = await this.durableStateStore.readRecorderIngressReceipt(receiptId);
        return { schemaVersion: recorderGatewaySchemaVersion, state: "available", observedAt: at, value: receipt };
      } catch (error) {
        if (error instanceof RecorderGatewayIngressDurableStateResourceNotFoundError) {
          return missingRecorderGatewayRead(at, { code: "ingress-receipt-missing", message: "the requested ingress receipt does not exist" });
        }
        return failedRecorderGatewayRead(at, {
          code: "gateway-ingress-durable-state-read-failed",
          message: "Recorder Gateway could not read the requested ingress receipt",
          retryable: true,
          dependency: "gateway-ingress-durable-state",
        });
      }
    });
  }

  public async readVitalServerDeliveryReceipt(receiptId: string): Promise<RecorderGatewayReadResult<VitalServerDeliveryReceipt>> {
    return this.durableStateOperationMutex.runExclusiveRecorderGatewayIngressDurableStateOperation(async () => {
      const at = recorderGatewayTimestamp(this.clock.now());
      if (!isRecorderGatewayIdentifier(receiptId)) {
        return invalidRecorderGatewayRead(at, { code: "invalid-delivery-receipt-id", message: "receiptId must be a v1 identifier" });
      }
      try {
        const receipt = await this.durableStateStore.readVitalServerDeliveryReceipt(receiptId);
        return { schemaVersion: recorderGatewaySchemaVersion, state: "available", observedAt: at, value: receipt };
      } catch (error) {
        if (error instanceof RecorderGatewayIngressDurableStateResourceNotFoundError) {
          return missingRecorderGatewayRead(at, { code: "delivery-receipt-missing", message: "the requested delivery receipt does not exist" });
        }
        return failedRecorderGatewayRead(at, {
          code: "gateway-ingress-durable-state-read-failed",
          message: "Recorder Gateway could not read the requested VitalServer delivery receipt",
          retryable: true,
          dependency: "gateway-ingress-durable-state",
        });
      }
    });
  }

  public async readRecorderColdPathCapture(captureId: string): Promise<RecorderGatewayReadResult<RecorderColdPathCapture>> {
    return this.durableStateOperationMutex.runExclusiveRecorderGatewayIngressDurableStateOperation(async () => {
      const at = recorderGatewayTimestamp(this.clock.now());
      if (!isRecorderGatewayIdentifier(captureId)) {
        return invalidRecorderGatewayRead(at, { code: "invalid-recorder-cold-path-capture-id", message: "coldPathCaptureId must be a v1 identifier" });
      }
      try {
        const capture = await this.durableStateStore.readRecorderColdPathCapture(captureId);
        return { schemaVersion: recorderGatewaySchemaVersion, state: "available", observedAt: at, value: capture, sourceRevision: capture.resourceRevision };
      } catch (error) {
        if (error instanceof RecorderGatewayIngressDurableStateResourceNotFoundError) {
          return missingRecorderGatewayRead(at, { code: "recorder-cold-path-capture-missing", message: "the requested Recorder Cold-Path Capture does not exist" });
        }
        return failedRecorderGatewayRead(at, {
          code: "recorder-cold-path-capture-read-failed",
          message: "Recorder Gateway could not read the requested cold-path capture",
          retryable: true,
          dependency: "gateway-ingress-durable-state",
        });
      }
    });
  }

  public async readRecorderColdPathCaptureFinalizationReceipt(receiptId: string): Promise<RecorderGatewayReadResult<RecorderColdPathCaptureFinalizationReceipt>> {
    return this.durableStateOperationMutex.runExclusiveRecorderGatewayIngressDurableStateOperation(async () => {
      const at = recorderGatewayTimestamp(this.clock.now());
      if (!isRecorderGatewayIdentifier(receiptId)) {
        return invalidRecorderGatewayRead(at, { code: "invalid-recorder-cold-path-finalization-receipt-id", message: "receiptId must be a v1 identifier" });
      }
      try {
        const receipt = await this.durableStateStore.readRecorderColdPathCaptureFinalizationReceipt(receiptId);
        return { schemaVersion: recorderGatewaySchemaVersion, state: "available", observedAt: at, value: receipt };
      } catch (error) {
        if (error instanceof RecorderGatewayIngressDurableStateResourceNotFoundError) {
          return missingRecorderGatewayRead(at, { code: "recorder-cold-path-finalization-receipt-missing", message: "the requested cold-path finalization receipt does not exist" });
        }
        return failedRecorderGatewayRead(at, {
          code: "recorder-cold-path-finalization-receipt-read-failed",
          message: "Recorder Gateway could not read the requested cold-path finalization receipt",
          retryable: true,
          dependency: "gateway-ingress-durable-state",
        });
      }
    });
  }

  public async finalizeRecorderColdPathCapture(command: RecorderColdPathCaptureFinalizationCommand): Promise<RecorderColdPathCaptureFinalizationResult> {
    return this.durableStateOperationMutex.runExclusiveRecorderGatewayIngressDurableStateOperation(async () => {
      const now = recorderGatewayTimestamp(this.clock.now());
      const validationIssue = validateRecorderColdPathCaptureFinalizationCommand(command);
      if (validationIssue !== undefined) {
        return { state: "rejected", observedAt: now, issue: validationIssue };
      }
      let existing: RecorderColdPathCaptureFinalizationReceipt | undefined;
      try {
        existing = await this.durableStateStore.findRecorderColdPathCaptureFinalizationReceiptByRequestId(command.requestId);
      } catch {
        return {
          state: "failed",
          observedAt: now,
          admissionState: "not-admitted",
          issue: {
            code: "recorder-cold-path-finalization-idempotency-read-failed",
            message: "Recorder Gateway could not read cold-path finalization request ownership",
            retryable: true,
            dependency: "gateway-ingress-durable-state",
          },
        };
      }
      if (existing !== undefined) {
        if (
          existing.captureReference.resourceId === command.coldPathCaptureId &&
          existing.expectedCaptureRevision === command.expectedCaptureRevision
        ) {
          return { state: "finalized", observedAt: now, receipt: existing };
        }
        return {
          state: "rejected",
          observedAt: now,
          issue: { code: "request-id-reused-with-different-command", message: "requestId already belongs to a different Recorder Cold-Path Capture finalization" },
        };
      }
      let capture: RecorderColdPathCapture;
      try {
        capture = await this.durableStateStore.readRecorderColdPathCapture(command.coldPathCaptureId);
      } catch (error) {
        if (error instanceof RecorderGatewayIngressDurableStateResourceNotFoundError) {
          return { state: "rejected", observedAt: now, issue: { code: "recorder-cold-path-capture-missing", message: "the requested Recorder Cold-Path Capture does not exist" } };
        }
        return {
          state: "failed",
          observedAt: now,
          admissionState: "not-admitted",
          issue: {
            code: "recorder-cold-path-capture-read-failed",
            message: "Recorder Gateway could not read the cold-path capture before finalization",
            retryable: true,
            dependency: "gateway-ingress-durable-state",
          },
        };
      }
      if (capture.resourceRevision !== command.expectedCaptureRevision) {
        return { state: "rejected", observedAt: now, issue: { code: "recorder-cold-path-capture-revision-conflict", message: "expectedCaptureRevision does not match the current capture revision" } };
      }
      if (capture.state !== "capturing") {
        return { state: "rejected", observedAt: now, issue: { code: "recorder-cold-path-capture-not-capturing", message: "only a capturing Recorder Cold-Path Capture can be finalized" } };
      }
      let capturedPackets;
      try {
        capturedPackets = await this.durableStateStore.readRecorderColdPathCapturedPackets(capture.id);
      } catch {
        return {
          state: "failed",
          observedAt: now,
          admissionState: "not-admitted",
          issue: {
            code: "recorder-cold-path-packet-sequence-read-failed",
            message: "Recorder Gateway could not read the cold-path packet sequence",
            retryable: true,
            dependency: "gateway-ingress-durable-state",
          },
        };
      }
      if (capturedPackets.length === 0) {
        return { state: "rejected", observedAt: now, issue: { code: "recorder-cold-path-capture-empty", message: "a cold-path capture needs at least one accepted packet before finalization" } };
      }
      let receipt: RecorderColdPathCaptureFinalizationReceipt;
      try {
        receipt = finalizeRecorderColdPathCapturePacketSequence(
          this.identifiers.newRecorderGatewayIdentifier("recorder-cold-path-finalization-receipt"),
          command,
          capture,
          capturedPackets,
          now,
        );
      } catch {
        return {
          state: "failed",
          observedAt: now,
          admissionState: "not-admitted",
          issue: {
            code: "recorder-cold-path-packet-sequence-finalization-failed",
            message: "Recorder Gateway could not construct finalization evidence for the cold-path packet sequence",
            retryable: false,
            dependency: "recorder-gateway",
          },
        };
      }
      try {
        await this.durableStateStore.commitRecorderColdPathCaptureFinalization(capture.id, command.expectedCaptureRevision, receipt);
      } catch (error) {
        if (error instanceof RecorderGatewayIngressDurableStateRevisionConflictError) {
          return { state: "rejected", observedAt: now, issue: { code: "recorder-cold-path-capture-revision-conflict", message: "Recorder Cold-Path Capture changed before finalization could be committed" } };
        }
        return {
          state: "failed",
          observedAt: now,
          admissionState: "unknown",
          issue: {
            code: "recorder-cold-path-finalization-admission-outcome-unknown",
            message: "Recorder Gateway could not determine whether cold-path finalization was durably committed",
            retryable: true,
            dependency: "gateway-ingress-durable-state",
          },
        };
      }
      return { state: "finalized", observedAt: now, receipt };
    });
  }

  public async replayOneDueVitalServerDelivery(): Promise<RecorderGatewayDeliveryReplayRunResult> {
    return this.durableStateOperationMutex.runExclusiveRecorderGatewayIngressDurableStateOperation(async () => {
      const now = this.clock.now();
      try {
        await this.recoverExpiredRecorderGatewayDeliveryReplayClaims(now);
        const claimed = await this.durableStateStore.claimNextDueRecorderGatewayDeliveryReplayRecord(now, new Date(now.getTime() + this.configuration.replay.leaseDurationMs));
        if (claimed === undefined) {
          return { state: "idle" };
        }
        return await this.deliverClaimedRecorderGatewayIngressDurableRecordToVitalServer(claimed);
      } catch {
        return {
          state: "failed",
          issue: {
            code: "gateway-delivery-replay-durable-state-failed",
            message: "Recorder Gateway could not read or update VitalServer delivery replay state",
            retryable: true,
            dependency: "gateway-ingress-durable-state",
          },
        };
      }
    });
  }

  private async recoverExpiredRecorderGatewayDeliveryReplayClaims(now: Date): Promise<void> {
    const claims = await this.durableStateStore.listExpiredRecorderGatewayDeliveryReplayClaims(now);
    for (const claim of claims) {
      const existing = await this.durableStateStore.findVitalServerDeliveryReceiptForAttempt(claim.receipt.delivery.requestId, claim.deliveryReplay.attempt);
      if (existing !== undefined) {
        await this.durableStateStore.settleRecorderGatewayDeliveryReplayClaim(claim.receipt.id, claim.deliveryReplay.attempt, deriveRecorderGatewayDeliveryReplayClaimSettlementFromReceipt(existing));
        continue;
      }
      const outcome: VitalServerDeliveryAttemptOutcome = {
        state: "unknown",
        issue: {
          code: "delivery-attempt-lease-expired",
          message: "Recorder Gateway lost the delivery attempt outcome before it was durably recorded",
          retryable: true,
          dependency: "gateway-delivery-replay-worker",
        },
      };
      const receipt = this.newVitalServerDeliveryReceipt(claim, outcome, now);
      await this.durableStateStore.persistVitalServerDeliveryReceipt(receipt);
      await this.durableStateStore.settleRecorderGatewayDeliveryReplayClaim(claim.receipt.id, claim.deliveryReplay.attempt, deriveRecorderGatewayDeliveryReplayClaimSettlementFromReceipt(receipt));
    }
  }

  private async deliverClaimedRecorderGatewayIngressDurableRecordToVitalServer(claim: RecorderGatewayIngressDurableRecord): Promise<RecorderGatewayDeliveryReplayRunResult> {
    const replayPayload = claim.deliveryReplay.payloadBase64 === undefined ? undefined : Buffer.from(claim.deliveryReplay.payloadBase64, "base64");
    let candidate: VitalServerDeliveryAttemptOutcome;
    if (replayPayload === undefined || claim.deliveryReplay.payloadEncoding === undefined) {
      candidate = {
        state: "failed",
        issue: {
          code: "delivery-replay-payload-missing",
          message: "Recorder Gateway claimed a delivery replay record without a replayable payload",
          retryable: false,
          dependency: "gateway-ingress-durable-state",
        },
      };
    } else {
      try {
        candidate = await this.vitalServerPacketDelivery.deliverRecorderPacketToVitalServer({
          deliveryRequestId: claim.receipt.delivery.requestId,
          ingressReceiptId: claim.receipt.id,
          attempt: claim.deliveryReplay.attempt,
          payload: replayPayload,
          payloadEncoding: claim.deliveryReplay.payloadEncoding,
        });
      } catch {
        candidate = {
          state: "unknown",
          issue: {
            code: "vitalserver-delivery-adapter-threw",
            message: "VitalServer delivery adapter did not return a typed outcome",
            retryable: true,
            dependency: this.configuration.provider.id,
          },
        };
      }
    }
    const completedAt = this.clock.now();
    const receipt = this.newVitalServerDeliveryReceipt(claim, normalizeVitalServerDeliveryAttemptOutcome(candidate, this.configuration.provider.id), completedAt);
    try {
      await this.durableStateStore.persistVitalServerDeliveryReceipt(receipt);
    } catch {
      return {
        state: "failed",
        issue: {
          code: "delivery-receipt-write-outcome-unknown",
          message: "Recorder Gateway could not durably record the VitalServer delivery outcome",
          retryable: true,
          dependency: "gateway-ingress-durable-state",
        },
      };
    }
    try {
      await this.durableStateStore.settleRecorderGatewayDeliveryReplayClaim(claim.receipt.id, claim.deliveryReplay.attempt, deriveRecorderGatewayDeliveryReplayClaimSettlementFromReceipt(receipt));
    } catch {
      return {
        state: "failed",
        deliveryReceipt: receipt,
        issue: {
          code: "delivery-replay-settlement-write-failed",
          message: "Recorder Gateway recorded the delivery outcome but could not settle its replay claim",
          retryable: true,
          dependency: "gateway-ingress-durable-state",
        },
      };
    }
    return { state: "completed", deliveryReceipt: receipt };
  }

  private newVitalServerDeliveryReceipt(claim: RecorderGatewayIngressDurableRecord, outcome: VitalServerDeliveryAttemptOutcome, completedAt: Date): VitalServerDeliveryReceipt {
    return {
      schemaVersion: recorderGatewaySchemaVersion,
      id: this.identifiers.newRecorderGatewayIdentifier("delivery-receipt"),
      deliveryRequestId: claim.receipt.delivery.requestId,
      ingressReceiptReference: {
        resourceType: "ingress-receipt",
        resourceId: claim.receipt.id,
      },
      provider: this.configuration.provider,
      attempt: claim.deliveryReplay.attempt,
      outcome,
      retry: decideVitalServerDeliveryRetryDisposition(outcome, claim.deliveryReplay.attempt, this.configuration.replay, completedAt),
      completedAt: recorderGatewayTimestamp(completedAt),
    };
  }
}

function validateRecorderColdPathCaptureFinalizationCommand(command: RecorderColdPathCaptureFinalizationCommand): RecorderGatewayIssue | undefined {
  if (command.schemaVersion !== recorderGatewaySchemaVersion) {
    return { code: "unsupported-schema-version", message: "schemaVersion must be v1" };
  }
  if (!isRecorderGatewayIdentifier(command.requestId) || !isRecorderGatewayIdentifier(command.coldPathCaptureId) || command.expectedCaptureRevision < 1) {
    return { code: "invalid-recorder-cold-path-finalization-command", message: "requestId, coldPathCaptureId, and expectedCaptureRevision must be valid" };
  }
  return undefined;
}

function validateRecorderPacketIngressInput(input: RecorderPacketIngressInput): RecorderGatewayIssue | undefined {
  if (
    !isRecorderGatewayIdentifier(input.recorderId) ||
    !isRecorderGatewayIdentifier(input.connection.sessionId) ||
    input.connection.protocolVersion !== "v2" ||
    !isRecorderGatewayIdentifier(input.coldPathCaptureId) ||
    !(input.payload instanceof Uint8Array) ||
    (input.payloadEncoding !== "binary" && input.payloadEncoding !== "binary-string")
  ) {
    return {
      code: "invalid-recorder-packet-ingress-input",
      message: "recorderId, connection, coldPathCaptureId, packet bytes, and payload encoding must describe one v2 recorder ingress packet",
    };
  }
  return undefined;
}

function rejectedRecorderIngressAcknowledgement(code: string, message: string | undefined, retryable = false, dependency = "recorder-gateway"): RecorderIngressAcknowledgement {
  return {
    schemaVersion: recorderGatewaySchemaVersion,
    state: "rejected",
    issue: { code, message, retryable, dependency },
  };
}

function failedRecorderIngressAcknowledgement(receiptId: string | undefined, issue: RecorderGatewayIssue): RecorderIngressAcknowledgement {
  return { schemaVersion: recorderGatewaySchemaVersion, state: "failed", receiptId, issue };
}

function validateRecorderGatewayIngressAndColdPathServiceConfiguration(configuration: RecorderGatewayIngressAndColdPathServiceConfiguration): void {
  if (
    configuration.ingressAdmission.maxPendingItems < 1 ||
    configuration.ingressAdmission.maxPendingBytes < 1 ||
    configuration.coldPathCapture.maxRetainedPackets < 1 ||
    configuration.coldPathCapture.maxRetainedPayloadBytes < 1 ||
    configuration.replay.maxAttempts < 1 ||
    configuration.replay.retryDelayMs < 1 ||
    configuration.replay.leaseDurationMs < 1 ||
    !isRecorderGatewayIdentifier(configuration.provider.kind) ||
    !isRecorderGatewayIdentifier(configuration.provider.id) ||
    configuration.provider.capabilityRevision < 1
  ) {
    throw new Error("Recorder Gateway ingress and cold-path service configuration is invalid");
  }
}

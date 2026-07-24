import { createHash } from "node:crypto";

import type {
  LabRecorderRunnerClock,
  LabRecorderRunnerIdentifierGenerator,
  LabReplayGatewayPort,
  LabReplaySessionStore,
} from "./lab-recorder-runner-ports.js";
import { LabReplaySessionNotFoundError } from "./lab-recorder-runner-ports.js";
import {
  labReplayFrameIdentity,
  stableLabReplayBatchCommandDigest,
  type ConfirmLabReplayUpstreamCommand,
  type LabReplayCommandResult,
  type LabReplayMessageBatchReceipt,
  type LabReplayPreparationReceipt,
  type LabReplaySession,
  type LabReplayUpstreamDeliveryReceipt,
  type PrepareLabReplayCommand,
  type SendLabReplayBatchCommand,
  validateConfirmLabReplayUpstreamCommand,
  validatePrepareLabReplayCommand,
  validateSendLabReplayBatchCommand,
} from "../labrecorderrunnerdomain/lab-replay-contracts.js";
import type { LabRecorderRunnerIssue } from "../labrecorderrunnerdomain/lab-recorder-run-contracts.js";

export class LabReplayApplicationService {
  private workflow: Promise<void> = Promise.resolve();

  public constructor(
    private readonly store: LabReplaySessionStore,
    private readonly gateway: LabReplayGatewayPort,
    private readonly clock: LabRecorderRunnerClock,
    private readonly identifiers: LabRecorderRunnerIdentifierGenerator,
  ) {}

  public initialize(): Promise<void> {
    return this.store.initialize();
  }

  public prepare(
    command: PrepareLabReplayCommand,
  ): Promise<LabReplayCommandResult<LabReplayPreparationReceipt>> {
    return this.exclusive(async () => {
      const issue = validatePrepareLabReplayCommand(command);
      if (issue !== undefined) {
        return { state: "rejected", issue };
      }
      let existing: LabReplaySession | undefined;
      try {
        existing = await this.store.readByReplayId(command.replayId);
      } catch (error) {
        if (!(error instanceof LabReplaySessionNotFoundError)) {
          return failed("lab-replay-session-read-failed", "Runner could not read durable replay preparation state");
        }
      }
      if (existing !== undefined) {
        const receipt = existing.preparationReceipt;
        if (
          receipt.spoolDatabaseSha256 !== command.spoolDatabaseSha256 ||
          receipt.frameCount !== command.frameCount ||
          existing.recorderGatewayRecorderCode !== command.recorderGatewayRecorderCode
        ) {
          return rejected("lab-replay-preparation-conflict", "replayId already belongs to different replay preparation evidence");
        }
        return { state: "accepted", receipt };
      }
      const now = this.clock.now();
      const receipt: LabReplayPreparationReceipt = {
        schemaVersion: "v1",
        replayId: command.replayId,
        runnerSessionId: this.identifiers.newLabRecorderRunnerIdentifier("lab-replay-session"),
        spoolDatabaseSha256: command.spoolDatabaseSha256,
        frameCount: command.frameCount,
        outputStartedAt: now.getTime() / 1000,
        preparedAt: now.toISOString(),
      };
      const session: LabReplaySession = {
        schemaVersion: "v1",
        preparationReceipt: receipt,
        recorderGatewayRecorderCode: command.recorderGatewayRecorderCode,
        batches: [],
      };
      try {
        await this.store.create(session);
      } catch {
        try {
          const resolved = await this.store.readByReplayId(command.replayId);
          if (
            resolved.preparationReceipt.spoolDatabaseSha256 === command.spoolDatabaseSha256 &&
            resolved.preparationReceipt.frameCount === command.frameCount &&
            resolved.recorderGatewayRecorderCode === command.recorderGatewayRecorderCode
          ) {
            return { state: "accepted", receipt: resolved.preparationReceipt };
          }
        } catch {
          // The create outcome remains unknown below.
        }
        return failed("lab-replay-preparation-write-outcome-unknown", "Runner could not determine whether replay preparation was durably stored");
      }
      return { state: "accepted", receipt };
    });
  }

  public sendBatch(
    command: SendLabReplayBatchCommand,
  ): Promise<LabReplayCommandResult<LabReplayMessageBatchReceipt>> {
    return this.exclusive(async () => {
      const issue = validateSendLabReplayBatchCommand(command);
      if (issue !== undefined) {
        return { state: "rejected", issue };
      }
      const session = await this.readSession(command.runnerSessionId);
      if ("state" in session) {
        return session;
      }
      if (session.preparationReceipt.replayId !== command.replayId) {
        return rejected("lab-replay-session-mismatch", "Runner session does not belong to replayId");
      }
      const commandDigest = stableLabReplayBatchCommandDigest(command);
      const existing = session.batches.find((batch) => batch.receipt.batchId === command.batchId);
      if (existing !== undefined) {
        if (existing.commandDigest !== commandDigest) {
          return rejected("lab-replay-batch-id-conflict", "batchId already belongs to different frame evidence");
        }
        return { state: "accepted", receipt: existing.receipt };
      }
      const acceptedFrameCount = session.batches.reduce(
        (count, batch) => count + batch.receipt.frameCount,
        0,
      );
      const nextFrameCount = command.startOffsetSecond + command.frames.length;
      if (
        command.startOffsetSecond !== acceptedFrameCount ||
        nextFrameCount > session.preparationReceipt.frameCount ||
        command.finalBatch !== (nextFrameCount === session.preparationReceipt.frameCount) ||
        command.frames.some(
          (frame) =>
            Math.abs(
              frame.outputTime -
                (session.preparationReceipt.outputStartedAt + frame.offsetSeconds),
            ) > 0.000001,
        )
      ) {
        return rejected("lab-replay-batch-sequence-invalid", "batch does not continue the durable Runner cursor or final frame boundary");
      }
      const admissions = command.frames.map((frame) => ({
        frame,
        identity: labReplayFrameIdentity(
          command.replayId,
          frame.offsetSeconds,
          Buffer.from(JSON.stringify(frame), "utf8"),
        ),
      }));
      let admitted: Awaited<ReturnType<LabReplayGatewayPort["admitFrames"]>>;
      try {
        admitted = await this.gateway.admitFrames(
          session.recorderGatewayRecorderCode,
          admissions,
        );
      } catch {
        return failed("recorder-gateway-replay-admission-outcome-unknown", "Runner could not determine Gateway replay frame admission outcome");
      }
      if (admitted.state !== "accepted") {
        return { state: admitted.state, issue: admitted.issue };
      }
      if (
        admitted.ingressReceiptIds.length !== command.frames.length ||
        admitted.ingressReceiptIds.some(
          (receiptId, index) => receiptId !== admissions[index]?.identity.receiptId,
        )
      ) {
        return failed("recorder-gateway-replay-admission-receipt-mismatch", "Gateway did not return one matching ingress receipt per replay frame");
      }
      const receipt: LabReplayMessageBatchReceipt = {
        schemaVersion: "v1",
        replayId: command.replayId,
        runnerSessionId: command.runnerSessionId,
        batchId: command.batchId,
        startOffsetSecond: command.startOffsetSecond,
        frameCount: command.frames.length,
        finalBatch: command.finalBatch,
        acceptedAt: this.clock.now().toISOString(),
      };
      const next: LabReplaySession = {
        ...session,
        batches: [
          ...session.batches,
          { commandDigest, receipt, ingressReceiptIds: admitted.ingressReceiptIds },
        ],
      };
      try {
        await this.store.replace(session, next);
      } catch {
        try {
          const resolved = await this.store.readByRunnerSessionId(command.runnerSessionId);
          const resolvedBatch = resolved.batches.find(
            (batch) => batch.receipt.batchId === command.batchId,
          );
          if (resolvedBatch?.commandDigest === commandDigest) {
            return { state: "accepted", receipt: resolvedBatch.receipt };
          }
        } catch {
          // The replace outcome remains unknown below.
        }
        return failed("lab-replay-batch-write-outcome-unknown", "Runner could not determine whether the accepted replay batch was durably stored");
      }
      return { state: "accepted", receipt };
    });
  }

  public confirmUpstream(
    command: ConfirmLabReplayUpstreamCommand,
  ): Promise<LabReplayCommandResult<LabReplayUpstreamDeliveryReceipt>> {
    return this.exclusive(async () => {
      const issue = validateConfirmLabReplayUpstreamCommand(command);
      if (issue !== undefined) {
        return { state: "rejected", issue };
      }
      const session = await this.readSession(command.runnerSessionId);
      if ("state" in session) {
        return session;
      }
      if (
        session.preparationReceipt.replayId !== command.replayId ||
        session.preparationReceipt.frameCount !== command.expectedFrameCount
      ) {
        return rejected("lab-replay-delivery-confirmation-conflict", "delivery confirmation does not match replay preparation evidence");
      }
      if (session.upstreamDeliveryReceipt !== undefined) {
        return { state: "accepted", receipt: session.upstreamDeliveryReceipt };
      }
      const ingressReceiptIds = session.batches.flatMap((batch) => batch.ingressReceiptIds);
      if (
        ingressReceiptIds.length !== command.expectedFrameCount ||
        session.batches.at(-1)?.receipt.finalBatch !== true
      ) {
        return rejected("lab-replay-delivery-confirmation-premature", "all replay frames must have durable Gateway ingress receipts before delivery confirmation");
      }
      const deliveryReceiptIds: string[] = [];
      for (const ingressReceiptId of ingressReceiptIds) {
        let delivery: Awaited<ReturnType<LabReplayGatewayPort["readLatestDelivery"]>>;
        try {
          delivery = await this.gateway.readLatestDelivery(ingressReceiptId);
        } catch {
          return failed("recorder-gateway-delivery-read-outcome-unknown", "Runner could not determine Gateway delivery receipt state");
        }
        if (delivery.state === "pending") {
          return failed("vitalserver-delivery-pending", "Gateway has not produced terminal VitalServer delivery evidence for every replay frame");
        }
        if (delivery.state === "failed") {
          return delivery;
        }
        if (delivery.attemptOutcome !== "succeeded") {
          if (delivery.retryState === "scheduled") {
            return failed("vitalserver-delivery-retry-scheduled", "Gateway has scheduled another VitalServer delivery attempt");
          }
          return rejected("vitalserver-delivery-terminal-failure", `Gateway delivery ended as ${delivery.attemptOutcome}`);
        }
        deliveryReceiptIds.push(delivery.deliveryReceiptId);
      }
      const confirmedAt = this.clock.now().toISOString();
      const receipt: LabReplayUpstreamDeliveryReceipt = {
        schemaVersion: "v1",
        replayId: command.replayId,
        runnerSessionId: command.runnerSessionId,
        deliveryReceiptId: `lab-upstream-${createHash("sha256").update(deliveryReceiptIds.join(":"), "utf8").digest("hex")}`,
        deliveredFrameCount: command.expectedFrameCount,
        deliveryConfirmedAt: confirmedAt,
      };
      try {
        await this.store.replace(session, { ...session, upstreamDeliveryReceipt: receipt });
      } catch {
        try {
          const resolved = await this.store.readByRunnerSessionId(command.runnerSessionId);
          if (resolved.upstreamDeliveryReceipt?.deliveryReceiptId === receipt.deliveryReceiptId) {
            return { state: "accepted", receipt: resolved.upstreamDeliveryReceipt };
          }
        } catch {
          // The replace outcome remains unknown below.
        }
        return failed("lab-replay-delivery-receipt-write-outcome-unknown", "Runner could not determine whether upstream delivery evidence was durably stored");
      }
      return { state: "accepted", receipt };
    });
  }

  private async readSession(
    runnerSessionId: string,
  ): Promise<LabReplaySession | { state: "rejected" | "failed"; issue: LabRecorderRunnerIssue }> {
    try {
      return await this.store.readByRunnerSessionId(runnerSessionId);
    } catch (error) {
      if (error instanceof LabReplaySessionNotFoundError) {
        return {
          state: "rejected",
          issue: {
            code: "lab-replay-session-missing",
            message: "Runner has no durable replay session for runnerSessionId",
            retryable: false,
            dependency: "lab-recorder-runner",
          },
        };
      }
      return {
        state: "failed",
        issue: {
          code: "lab-replay-session-read-failed",
          message: "Runner could not read durable replay session state",
          retryable: true,
          dependency: "lab-recorder-runner",
        },
      };
    }
  }

  private async exclusive<T>(work: () => Promise<T>): Promise<T> {
    const prior = this.workflow;
    let release: (() => void) | undefined;
    this.workflow = new Promise<void>((resolve) => {
      release = resolve;
    });
    await prior;
    try {
      return await work();
    } finally {
      release?.();
    }
  }
}

function rejected<T>(code: string, message: string): LabReplayCommandResult<T> {
  return {
    state: "rejected",
    issue: { code, message, retryable: false, dependency: "lab-recorder-runner" },
  };
}

function failed<T>(code: string, message: string): LabReplayCommandResult<T> {
  return {
    state: "failed",
    issue: { code, message, retryable: true, dependency: "lab-recorder-runner" },
  };
}

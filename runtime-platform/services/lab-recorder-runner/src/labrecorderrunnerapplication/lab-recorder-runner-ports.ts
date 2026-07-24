import type { LabRecorderRun, LabRecorderRunnerIssue, RecorderObservationDelivery, RecorderObservationPublishCommand, StartLabRecorderRunCommand } from "../labrecorderrunnerdomain/lab-recorder-run-contracts.js";
import type {
  LabReplayFrame,
  LabReplaySession,
} from "../labrecorderrunnerdomain/lab-replay-contracts.js";

export interface LabRecorderRunnerClock {
  now(): Date;
}

export interface LabRecorderRunnerIdentifierGenerator {
  newLabRecorderRunnerIdentifier(prefix: string): string;
}

export interface LabRecorderScenarioExecutionHandle {
  readEmittedPacketCount(): number;
  stopAndFinalize(requestId: string): Promise<{ state: "finalized"; finalizationReceipt: LabRecorderRun["finalizationReceipt"] } | { state: "rejected" | "failed"; issue: LabRecorderRunnerIssue }>;
  close(): void;
}

// LabRecorderScenarioExecutionPort owns one live Socket.IO effect. It must not
// manufacture a Lab transition, Archive manifest, or upstream upload receipt.
export interface LabRecorderScenarioExecutionPort {
  startScenario(command: StartLabRecorderRunCommand): Promise<
    | { state: "started"; coldPathCaptureId: string; recorderGatewayRecorderId: string; handle: LabRecorderScenarioExecutionHandle }
    | { state: "rejected" | "failed"; issue: LabRecorderRunnerIssue }
  >;
}

// RecorderObservationPublisher is the sole outbound C19 boundary for a
// Recorder-owned self-observation. It cannot infer delivery from HTTP reachability
// and must return its own explicit catalog-submission outcome.
export interface RecorderObservationPublisher {
  publishRecorderObservation(command: RecorderObservationPublishCommand): Promise<RecorderObservationDelivery>;
}

export class LabReplaySessionNotFoundError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "LabReplaySessionNotFoundError";
  }
}

export interface LabReplaySessionStore {
  initialize(): Promise<void>;
  readByReplayId(replayId: string): Promise<LabReplaySession>;
  readByRunnerSessionId(runnerSessionId: string): Promise<LabReplaySession>;
  create(session: LabReplaySession): Promise<void>;
  replace(current: LabReplaySession, next: LabReplaySession): Promise<void>;
}

export interface LabReplayGatewayFrameAdmission {
  frame: LabReplayFrame;
  identity: {
    receiptId: string;
    requestId: string;
    deliveryRequestId: string;
    packetId: string;
    durableIngressStateReceiptId: string;
  };
}

export interface LabReplayGatewayPort {
  admitFrames(
    recorderGatewayRecorderCode: string,
    frames: LabReplayGatewayFrameAdmission[],
  ): Promise<
    | { state: "accepted"; ingressReceiptIds: string[] }
    | { state: "rejected" | "failed"; issue: LabRecorderRunnerIssue }
  >;
  readLatestDelivery(
    ingressReceiptId: string,
  ): Promise<
    | {
      state: "available";
      deliveryReceiptId: string;
      attemptOutcome: "succeeded" | "failed" | "unavailable" | "unsupported" | "unknown";
      retryState: "not-scheduled" | "scheduled" | "exhausted";
    }
    | { state: "pending" }
    | { state: "failed"; issue: LabRecorderRunnerIssue }
  >;
}

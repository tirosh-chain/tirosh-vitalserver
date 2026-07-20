import type { LabRecorderRun, LabRecorderRunnerIssue, RecorderObservationDelivery, RecorderObservationPublishCommand, StartLabRecorderRunCommand } from "../labrecorderrunnerdomain/lab-recorder-run-contracts.js";

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

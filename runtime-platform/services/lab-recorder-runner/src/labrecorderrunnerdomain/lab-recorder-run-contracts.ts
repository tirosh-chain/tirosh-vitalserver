export const labRecorderRunnerSchemaVersion = "v1";

export interface LabScenarioDefinition {
  id: string;
  packetIntervalMilliseconds: number;
  minimumPacketCountBeforeStop: number;
  archiveOnTerminalStop: boolean;
}

export interface StartLabRecorderRunCommand {
  schemaVersion: string;
  requestId: string;
  virtualRecorderId: string;
  recorderGatewayRecorderCode: string;
  scenario: LabScenarioDefinition;
}

export interface StopLabRecorderRunCommand {
  schemaVersion: string;
  requestId: string;
  expectedRunRevision: number;
}

export interface LabRecorderRunnerIssue {
  code: string;
  message: string;
  retryable?: boolean;
  dependency?: string;
}

export interface RecorderGatewayFinalizationReceiptReference {
  kind: "recorder-gateway-cold-path-finalization-receipt";
  id: string;
  captureId: string;
  recorderId: string;
  finalizedAt: string;
}

// RecorderObservationDelivery records the Runner-owned outcome of submitting
// the virtual Recorder's self-observation to the Guest catalog. It is not a
// Catalog projection and cannot be used as a Gateway or Archive receipt.
export type RecorderObservationDelivery =
  | { state: "published"; observationId: string }
  | { state: "failed"; issue: LabRecorderRunnerIssue };

export interface RecorderObservationEnvelope {
  schemaVersion: "v1";
  protocolVersion: "v1";
  recorderId: string;
  bootId: string;
  sequence: number;
  occurredAt: string;
  time: { state: "not-reported" };
  runtime: { state: "ready"; version: string };
}

export interface RecorderObservationPublishCommand {
  schemaVersion: "v1";
  requestId: string;
  observationId: string;
  envelope: RecorderObservationEnvelope;
}

// LabRecorderRun is a Runner-owned live-effect resource. It is intentionally
// separate from the durable Lab virtual-recorder lifecycle state. A Runner
// restart cannot be translated into `stopped` or a generated finalization
// receipt by a consumer.
export interface LabRecorderRun {
  schemaVersion: string;
  id: string;
  requestId: string;
  virtualRecorderId: string;
  recorderGatewayRecorderCode: string;
  recorderGatewayRecorderId: string;
  coldPathCaptureId: string;
  scenarioId: string;
  archiveOnTerminalStop: boolean;
  resourceRevision: number;
  state: "running" | "finalized" | "failed";
  emittedPacketCount: number;
  observationDelivery: RecorderObservationDelivery;
  startedAt: string;
  updatedAt: string;
  finalizationReceipt?: RecorderGatewayFinalizationReceiptReference;
  issue?: LabRecorderRunnerIssue;
}

export type LabRecorderRunStartResult =
  | { state: "running"; run: LabRecorderRun }
  | { state: "rejected"; issue: LabRecorderRunnerIssue }
  | { state: "failed"; issue: LabRecorderRunnerIssue };

export type LabRecorderRunStopResult =
  | { state: "finalized"; run: LabRecorderRun }
  | { state: "rejected"; issue: LabRecorderRunnerIssue }
  | { state: "failed"; issue: LabRecorderRunnerIssue };

export function validateStartLabRecorderRunCommand(command: StartLabRecorderRunCommand): LabRecorderRunnerIssue | undefined {
  if (command.schemaVersion !== labRecorderRunnerSchemaVersion) {
    return { code: "unsupported-schema-version", message: "schemaVersion must be v1" };
  }
  if (!isLabRecorderRunnerIdentifier(command.requestId) || !isLabRecorderRunnerIdentifier(command.virtualRecorderId) || !isLabRecorderRunnerIdentifier(command.recorderGatewayRecorderCode)) {
    return { code: "invalid-lab-recorder-run-identity", message: "requestId, virtualRecorderId, and recorderGatewayRecorderCode must be v1 identifiers" };
  }
  if (!isValidScenario(command.scenario)) {
    return { code: "invalid-lab-recorder-scenario", message: "scenario must declare a valid identifier, packet interval, minimum packet count, and archive policy" };
  }
  if (!isLabRecorderRunnerIdentifier(`recorder-${command.recorderGatewayRecorderCode}`)) {
    return { code: "invalid-recorder-gateway-recorder-code", message: "recorderGatewayRecorderCode is too long for the Recorder Gateway recorder identifier contract" };
  }
  return undefined;
}

export function validateStopLabRecorderRunCommand(command: StopLabRecorderRunCommand): LabRecorderRunnerIssue | undefined {
  if (command.schemaVersion !== labRecorderRunnerSchemaVersion) {
    return { code: "unsupported-schema-version", message: "schemaVersion must be v1" };
  }
  if (!isLabRecorderRunnerIdentifier(command.requestId)) {
    return { code: "invalid-request-id", message: "requestId must be a v1 identifier" };
  }
  if (!Number.isInteger(command.expectedRunRevision) || command.expectedRunRevision < 1) {
    return { code: "invalid-expected-run-revision", message: "expectedRunRevision must be one or greater" };
  }
  return undefined;
}

export function isLabRecorderRunnerIdentifier(value: unknown): value is string {
  return typeof value === "string" && /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(value);
}

function isValidScenario(value: LabScenarioDefinition): boolean {
  return isLabRecorderRunnerIdentifier(value.id) && Number.isInteger(value.packetIntervalMilliseconds) && value.packetIntervalMilliseconds >= 20 && value.packetIntervalMilliseconds <= 60_000 &&
    Number.isInteger(value.minimumPacketCountBeforeStop) && value.minimumPacketCountBeforeStop >= 1 && value.minimumPacketCountBeforeStop <= 10_000 && typeof value.archiveOnTerminalStop === "boolean";
}

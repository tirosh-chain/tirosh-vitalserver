import { randomUUID } from "node:crypto";

import type { LabRecorderScenarioExecutionPort, LabRecorderRunnerClock, LabRecorderRunnerIdentifierGenerator, LabRecorderScenarioExecutionHandle, RecorderObservationPublisher } from "./lab-recorder-runner-ports.js";
import {
  labRecorderRunnerSchemaVersion,
  type LabRecorderRun,
  type LabRecorderRunStartResult,
  type LabRecorderRunStopResult,
  type LabRecorderRunnerIssue,
  type StartLabRecorderRunCommand,
  type StopLabRecorderRunCommand,
  validateStartLabRecorderRunCommand,
  validateStopLabRecorderRunCommand,
} from "../labrecorderrunnerdomain/lab-recorder-run-contracts.js";

export class SystemLabRecorderRunnerClock implements LabRecorderRunnerClock {
  public now(): Date {
    return new Date();
  }
}

export class CryptoLabRecorderRunnerIdentifierGenerator implements LabRecorderRunnerIdentifierGenerator {
  public newLabRecorderRunnerIdentifier(prefix: string): string {
    return `${prefix}-${randomUUID()}`;
  }
}

interface ActiveLabRecorderRun {
  run: LabRecorderRun;
  handle: LabRecorderScenarioExecutionHandle;
  commandDigest: string;
  stopCommandDigest?: string;
}

// LabRecorderRunnerApplicationService owns only live run records and their
// idempotency while this process is alive. Guest Runtime Lab owns durable
// desired execution state and never treats a missing Runner process record as
// a stopped Lab recorder.
export class LabRecorderRunnerApplicationService {
  private readonly activeRunsByID = new Map<string, ActiveLabRecorderRun>();
  private readonly activeRunsByStartRequestID = new Map<string, ActiveLabRecorderRun>();
  private readonly nextObservationSequenceByRecorderID = new Map<string, number>();
  private readonly bootID: string;

  public constructor(
    private readonly execution: LabRecorderScenarioExecutionPort,
    private readonly observations: RecorderObservationPublisher,
    private readonly clock: LabRecorderRunnerClock = new SystemLabRecorderRunnerClock(),
    private readonly identifiers: LabRecorderRunnerIdentifierGenerator = new CryptoLabRecorderRunnerIdentifierGenerator(),
  ) {
    this.bootID = this.identifiers.newLabRecorderRunnerIdentifier("lab-recorder-runner-boot");
  }

  public async startLabRecorderRun(command: StartLabRecorderRunCommand): Promise<LabRecorderRunStartResult> {
    const issue = validateStartLabRecorderRunCommand(command);
    if (issue !== undefined) {
      return { state: "rejected", issue };
    }
    const commandDigest = stableStartCommandDigest(command);
    const existing = this.activeRunsByStartRequestID.get(command.requestId);
    if (existing !== undefined) {
      if (existing.commandDigest === commandDigest) {
        return { state: "running", run: cloneRun(existing.run, existing.handle.readEmittedPacketCount()) };
      }
      return { state: "rejected", issue: { code: "request-id-reused-with-different-command", message: "requestId already belongs to a different Lab recorder run command" } };
    }
    const execution = await this.execution.startScenario(command);
    if (execution.state !== "started") {
      return execution;
    }
    const at = timestamp(this.clock.now());
    const observationDelivery = await this.publishStartedRecorderObservation(execution.recorderGatewayRecorderId, at);
    const run: LabRecorderRun = {
      schemaVersion: labRecorderRunnerSchemaVersion,
      id: this.identifiers.newLabRecorderRunnerIdentifier("lab-recorder-run"),
      requestId: command.requestId,
      virtualRecorderId: command.virtualRecorderId,
      recorderGatewayRecorderCode: command.recorderGatewayRecorderCode,
      recorderGatewayRecorderId: execution.recorderGatewayRecorderId,
      coldPathCaptureId: execution.coldPathCaptureId,
      scenarioId: command.scenario.id,
      archiveOnTerminalStop: command.scenario.archiveOnTerminalStop,
      resourceRevision: 1,
      state: "running",
      emittedPacketCount: execution.handle.readEmittedPacketCount(),
      observationDelivery,
      startedAt: at,
      updatedAt: at,
    };
    const active = { run, handle: execution.handle, commandDigest };
    this.activeRunsByID.set(run.id, active);
    this.activeRunsByStartRequestID.set(command.requestId, active);
    return { state: "running", run: cloneRun(run, execution.handle.readEmittedPacketCount()) };
  }

  private async publishStartedRecorderObservation(recorderID: string, occurredAt: string): Promise<LabRecorderRun["observationDelivery"]> {
    const sequence = this.nextObservationSequenceByRecorderID.get(recorderID) ?? 0;
    this.nextObservationSequenceByRecorderID.set(recorderID, sequence + 1);
    const observationID = this.identifiers.newLabRecorderRunnerIdentifier("recorder-observation");
    const requestID = this.identifiers.newLabRecorderRunnerIdentifier("recorder-observation-publish");
    try {
      return await this.observations.publishRecorderObservation({
        schemaVersion: labRecorderRunnerSchemaVersion,
        requestId: requestID,
        observationId: observationID,
        envelope: {
          schemaVersion: labRecorderRunnerSchemaVersion,
          protocolVersion: labRecorderRunnerSchemaVersion,
          recorderId: recorderID,
          bootId: this.bootID,
          sequence,
          occurredAt,
          // The virtual Recorder Runner has no independent NTP authority.
          // It must say not-reported rather than manufacture Host/Guest time.
          time: { state: "not-reported" },
          runtime: { state: "ready", version: "lab-recorder-runner-0.1.0" },
        },
      });
    } catch (error) {
      return { state: "failed", issue: { code: "recorder-observation-publish-outcome-unknown", message: `Lab recorder Runner could not determine Recorder observation publication outcome: ${error instanceof Error ? error.message : "unknown error"}`, retryable: true, dependency: "guest-runtime-observation-catalog" } };
    }
  }

  public readLabRecorderRun(id: string): { state: "available"; value: LabRecorderRun } | { state: "missing"; issue: LabRecorderRunnerIssue } | { state: "invalid"; issue: LabRecorderRunnerIssue } {
    if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(id)) {
      return { state: "invalid", issue: { code: "invalid-lab-recorder-run-id", message: "run id must be a v1 identifier" } };
    }
    const active = this.activeRunsByID.get(id);
    if (active === undefined) {
      return { state: "missing", issue: { code: "lab-recorder-run-live-effect-missing", message: "the Runner has no live effect record for this run; this does not describe Lab lifecycle state" } };
    }
    return { state: "available", value: cloneRun(active.run, active.handle.readEmittedPacketCount()) };
  }

  public async stopLabRecorderRun(id: string, command: StopLabRecorderRunCommand): Promise<LabRecorderRunStopResult> {
    const issue = validateStopLabRecorderRunCommand(command);
    if (issue !== undefined) {
      return { state: "rejected", issue };
    }
    const active = this.activeRunsByID.get(id);
    if (active === undefined) {
      return { state: "rejected", issue: { code: "lab-recorder-run-live-effect-missing", message: "the Runner has no live effect record for this run; it cannot finalize a guessed Gateway capture" } };
    }
    const commandDigest = stableStopCommandDigest(command);
    if (active.stopCommandDigest !== undefined) {
      if (active.stopCommandDigest !== commandDigest) {
        return { state: "rejected", issue: { code: "request-id-reused-with-different-command", message: "requestId already belongs to a different Lab recorder stop command" } };
      }
      if (active.run.state === "finalized") {
        return { state: "finalized", run: cloneRun(active.run, active.handle.readEmittedPacketCount()) };
      }
      return { state: "failed", issue: active.run.issue ?? { code: "lab-recorder-stop-outcome-unknown", message: "the prior stop result was not finalized", retryable: true, dependency: "lab-recorder-runner" } };
    }
    if (active.run.resourceRevision !== command.expectedRunRevision) {
      return { state: "rejected", issue: { code: "lab-recorder-run-revision-conflict", message: "expectedRunRevision does not match the Runner live run" } };
    }
    active.stopCommandDigest = commandDigest;
    const stopped = await active.handle.stopAndFinalize(command.requestId);
    if (stopped.state !== "finalized" || stopped.finalizationReceipt === undefined) {
      const stopIssue = "issue" in stopped ? stopped.issue : undefined;
      active.run = {
        ...active.run,
        resourceRevision: active.run.resourceRevision + 1,
        state: "failed",
        emittedPacketCount: active.handle.readEmittedPacketCount(),
        updatedAt: timestamp(this.clock.now()),
        issue: stopIssue ?? { code: "lab-recorder-finalization-result-invalid", message: "Runner received no complete Recorder Gateway finalization receipt", retryable: true, dependency: "recorder-gateway" },
      };
      return { state: "failed", issue: active.run.issue ?? { code: "lab-recorder-finalization-result-invalid", message: "Runner recorded no finalization issue", retryable: true, dependency: "recorder-gateway" } };
    }
    active.run = {
      ...active.run,
      resourceRevision: active.run.resourceRevision + 1,
      state: "finalized",
      emittedPacketCount: active.handle.readEmittedPacketCount(),
      updatedAt: timestamp(this.clock.now()),
      finalizationReceipt: stopped.finalizationReceipt,
      issue: undefined,
    };
    active.handle.close();
    return { state: "finalized", run: cloneRun(active.run, active.handle.readEmittedPacketCount()) };
  }

  public close(): void {
    for (const active of this.activeRunsByID.values()) {
      active.handle.close();
    }
    this.activeRunsByID.clear();
    this.activeRunsByStartRequestID.clear();
  }
}

function stableStartCommandDigest(command: StartLabRecorderRunCommand): string {
  return JSON.stringify(command);
}

function stableStopCommandDigest(command: StopLabRecorderRunCommand): string {
  return JSON.stringify(command);
}

function cloneRun(run: LabRecorderRun, emittedPacketCount: number): LabRecorderRun {
	return {
		...run,
		emittedPacketCount,
		observationDelivery: run.observationDelivery.state === "published" ? { ...run.observationDelivery } : { state: "failed", issue: { ...run.observationDelivery.issue } },
		finalizationReceipt: run.finalizationReceipt === undefined ? undefined : { ...run.finalizationReceipt },
		issue: run.issue === undefined ? undefined : { ...run.issue },
	};
}

function timestamp(value: Date): string {
  return value.toISOString();
}

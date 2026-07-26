import assert from "node:assert/strict";
import test from "node:test";

import { LabRecorderRunnerApplicationService } from "../../labrecorderrunnerapplication/lab-recorder-runner-application-service.js";
import type { LabRecorderScenarioExecutionHandle, LabRecorderScenarioExecutionPort } from "../../labrecorderrunnerapplication/lab-recorder-runner-ports.js";
import type { RecorderObservationPublisher } from "../../labrecorderrunnerapplication/lab-recorder-runner-ports.js";
import type { StartLabRecorderRunCommand } from "../../labrecorderrunnerdomain/lab-recorder-run-contracts.js";

test("a Runner run keeps Gateway capture finalization distinct from its Lab caller", async () => {
  const execution = new FakeExecutionPort();
  const observations = new FakeObservationPublisher();
  const service = new LabRecorderRunnerApplicationService(execution, observations, new FixedClock(), new FixedIdentifiers());
  const command = startCommand("runner-start-1");

  const started = await service.startLabRecorderRun(command);
  assert.equal(started.state, "running");
  if (started.state !== "running") {
    return;
  }
  assert.equal(started.run.recorderGatewayRecorderId, "recorder-virtual-recorder-1");
  assert.equal(started.run.coldPathCaptureId, "capture-1");
  assert.equal(started.run.archiveOnTerminalStop, true);
  assert.equal(started.run.emittedPacketCount, 2);
  assert.deepEqual(started.run.observationDelivery, { state: "published", observationId: "recorder-observation-1" });
  assert.equal(observations.commands.length, 1);
  assert.equal(observations.commands[0]?.envelope.recorderId, "recorder-virtual-recorder-1");
  assert.deepEqual(observations.commands[0]?.envelope.time, { state: "not-reported" });

  const finalized = await service.stopLabRecorderRun(started.run.id, { schemaVersion: "v1", requestId: "runner-stop-1", expectedRunRevision: 1 });
  assert.equal(finalized.state, "finalized");
  if (finalized.state !== "finalized") {
    return;
  }
  assert.equal(finalized.run.state, "finalized");
  assert.deepEqual(finalized.run.finalizationReceipt, {
    kind: "recorder-gateway-cold-path-finalization-receipt",
    id: "finalization-1",
    captureId: "capture-1",
    recorderId: "recorder-virtual-recorder-1",
    finalizedAt: "2026-07-19T00:00:00.000Z",
  });
  assert.equal(execution.lastHandle?.closed, true);
});

test("a Runner does not replace a stopped effect with a second finalization command", async () => {
  const execution = new FakeExecutionPort();
  const service = new LabRecorderRunnerApplicationService(execution, new FakeObservationPublisher(), new FixedClock(), new FixedIdentifiers());
  const started = await service.startLabRecorderRun(startCommand("runner-start-2"));
  assert.equal(started.state, "running");
  if (started.state !== "running") {
    return;
  }
  const first = await service.stopLabRecorderRun(started.run.id, { schemaVersion: "v1", requestId: "runner-stop-2", expectedRunRevision: 1 });
  const replay = await service.stopLabRecorderRun(started.run.id, { schemaVersion: "v1", requestId: "runner-stop-2", expectedRunRevision: 1 });
  assert.equal(first.state, "finalized");
  assert.equal(replay.state, "finalized");
  assert.equal(execution.lastHandle?.stopCallCount, 1);
});

test("a Runner rejects a start request ID reused for a different virtual recorder", async () => {
  const execution = new FakeExecutionPort();
  const service = new LabRecorderRunnerApplicationService(execution, new FakeObservationPublisher(), new FixedClock(), new FixedIdentifiers());
  const first = await service.startLabRecorderRun(startCommand("runner-start-3"));
  assert.equal(first.state, "running");
  const conflicting = await service.startLabRecorderRun({ ...startCommand("runner-start-3"), virtualRecorderId: "virtual-recorder-2" });
  assert.deepEqual(conflicting, {
    state: "rejected",
    issue: {
      code: "request-id-reused-with-different-command",
      message: "requestId already belongs to a different Lab recorder run command",
    },
  });
});

class FixedClock {
  public now(): Date {
    return new Date("2026-07-19T00:00:00.000Z");
  }
}

class FixedIdentifiers {
  public newLabRecorderRunnerIdentifier(prefix: string): string {
    return `${prefix}-1`;
  }
}

class FakeExecutionPort implements LabRecorderScenarioExecutionPort {
  public lastHandle: FakeExecutionHandle | undefined;

  public async startScenario(command: StartLabRecorderRunCommand) {
    this.lastHandle = new FakeExecutionHandle(command.recorderGatewayRecorderCode);
    return {
      state: "started" as const,
      coldPathCaptureId: "capture-1",
      recorderGatewayRecorderId: `recorder-${command.recorderGatewayRecorderCode}`,
      handle: this.lastHandle,
    };
  }
}

class FakeObservationPublisher implements RecorderObservationPublisher {
  public readonly commands: import("../../labrecorderrunnerdomain/lab-recorder-run-contracts.js").RecorderObservationPublishCommand[] = [];
  public async publishRecorderObservation(command: import("../../labrecorderrunnerdomain/lab-recorder-run-contracts.js").RecorderObservationPublishCommand) {
    this.commands.push(command);
    return { state: "published" as const, observationId: command.observationId };
  }
}

class FakeExecutionHandle implements LabRecorderScenarioExecutionHandle {
  public closed = false;
  public stopCallCount = 0;

  public constructor(private readonly recorderCode: string) {}

  public readEmittedPacketCount(): number {
    return 2;
  }

  public async stopAndFinalize() {
    this.stopCallCount += 1;
    return {
      state: "finalized" as const,
      finalizationReceipt: {
        kind: "recorder-gateway-cold-path-finalization-receipt" as const,
        id: "finalization-1",
        captureId: "capture-1",
        recorderId: `recorder-${this.recorderCode}`,
        finalizedAt: "2026-07-19T00:00:00.000Z",
      },
    };
  }

  public close(): void {
    this.closed = true;
  }
}

function startCommand(requestId: string): StartLabRecorderRunCommand {
  return {
    schemaVersion: "v1",
    requestId,
    virtualRecorderId: "virtual-recorder-1",
    recorderGatewayRecorderCode: "virtual-recorder-1",
    scenario: {
      id: "baseline-monitoring",
      packetIntervalMilliseconds: 100,
      minimumPacketCountBeforeStop: 1,
      archiveOnTerminalStop: true,
    },
  };
}

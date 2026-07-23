import {
  decideRecorderObservabilityExpectation,
  type RecorderObservabilityExpectationCommand,
  type RecorderObservabilityExpectationEvent,
  type RecorderObservabilityExpectationProjection,
} from "../../src/domain/recorder-observability-expectation";

"use strict";

const assert = require("assert");
const test = require("node:test");

const commandId = "1d5cce97-1b83-47ea-a7e3-95459dce6b41";
const eventId = "a3abf2b5-338a-4d8d-a416-25f02ff31ad7";

test("accepts a supported expectation and creates an active next revision", () => {
  const decision = decideRecorderObservabilityExpectation({
    command: setCommand(),
    current: null,
    existingEvent: null,
    eventId,
    receivedAt: "2026-07-24T01:01:00Z",
  });

  assert.strictEqual(decision.kind, "accepted");
  if (decision.kind !== "accepted") return;
  assert.strictEqual(decision.event.previousRevision, 0);
  assert.strictEqual(decision.event.revision, 1);
  assert.strictEqual(decision.projection.lifecycleState, "active");
  assert.strictEqual(decision.projection.sourceEventId, eventId);
});

test("returns the original event for an identical command id retry", () => {
  const event = acceptedEvent({
    ...setCommand(),
    decidedAt: "2026-07-24T01:00:00.000Z",
    expectedSince: "2026-07-24T01:00:00.000Z",
  });
  const decision = decideRecorderObservabilityExpectation({
    command: setCommand(),
    current: activeProjection(event),
    existingEvent: event,
    eventId: "be315157-58d0-4812-a775-eb95ee4222ba",
    receivedAt: "2026-07-24T02:00:00Z",
  });

  assert.deepStrictEqual(decision, {
    kind: "idempotent",
    currentRevision: 1,
    event,
  });
});

test("rejects reuse of a command id with different command content", () => {
  const event = acceptedEvent(setCommand());
  const decision = decideRecorderObservabilityExpectation({
    command: { ...setCommand(), supportState: "unsupported", expectedSince: null },
    current: activeProjection(event),
    existingEvent: event,
    eventId,
    receivedAt: "2026-07-24T02:00:00Z",
  });

  assert.deepStrictEqual(decision, {
    kind: "rejected",
    currentRevision: 1,
    failure: "commandIdConflict",
  });
});

test("does not let a stale command replace the current expectation", () => {
  const event = acceptedEvent(setCommand());
  const decision = decideRecorderObservabilityExpectation({
    command: { ...setCommand(), commandId: "af936e2f-cdbc-4585-895b-5888e3a2f7ae" },
    current: activeProjection(event),
    existingEvent: null,
    eventId,
    receivedAt: "2026-07-24T02:00:00Z",
  });

  assert.deepStrictEqual(decision, {
    kind: "revisionConflict",
    currentRevision: 1,
    failure: "revisionConflict",
  });
});

test("requires expectedSince when support is supported", () => {
  const decision = decideRecorderObservabilityExpectation({
    command: { ...setCommand(), expectedSince: null },
    current: null,
    existingEvent: null,
    eventId,
    receivedAt: "2026-07-24T02:00:00Z",
  });

  assert.deepStrictEqual(decision, {
    kind: "rejected",
    currentRevision: 0,
    failure: "expectedSinceRequired",
  });
});

test("clear creates a retained cleared projection without support evidence", () => {
  const currentEvent = acceptedEvent(setCommand());
  const clear: RecorderObservabilityExpectationCommand = {
    commandId: "7f094e87-322f-4e6a-88a1-611cbdb4acc5",
    vrcode: "VR_A",
    expectedRevision: 1,
    action: "clear",
    supportState: null,
    source: null,
    recorderVersion: null,
    producerVersion: null,
    protocolVersion: null,
    catalogRevision: null,
    expectedSince: null,
    evidenceDocument: {},
    decidedAt: "2026-07-24T02:00:00Z",
  };
  const decision = decideRecorderObservabilityExpectation({
    command: clear,
    current: activeProjection(currentEvent),
    existingEvent: null,
    eventId,
    receivedAt: "2026-07-24T02:01:00Z",
  });

  assert.strictEqual(decision.kind, "accepted");
  if (decision.kind !== "accepted") return;
  assert.deepStrictEqual(decision.projection, {
    vrcode: "VR_A",
    revision: 2,
    lifecycleState: "cleared",
    sourceEventId: eventId,
    supportState: null,
    source: null,
    recorderVersion: null,
    producerVersion: null,
    protocolVersion: null,
    catalogRevision: null,
    expectedSince: null,
    evidenceDocument: {},
    updatedAt: "2026-07-24T02:01:00Z",
  });
});

function setCommand(): RecorderObservabilityExpectationCommand {
  return {
    commandId,
    vrcode: "VR_A",
    expectedRevision: 0,
    action: "set",
    supportState: "supported",
    source: "deployment_assignment",
    recorderVersion: "1.20.0",
    producerVersion: "2.0.0",
    protocolVersion: "1",
    catalogRevision: null,
    expectedSince: "2026-07-24T01:00:00Z",
    evidenceDocument: { deploymentId: "deployment-1" },
    decidedAt: "2026-07-24T01:00:00Z",
  };
}

function acceptedEvent(
  command: RecorderObservabilityExpectationCommand,
): RecorderObservabilityExpectationEvent {
  return {
    ...command,
    eventId,
    previousRevision: 0,
    revision: 1,
    receivedAt: "2026-07-24T01:01:00Z",
  };
}

function activeProjection(
  event: RecorderObservabilityExpectationEvent,
): RecorderObservabilityExpectationProjection {
  return {
    vrcode: event.vrcode,
    revision: event.revision,
    lifecycleState: "active",
    sourceEventId: event.eventId,
    supportState: event.supportState,
    source: event.source,
    recorderVersion: event.recorderVersion,
    producerVersion: event.producerVersion,
    protocolVersion: event.protocolVersion,
    catalogRevision: event.catalogRevision,
    expectedSince: event.expectedSince,
    evidenceDocument: event.evidenceDocument,
    updatedAt: event.receivedAt,
  };
}

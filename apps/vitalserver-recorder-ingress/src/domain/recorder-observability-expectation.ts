export type RecorderObservabilityExpectationSource =
  | "deployment_assignment"
  | "version_catalog"
  | "manual";

export type RecorderObservabilityExpectationCommand = {
  commandId: string;
  vrcode: string;
  expectedRevision: number;
  action: "set" | "clear";
  supportState: "supported" | "unsupported" | null;
  source: RecorderObservabilityExpectationSource | null;
  recorderVersion: string | null;
  producerVersion: string | null;
  protocolVersion: string | null;
  catalogRevision: string | null;
  expectedSince: string | null;
  evidenceDocument: Record<string, unknown>;
  decidedAt: string;
};

export type RecorderObservabilityExpectationEvent =
  RecorderObservabilityExpectationCommand & {
    eventId: string;
    previousRevision: number;
    revision: number;
    receivedAt: string;
  };

export type RecorderObservabilityExpectationProjection = {
  vrcode: string;
  revision: number;
  lifecycleState: "active" | "cleared";
  sourceEventId: string;
  supportState: "supported" | "unsupported" | null;
  source: RecorderObservabilityExpectationSource | null;
  recorderVersion: string | null;
  producerVersion: string | null;
  protocolVersion: string | null;
  catalogRevision: string | null;
  expectedSince: string | null;
  evidenceDocument: Record<string, unknown>;
  updatedAt: string;
};

export type RecorderObservabilityExpectationDecision =
  | {
      kind: "accepted";
      currentRevision: number;
      event: RecorderObservabilityExpectationEvent;
      projection: RecorderObservabilityExpectationProjection;
    }
  | {
      kind: "idempotent";
      currentRevision: number;
      event: RecorderObservabilityExpectationEvent;
    }
  | {
      kind: "revisionConflict";
      currentRevision: number;
      failure: "revisionConflict";
    }
  | {
      kind: "rejected";
      currentRevision: number;
      failure: RecorderObservabilityExpectationFailure;
    };

export type RecorderObservabilityExpectationFailure =
  | "invalidCommandId"
  | "invalidVrcode"
  | "invalidExpectedRevision"
  | "invalidDecidedAt"
  | "invalidReceivedAt"
  | "invalidEvidenceDocument"
  | "setFieldsMissing"
  | "expectedSinceRequired"
  | "invalidExpectedSince"
  | "clearFieldsPresent"
  | "commandIdConflict";

export function decideRecorderObservabilityExpectation(input: {
  command: RecorderObservabilityExpectationCommand;
  current: RecorderObservabilityExpectationProjection | null;
  existingEvent: RecorderObservabilityExpectationEvent | null;
  eventId: string;
  receivedAt: string;
}): RecorderObservabilityExpectationDecision {
  const currentRevision = input.current?.revision ?? 0;
  const failure = validateRecorderObservabilityExpectationCommand(
    input.command,
    input.receivedAt,
  );
  if (failure) {
    return { kind: "rejected", currentRevision, failure };
  }
  if (input.existingEvent) {
    if (sameCommand(input.existingEvent, input.command)) {
      return {
        kind: "idempotent",
        currentRevision,
        event: input.existingEvent,
      };
    }
    return {
      kind: "rejected",
      currentRevision,
      failure: "commandIdConflict",
    };
  }
  if (input.command.expectedRevision !== currentRevision) {
    return {
      kind: "revisionConflict",
      currentRevision,
      failure: "revisionConflict",
    };
  }

  const revision = currentRevision + 1;
  const event: RecorderObservabilityExpectationEvent = {
    ...input.command,
    eventId: input.eventId,
    previousRevision: currentRevision,
    revision,
    receivedAt: input.receivedAt,
  };
  return {
    kind: "accepted",
    currentRevision: revision,
    event,
    projection: projectionFromEvent(event),
  };
}

function projectionFromEvent(
  event: RecorderObservabilityExpectationEvent,
): RecorderObservabilityExpectationProjection {
  const active = event.action === "set";
  return {
    vrcode: event.vrcode,
    revision: event.revision,
    lifecycleState: active ? "active" : "cleared",
    sourceEventId: event.eventId,
    supportState: active ? event.supportState : null,
    source: active ? event.source : null,
    recorderVersion: active ? event.recorderVersion : null,
    producerVersion: active ? event.producerVersion : null,
    protocolVersion: active ? event.protocolVersion : null,
    catalogRevision: active ? event.catalogRevision : null,
    expectedSince: active ? event.expectedSince : null,
    evidenceDocument: active ? event.evidenceDocument : {},
    updatedAt: event.receivedAt,
  };
}

export function validateRecorderObservabilityExpectationCommand(
  command: RecorderObservabilityExpectationCommand,
  receivedAt: string,
): RecorderObservabilityExpectationFailure | null {
  if (!uuid(command.commandId)) return "invalidCommandId";
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(command.vrcode)) {
    return "invalidVrcode";
  }
  if (!Number.isSafeInteger(command.expectedRevision) || command.expectedRevision < 0) {
    return "invalidExpectedRevision";
  }
  if (!timestamp(command.decidedAt)) return "invalidDecidedAt";
  if (!timestamp(receivedAt)) return "invalidReceivedAt";
  if (
    !command.evidenceDocument
    || Array.isArray(command.evidenceDocument)
    || typeof command.evidenceDocument !== "object"
  ) {
    return "invalidEvidenceDocument";
  }
  if (command.action === "clear") {
    if (
      command.supportState !== null
      || command.source !== null
      || command.recorderVersion !== null
      || command.producerVersion !== null
      || command.protocolVersion !== null
      || command.catalogRevision !== null
      || command.expectedSince !== null
      || Object.keys(command.evidenceDocument).length > 0
    ) {
      return "clearFieldsPresent";
    }
    return null;
  }
  if (!command.supportState || !command.source) return "setFieldsMissing";
  if (command.supportState === "supported" && !command.expectedSince) {
    return "expectedSinceRequired";
  }
  if (command.expectedSince && !timestamp(command.expectedSince)) {
    return "invalidExpectedSince";
  }
  return null;
}

function sameCommand(
  event: RecorderObservabilityExpectationEvent,
  command: RecorderObservabilityExpectationCommand,
): boolean {
  return canonicalJSON(commandShape(event)) === canonicalJSON(commandShape(command));
}

function commandShape(command: RecorderObservabilityExpectationCommand) {
  return {
    commandId: command.commandId,
    vrcode: command.vrcode,
    expectedRevision: command.expectedRevision,
    action: command.action,
    supportState: command.supportState,
    source: command.source,
    recorderVersion: command.recorderVersion,
    producerVersion: command.producerVersion,
    protocolVersion: command.protocolVersion,
    catalogRevision: command.catalogRevision,
    expectedSince: normalizedTimestamp(command.expectedSince),
    evidenceDocument: command.evidenceDocument,
    decidedAt: normalizedTimestamp(command.decidedAt),
  };
}

function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJSON).join(",")}]`;
  }
  if (value !== null && typeof value === "object") {
    return `{${Object.entries(value)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, entry]) => `${JSON.stringify(key)}:${canonicalJSON(entry)}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function uuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function timestamp(value: string): boolean {
  return value.trim() !== "" && Number.isFinite(Date.parse(value));
}

function normalizedTimestamp(value: string | null): string | null {
  return value === null ? null : new Date(value).toISOString();
}

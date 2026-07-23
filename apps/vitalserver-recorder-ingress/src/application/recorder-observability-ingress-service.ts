import { createHash, randomUUID } from "crypto";
import type {
  PreparedRecorderObservabilityLine,
  RecorderObservabilityRepositoryPort,
} from "./ports/outbound/recorder-observability-repository-port";
import type { RecorderObservabilitySchemaPort } from "./ports/outbound/recorder-observability-schema-port";
import type { RecorderObservabilityResourceType } from "../domain/recorder-observability";

"use strict";

const canonicalize = require("canonicalize") as (
  value: unknown,
) => string | undefined;

export type RecorderObservabilityInputLine = {
  lineNumber: number;
  rawDocument: string;
  document: unknown;
  parseFailure?: string;
};

export type RecorderObservabilityAdmissionInput = {
  resourceType: RecorderObservabilityResourceType;
  vrcode: string;
  requestDeviceId: string;
  sourceIp: string;
  lines: RecorderObservabilityInputLine[];
};

export type RecorderObservabilityAdmissionResult = {
  state: "admitted";
  requestId: string;
  accepted: number;
  duplicates: number;
  quarantined: number;
};

type RecorderObservabilityClock = {
  now(): string;
};

export function createRecorderObservabilityIngressService({
  repository,
  schemas,
  clock = { now: () => new Date().toISOString() },
  createRequestId = randomUUID,
}: {
  repository: RecorderObservabilityRepositoryPort;
  schemas: RecorderObservabilitySchemaPort;
  clock?: RecorderObservabilityClock;
  createRequestId?: () => string;
}) {
  return {
    async admit(
      input: RecorderObservabilityAdmissionInput,
    ): Promise<RecorderObservabilityAdmissionResult> {
      const requestId = createRequestId();
      const lines = input.lines.map((line) => prepareLine(input, line, schemas));
      const counts = await repository.admit({
        requestId,
        resourceType: input.resourceType,
        vrcode: input.vrcode,
        requestDeviceId: input.requestDeviceId,
        sourceIp: input.sourceIp,
        receivedAt: clock.now(),
        lines,
      });
      return { state: "admitted", requestId, ...counts };
    },
  };
}

function prepareLine(
  input: RecorderObservabilityAdmissionInput,
  line: RecorderObservabilityInputLine,
  schemas: RecorderObservabilitySchemaPort,
): PreparedRecorderObservabilityLine {
  const rawSha256 = sha256(line.rawDocument);
  if (line.parseFailure) {
    return {
      lineNumber: line.lineNumber,
      rawDocument: line.rawDocument,
      rawSha256,
      document: null,
      canonicalSha256: null,
      identity: {},
      contractReceipt: null,
      failureCode: "json_parse_failed",
      failureDetail: line.parseFailure,
    };
  }
  const validation = schemas.validate(
    input.resourceType,
    line.document,
    input.requestDeviceId,
  );
  const document = isObject(line.document) ? line.document : null;
  const canonical = document ? canonicalize(document) : undefined;
  const canonicalSha256 = canonical ? sha256(canonical) : null;
  if (validation.kind === "invalid") {
    return {
      lineNumber: line.lineNumber,
      rawDocument: line.rawDocument,
      rawSha256,
      document,
      canonicalSha256,
      identity: validation.identity,
      contractReceipt: validation.contractReceipt,
      failureCode: validation.reason,
      failureDetail: validation.detail,
    };
  }
  if (
    input.resourceType === "recorderProfile"
    && document
    && isObject(document.identity)
    && document.identity.vrcode !== input.vrcode
  ) {
    return {
      lineNumber: line.lineNumber,
      rawDocument: line.rawDocument,
      rawSha256,
      document,
      canonicalSha256,
      identity: validation.identity,
      contractReceipt: validation.contractReceipt,
      failureCode: "profile_vrcode_mismatch",
      failureDetail:
        `path=${input.vrcode}; profile=${String(document.identity.vrcode)}`,
    };
  }
  if (!canonicalSha256) {
    return {
      lineNumber: line.lineNumber,
      rawDocument: line.rawDocument,
      rawSha256,
      document,
      canonicalSha256: null,
      identity: validation.identity,
      contractReceipt: validation.contractReceipt,
      failureCode: "canonicalization_failed",
      failureDetail: null,
    };
  }
  return {
    lineNumber: line.lineNumber,
    rawDocument: line.rawDocument,
    rawSha256,
    document,
    canonicalSha256,
    identity: validation.identity,
    contractReceipt: validation.contractReceipt,
    failureCode: null,
    failureDetail: null,
  };
}

function isObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

module.exports = { createRecorderObservabilityIngressService };

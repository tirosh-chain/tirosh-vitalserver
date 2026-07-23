import { createHash, randomUUID } from "crypto";
import type {
  RecorderObservabilityLedgerBatch,
  RecorderObservabilityLedgerPort,
  RecorderObservabilityLedgerRecord,
} from "./ports/outbound/recorder-observability-ledger-port";
import {
  validateRecorderObservabilityDocument,
  type RecorderObservabilityResourceType,
} from "../domain/recorder-observability";

"use strict";

export type RecorderObservabilityInputLine = {
  lineNumber: number;
  rawDocument: string;
  document: unknown;
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

type RecorderObservabilityIdentity = {
  contentHash: string;
};

export function createRecorderObservabilityIngressService({
  ledger,
  clock = { now: () => new Date().toISOString() },
  createRequestId = randomUUID,
}: {
  ledger: RecorderObservabilityLedgerPort;
  clock?: RecorderObservabilityClock;
  createRequestId?: () => string;
}) {
  return {
    admit(
      input: RecorderObservabilityAdmissionInput,
    ): RecorderObservabilityAdmissionResult {
      const requestId = createRequestId();
      const receivedAt = clock.now();
      const records: RecorderObservabilityLedgerRecord[] = [];
      const stagedAccepted = new Map<string, RecorderObservabilityIdentity>();
      let accepted = 0;
      let duplicates = 0;
      let quarantined = 0;

      for (const line of input.lines) {
        const contentHash = sha256(line.rawDocument);
        const validation = validateRecorderObservabilityDocument(
          input.resourceType,
          line.document,
          input.requestDeviceId,
        );
        if (validation.kind === "invalid") {
          quarantined += 1;
          records.push(record({
            input,
            line,
            requestId,
            receivedAt,
            contentHash,
            disposition: "quarantined",
            eventId: validation.eventId,
            documentDeviceId: validation.documentDeviceId,
            quarantineReason: validation.reason,
          }));
          continue;
        }

        const { eventId, deviceId } = validation.candidate;
        const key = `${input.vrcode}\u0000${eventId}`;
        const existing = stagedAccepted.get(key)
          || ledger.findAccepted(input.vrcode, eventId);
        if (existing && existing.contentHash === contentHash) {
          duplicates += 1;
          continue;
        }
        if (existing) {
          quarantined += 1;
          records.push(record({
            input,
            line,
            requestId,
            receivedAt,
            contentHash,
            disposition: "quarantined",
            eventId,
            documentDeviceId: deviceId,
            quarantineReason: "event_id_content_conflict",
          }));
          continue;
        }
        accepted += 1;
        stagedAccepted.set(key, { contentHash });
        records.push(record({
          input,
          line,
          requestId,
          receivedAt,
          contentHash,
          disposition: "accepted",
          eventId,
          documentDeviceId: deviceId,
          quarantineReason: null,
        }));
      }

      if (records.length > 0) {
        const batch: RecorderObservabilityLedgerBatch = {
          schemaVersion: 1,
          requestId,
          receivedAt,
          records,
        };
        ledger.persist(batch);
      }
      return {
        state: "admitted",
        requestId,
        accepted,
        duplicates,
        quarantined,
      };
    },
  };
}

function record({
  input,
  line,
  requestId,
  receivedAt,
  contentHash,
  disposition,
  eventId,
  documentDeviceId,
  quarantineReason,
}): RecorderObservabilityLedgerRecord {
  return {
    schemaVersion: 1,
    requestId,
    lineNumber: line.lineNumber,
    disposition,
    resourceType: input.resourceType,
    vrcode: input.vrcode,
    requestDeviceId: input.requestDeviceId,
    documentDeviceId,
    eventId,
    contentHash,
    rawDocument: line.rawDocument,
    receivedAt,
    sourceIp: input.sourceIp,
    quarantineReason,
  };
}

function sha256(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}

module.exports = { createRecorderObservabilityIngressService };

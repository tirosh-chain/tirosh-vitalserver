import type {
  RecorderObservabilityAcceptedIdentity,
  RecorderObservabilityLedgerBatch,
  RecorderObservabilityLedgerPort,
  RecorderObservabilityLedgerRecord,
} from "../../../application/ports/outbound/recorder-observability-ledger-port";

"use strict";

const fs = require("fs");
const path = require("path");

export function createRecorderObservabilityLedger({
  directory,
}: {
  directory: string;
}): RecorderObservabilityLedgerPort {
  requiredString(directory, "directory");
  fs.mkdirSync(directory, { recursive: true });
  const accepted = loadAccepted(directory);
  let writeFailure: unknown = null;

  return {
    findAccepted(
      vrcode: string,
      eventId: string,
    ): RecorderObservabilityAcceptedIdentity | null {
      requireAvailable(writeFailure);
      return accepted.get(identityKey(vrcode, eventId)) || null;
    },

    persist(batch: RecorderObservabilityLedgerBatch): void {
      requireAvailable(writeFailure);
      validateBatch(batch);
      const segmentPath = path.join(
        directory,
        `ledger-${batch.receivedAt.slice(0, 10)}.ndjson`,
      );
      const segmentExisted = fs.existsSync(segmentPath);
      const bytes = Buffer.from(`${JSON.stringify(batch)}\n`, "utf8");
      let descriptor: number | null = null;
      try {
        descriptor = fs.openSync(
          segmentPath,
          fs.constants.O_CREAT | fs.constants.O_APPEND | fs.constants.O_WRONLY,
          0o640,
        );
        const written = fs.writeSync(
          descriptor,
          bytes,
          0,
          bytes.length,
          null,
        );
        if (written !== bytes.length) {
          throw new Error(
            `recorder observability ledger append was partial: ${written}/${bytes.length}`,
          );
        }
        fs.fsyncSync(descriptor);
        fs.closeSync(descriptor);
        descriptor = null;
        if (!segmentExisted) syncDirectory(directory);
      } catch (error) {
        if (descriptor !== null) fs.closeSync(descriptor);
        writeFailure = error;
        throw error;
      }
      for (const record of batch.records) {
        if (record.disposition !== "accepted" || record.eventId === null) continue;
        accepted.set(identityKey(record.vrcode, record.eventId), {
          contentHash: record.contentHash,
        });
      }
    },
  };
}

function loadAccepted(
  directory: string,
): Map<string, RecorderObservabilityAcceptedIdentity> {
  const accepted = new Map<string, RecorderObservabilityAcceptedIdentity>();
  for (const name of fs.readdirSync(directory).sort()) {
    if (!/^ledger-\d{4}-\d{2}-\d{2}\.ndjson$/.test(name)) continue;
    const lines = fs.readFileSync(path.join(directory, name), "utf8").split("\n");
    for (const [index, line] of lines.entries()) {
      if (!line) continue;
      let batch;
      try {
        batch = JSON.parse(line);
        validateBatch(batch);
      } catch (error) {
        throw new TypeError(
          `recorder observability ledger segment is invalid: ${name}:${index + 1}: ${errorMessage(error)}`,
        );
      }
      for (const record of batch.records) {
        if (record.disposition !== "accepted" || record.eventId === null) continue;
        const key = identityKey(record.vrcode, record.eventId);
        const existing = accepted.get(key);
        if (existing && existing.contentHash !== record.contentHash) {
          throw new TypeError(
            `recorder observability ledger has conflicting accepted identity: ${key}`,
          );
        }
        accepted.set(key, { contentHash: record.contentHash });
      }
    }
  }
  return accepted;
}

function validateBatch(
  value: unknown,
): asserts value is RecorderObservabilityLedgerBatch {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new TypeError("recorder observability ledger batch must be an object");
  }
  const batch = value as RecorderObservabilityLedgerBatch;
  if (
    batch.schemaVersion !== 1
    || !validIdentifier(batch.requestId)
    || !validTimestamp(batch.receivedAt)
    || !Array.isArray(batch.records)
    || batch.records.length < 1
  ) {
    throw new TypeError("recorder observability ledger batch is invalid");
  }
  for (const record of batch.records) validateRecord(record, batch);
}

function validateRecord(
  record: RecorderObservabilityLedgerRecord,
  batch: RecorderObservabilityLedgerBatch,
): void {
  if (
    !record
    || record.schemaVersion !== 1
    || record.requestId !== batch.requestId
    || record.receivedAt !== batch.receivedAt
    || !Number.isSafeInteger(record.lineNumber)
    || record.lineNumber < 1
    || !["accepted", "quarantined"].includes(record.disposition)
    || !["observation", "diagnosticEvent", "kernelIncident"].includes(record.resourceType)
    || !validIdentifier(record.vrcode)
    || !validIdentifier(record.requestDeviceId)
    || (record.documentDeviceId !== null && !validIdentifier(record.documentDeviceId))
    || (record.eventId !== null && !validIdentifier(record.eventId))
    || !/^[a-f0-9]{64}$/.test(record.contentHash)
    || typeof record.rawDocument !== "string"
    || !validIdentifier(record.sourceIp)
  ) {
    throw new TypeError("recorder observability ledger record is invalid");
  }
  if (
    record.disposition === "accepted"
    && (record.eventId === null || record.documentDeviceId === null || record.quarantineReason !== null)
  ) {
    throw new TypeError("accepted recorder observability record is invalid");
  }
  if (
    record.disposition === "quarantined"
    && !validIdentifier(record.quarantineReason)
  ) {
    throw new TypeError("quarantined recorder observability record lacks a reason");
  }
}

function syncDirectory(directory: string): void {
  const descriptor = fs.openSync(directory, fs.constants.O_RDONLY);
  try {
    fs.fsyncSync(descriptor);
  } finally {
    fs.closeSync(descriptor);
  }
}

function identityKey(vrcode: string, eventId: string): string {
  return `${vrcode}\u0000${eventId}`;
}

function requireAvailable(writeFailure: unknown): void {
  if (writeFailure) {
    throw new Error(
      `recorder observability ledger is unavailable after a write failure: ${errorMessage(writeFailure)}`,
    );
  }
}

function requiredString(value: unknown, field: string): asserts value is string {
  if (!validIdentifier(value)) {
    throw new TypeError(`${field} must be a non-empty string`);
  }
}

function validIdentifier(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function validTimestamp(value: unknown): value is string {
  return validIdentifier(value) && !Number.isNaN(Date.parse(value));
}

function errorMessage(error: unknown): string {
  return error && typeof error === "object" && "message" in error
    ? String(error.message)
    : String(error);
}

module.exports = { createRecorderObservabilityLedger };

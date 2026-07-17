import { randomUUID } from "node:crypto";
import { mkdir, open, readdir, readFile, rename, stat, unlink } from "node:fs/promises";
import { dirname, join } from "node:path";

import {
  RecorderGatewayIngressDurableStateResourceNotFoundError,
  RecorderGatewayIngressDurableStateRevisionConflictError,
  type RecorderGatewayIngressDurableStateStore,
} from "../../recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-ports.js";
import type {
  RecorderColdPathCapture,
  RecorderColdPathCapturedPacket,
  RecorderColdPathCaptureFinalizationReceipt,
  RecorderColdPathCaptureUsage,
  RecorderGatewayDeliveryReplayUsage,
  RecorderGatewayIngressDurableRecord,
  RecorderGatewayDeliveryReplayState,
  RecorderIngressReceipt,
  VitalServerDeliveryReceipt,
} from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";
import { isRecorderGatewayIdentifier, recorderGatewaySchemaVersion } from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";
import type { RecorderGatewayDeliveryReplayClaimSettlement } from "../../recordergatewaydomain/recorder-gateway-vital-server-delivery-replay-policy.js";

export class RecorderGatewayIngressDurableStateStoreError extends Error {
  public override readonly cause?: unknown;

  public constructor(message: string, cause?: unknown) {
    super(message);
    this.name = "RecorderGatewayIngressDurableStateStoreError";
    this.cause = cause;
  }
}

// FileRecorderGatewayIngressDurableStateStore keeps one atomically replaced
// durable record per accepted packet. The record contains a delivery-replay
// payload and an independent cold-path packet capture payload, so one
// successful VitalServer acknowledgement cannot erase the archive source.
// Cold-path capture aggregates are separate atomically replaced files because
// their lifecycle is independent from individual packet delivery replay.
export class FileRecorderGatewayIngressDurableStateStore implements RecorderGatewayIngressDurableStateStore {
  private readonly ingressDurableRecordsDirectory: string;
  private readonly vitalServerDeliveryReceiptsDirectory: string;
  private readonly recorderColdPathCapturesDirectory: string;

  public constructor(stateDirectory: string) {
    // Retain the historic ingress-records directory name as an explicit
    // on-disk compatibility boundary. Older delivery-only records decode as
    // records without coldPathPacketCapture; they remain replayable but can
    // never be promoted to a newly invented cold-path source.
    this.ingressDurableRecordsDirectory = join(stateDirectory, "ingress-records");
    this.vitalServerDeliveryReceiptsDirectory = join(stateDirectory, "delivery-receipts");
    this.recorderColdPathCapturesDirectory = join(stateDirectory, "recorder-cold-path-captures");
  }

  public async initializeRecorderGatewayIngressDurableState(): Promise<void> {
    try {
      await mkdir(this.ingressDurableRecordsDirectory, { recursive: true, mode: 0o700 });
      await mkdir(this.vitalServerDeliveryReceiptsDirectory, { recursive: true, mode: 0o700 });
      await mkdir(this.recorderColdPathCapturesDirectory, { recursive: true, mode: 0o700 });
      await this.migrateLegacyDeliveryOnlyRecorderGatewayIngressDurableRecords();
    } catch (error) {
      throw new RecorderGatewayIngressDurableStateStoreError("could not initialize Recorder Gateway ingress durable state directories", error);
    }
  }

  public async readRecorderGatewayDeliveryReplayUsage(): Promise<RecorderGatewayDeliveryReplayUsage> {
    const records = await this.allRecorderGatewayIngressDurableRecords();
    return records.reduce<RecorderGatewayDeliveryReplayUsage>(
      (usage, record) => {
        if (record.deliveryReplay.state === "pending" || record.deliveryReplay.state === "delivering") {
          usage.pendingItems += 1;
          usage.pendingBytes += record.receipt.packet.byteCount;
        }
        return usage;
      },
      { pendingItems: 0, pendingBytes: 0 },
    );
  }

  public async readRecorderColdPathCaptureUsage(): Promise<RecorderColdPathCaptureUsage> {
    const records = await this.allRecorderGatewayIngressDurableRecords();
    return records.reduce<RecorderColdPathCaptureUsage>(
      (usage, record) => {
        if (record.coldPathPacketCapture !== undefined) {
          usage.retainedPacketCount += 1;
          usage.retainedPayloadBytes += record.receipt.packet.byteCount;
        }
        return usage;
      },
      { retainedPacketCount: 0, retainedPayloadBytes: 0 },
    );
  }

  public async persistAcceptedRecorderGatewayIngressDurableRecord(record: RecorderGatewayIngressDurableRecord): Promise<void> {
    validateRecorderGatewayIngressDurableRecord(record);
    const recordPath = this.recorderGatewayIngressDurableRecordPath(record.receipt.id);
    try {
      await stat(recordPath);
      throw new RecorderGatewayIngressDurableStateStoreError("ingress receipt identifier already exists");
    } catch (error) {
      if (error instanceof RecorderGatewayIngressDurableStateStoreError) {
        throw error;
      }
      if (!isNotFound(error)) {
        throw new RecorderGatewayIngressDurableStateStoreError("could not check ingress receipt ownership", error);
      }
    }
    await this.writeJsonAtomically(recordPath, record);
  }

  public async readRecorderIngressReceipt(receiptId: string): Promise<RecorderIngressReceipt> {
    if (!isRecorderGatewayIdentifier(receiptId)) {
      throw new RecorderGatewayIngressDurableStateResourceNotFoundError("invalid ingress receipt id");
    }
    const record = await this.readRecorderGatewayIngressDurableRecord(receiptId);
    return record.receipt;
  }

  public async readVitalServerDeliveryReceipt(receiptId: string): Promise<VitalServerDeliveryReceipt> {
    if (!isRecorderGatewayIdentifier(receiptId)) {
      throw new RecorderGatewayIngressDurableStateResourceNotFoundError("invalid VitalServer delivery receipt id");
    }
    const receipt = await this.readJson(this.vitalServerDeliveryReceiptPath(receiptId), "VitalServer delivery receipt");
    validateVitalServerDeliveryReceipt(receipt);
    return receipt;
  }

  public async listExpiredRecorderGatewayDeliveryReplayClaims(now: Date): Promise<RecorderGatewayIngressDurableRecord[]> {
    const records = await this.allRecorderGatewayIngressDurableRecords();
    return records.filter((record) => {
      if (record.deliveryReplay.state !== "delivering") {
        return false;
      }
      if (record.deliveryReplay.leaseExpiresAt === undefined) {
        throw new RecorderGatewayIngressDurableStateStoreError("delivering Recorder Gateway delivery replay has no lease expiry");
      }
      const expiry = new Date(record.deliveryReplay.leaseExpiresAt);
      if (Number.isNaN(expiry.getTime())) {
        throw new RecorderGatewayIngressDurableStateStoreError("delivering Recorder Gateway delivery replay has an invalid lease expiry");
      }
      return expiry.getTime() <= now.getTime();
    });
  }

  public async findVitalServerDeliveryReceiptForAttempt(deliveryRequestId: string, attempt: number): Promise<VitalServerDeliveryReceipt | undefined> {
    if (!isRecorderGatewayIdentifier(deliveryRequestId) || attempt < 1) {
      throw new RecorderGatewayIngressDurableStateStoreError("VitalServer delivery receipt lookup requires a valid request id and positive attempt");
    }
    const matches: VitalServerDeliveryReceipt[] = [];
    for (const filename of await this.jsonFiles(this.vitalServerDeliveryReceiptsDirectory)) {
      const candidate = await this.readJson(join(this.vitalServerDeliveryReceiptsDirectory, filename), "VitalServer delivery receipt");
      validateVitalServerDeliveryReceipt(candidate);
      if (candidate.deliveryRequestId === deliveryRequestId && candidate.attempt === attempt) {
        matches.push(candidate);
      }
    }
    if (matches.length > 1) {
      throw new RecorderGatewayIngressDurableStateStoreError("more than one VitalServer delivery receipt exists for one logical delivery attempt");
    }
    return matches[0];
  }

  public async claimNextDueRecorderGatewayDeliveryReplayRecord(now: Date, leaseExpiresAt: Date): Promise<RecorderGatewayIngressDurableRecord | undefined> {
    const records = await this.allRecorderGatewayIngressDurableRecords();
    const candidate = records
      .filter((record) => record.deliveryReplay.state === "pending" && isRecorderGatewayDeliveryReplayDue(record.deliveryReplay.nextAttemptAt, now))
      .sort((left, right) => left.receipt.recordedAt.localeCompare(right.receipt.recordedAt))[0];
    if (candidate === undefined) {
      return undefined;
    }
    const claimed: RecorderGatewayIngressDurableRecord = {
      ...candidate,
      deliveryReplay: {
        ...candidate.deliveryReplay,
        attempt: candidate.deliveryReplay.attempt + 1,
        state: "delivering",
        nextAttemptAt: undefined,
        leaseExpiresAt: leaseExpiresAt.toISOString(),
      },
    };
    await this.writeRecorderGatewayIngressDurableRecord(claimed);
    return claimed;
  }

  public async persistVitalServerDeliveryReceipt(receipt: VitalServerDeliveryReceipt): Promise<void> {
    validateVitalServerDeliveryReceipt(receipt);
    const receiptPath = this.vitalServerDeliveryReceiptPath(receipt.id);
    try {
      await stat(receiptPath);
      throw new RecorderGatewayIngressDurableStateStoreError("VitalServer delivery receipt identifier already exists");
    } catch (error) {
      if (error instanceof RecorderGatewayIngressDurableStateStoreError) {
        throw error;
      }
      if (!isNotFound(error)) {
        throw new RecorderGatewayIngressDurableStateStoreError("could not check VitalServer delivery receipt ownership", error);
      }
    }
    await this.writeJsonAtomically(receiptPath, receipt);
  }

  public async settleRecorderGatewayDeliveryReplayClaim(receiptId: string, attempt: number, settlement: RecorderGatewayDeliveryReplayClaimSettlement): Promise<void> {
    const current = await this.readRecorderGatewayIngressDurableRecord(receiptId);
    if (current.deliveryReplay.state !== "delivering" || current.deliveryReplay.attempt !== attempt) {
      throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway delivery replay claim changed before its delivery outcome could be persisted");
    }
    const settled: RecorderGatewayIngressDurableRecord = {
      ...current,
      deliveryReplay: {
        ...current.deliveryReplay,
        state: settlement.state,
        nextAttemptAt: settlement.nextAttemptAt,
        leaseExpiresAt: undefined,
      },
    };
    if (settlement.clearReplayPayload) {
      // Never touch coldPathPacketCapture here. Delivery success and archive
      // source retention are intentionally separate lifecycle facts.
      settled.deliveryReplay.payloadBase64 = undefined;
      settled.deliveryReplay.payloadEncoding = undefined;
    }
    validateRecorderGatewayIngressDurableRecord(settled);
    await this.writeRecorderGatewayIngressDurableRecord(settled);
  }

  public async createRecorderColdPathCapture(capture: RecorderColdPathCapture): Promise<void> {
    validateRecorderColdPathCapture(capture);
    if (capture.state !== "capturing" || capture.resourceRevision !== 1 || capture.finalizationReceipt !== undefined) {
      throw new RecorderGatewayIngressDurableStateStoreError("a new Recorder Cold-Path Capture must begin at capturing revision one");
    }
    const capturePath = this.recorderColdPathCapturePath(capture.id);
    try {
      await stat(capturePath);
      throw new RecorderGatewayIngressDurableStateStoreError("Recorder Cold-Path Capture identifier already exists");
    } catch (error) {
      if (error instanceof RecorderGatewayIngressDurableStateStoreError) {
        throw error;
      }
      if (!isNotFound(error)) {
        throw new RecorderGatewayIngressDurableStateStoreError("could not check Recorder Cold-Path Capture ownership", error);
      }
    }
    await this.writeJsonAtomically(capturePath, capture);
  }

  public async readRecorderColdPathCapture(captureId: string): Promise<RecorderColdPathCapture> {
    if (!isRecorderGatewayIdentifier(captureId)) {
      throw new RecorderGatewayIngressDurableStateResourceNotFoundError("invalid Recorder Cold-Path Capture id");
    }
    const capture = await this.readJson(this.recorderColdPathCapturePath(captureId), "Recorder Cold-Path Capture");
    validateRecorderColdPathCapture(capture);
    return capture;
  }

  public async readRecorderColdPathCaptureFinalizationReceipt(receiptId: string): Promise<RecorderColdPathCaptureFinalizationReceipt> {
    if (!isRecorderGatewayIdentifier(receiptId)) {
      throw new RecorderGatewayIngressDurableStateResourceNotFoundError("invalid Recorder Cold-Path Capture finalization receipt id");
    }
    const receipt = await this.findRecorderColdPathCaptureFinalizationReceipt((candidate) => candidate.id === receiptId);
    if (receipt === undefined) {
      throw new RecorderGatewayIngressDurableStateResourceNotFoundError("Recorder Cold-Path Capture finalization receipt does not exist");
    }
    return receipt;
  }

  public async findRecorderColdPathCaptureFinalizationReceiptByRequestId(requestId: string): Promise<RecorderColdPathCaptureFinalizationReceipt | undefined> {
    if (!isRecorderGatewayIdentifier(requestId)) {
      throw new RecorderGatewayIngressDurableStateStoreError("Recorder Cold-Path Capture finalization request id is invalid");
    }
    return this.findRecorderColdPathCaptureFinalizationReceipt((candidate) => candidate.requestId === requestId);
  }

  public async readRecorderColdPathCapturedPackets(captureId: string): Promise<RecorderColdPathCapturedPacket[]> {
    if (!isRecorderGatewayIdentifier(captureId)) {
      throw new RecorderGatewayIngressDurableStateResourceNotFoundError("invalid Recorder Cold-Path Capture id");
    }
    // Require the capture aggregate itself to exist. A packet record that has
    // an unknown capture reference is corrupted state rather than a new source.
    await this.readRecorderColdPathCapture(captureId);
    const capturedPackets: RecorderColdPathCapturedPacket[] = [];
    for (const record of await this.allRecorderGatewayIngressDurableRecords()) {
      const capture = record.coldPathPacketCapture;
      if (capture === undefined || capture.captureReference.resourceId !== captureId) {
        continue;
      }
      capturedPackets.push({
        ingressReceiptReference: { resourceType: "ingress-receipt", resourceId: record.receipt.id },
        packet: record.receipt.packet,
        payloadEncoding: capture.payloadEncoding,
        payloadBase64: capture.payloadBase64,
      });
    }
    return capturedPackets.sort((left, right) => {
      const receivedAtComparison = left.packet.receivedAt.localeCompare(right.packet.receivedAt);
      return receivedAtComparison === 0
        ? left.ingressReceiptReference.resourceId.localeCompare(right.ingressReceiptReference.resourceId)
        : receivedAtComparison;
    });
  }

  public async commitRecorderColdPathCaptureFinalization(
    captureId: string,
    expectedCaptureRevision: number,
    receipt: RecorderColdPathCaptureFinalizationReceipt,
  ): Promise<void> {
    const current = await this.readRecorderColdPathCapture(captureId);
    if (current.state !== "capturing" || current.resourceRevision !== expectedCaptureRevision) {
      throw new RecorderGatewayIngressDurableStateRevisionConflictError("Recorder Cold-Path Capture changed before finalization commit");
    }
    validateRecorderColdPathCaptureFinalizationReceipt(receipt);
    if (
      receipt.captureReference.resourceId !== current.id ||
      receipt.recorderId !== current.recorderId ||
      receipt.connection.sessionId !== current.connection.sessionId ||
      receipt.expectedCaptureRevision !== expectedCaptureRevision ||
      receipt.finalizedCaptureRevision !== expectedCaptureRevision + 1
    ) {
      throw new RecorderGatewayIngressDurableStateStoreError("Recorder Cold-Path Capture finalization receipt does not describe the current capture");
    }
    const finalized: RecorderColdPathCapture = {
      ...current,
      resourceRevision: expectedCaptureRevision + 1,
      state: "finalized",
      finalizationReceipt: receipt,
    };
    validateRecorderColdPathCapture(finalized);
    await this.writeJsonAtomically(this.recorderColdPathCapturePath(captureId), finalized);
  }

  private async allRecorderGatewayIngressDurableRecords(): Promise<RecorderGatewayIngressDurableRecord[]> {
    const records: RecorderGatewayIngressDurableRecord[] = [];
    for (const filename of await this.jsonFiles(this.ingressDurableRecordsDirectory)) {
      const value = await this.readJson(join(this.ingressDurableRecordsDirectory, filename), "Recorder Gateway ingress durable record");
      validateRecorderGatewayIngressDurableRecord(value);
      records.push(value);
    }
    return records;
  }

  // This is an explicit one-way migration, not a read fallback. Before the
  // cold-path boundary existed, the same ingress-records directory held a
  // delivery-only replay record. The old record can preserve an outstanding
  // VitalServer replay obligation, but it cannot be upgraded into a captured
  // archive source because no old state proves that source existed.
  //
  // A crash during migration is safe to retry: each file is atomically either
  // the validated legacy shape or the validated current shape. Any unknown
  // shape stops initialization instead of being treated as an empty queue.
  private async migrateLegacyDeliveryOnlyRecorderGatewayIngressDurableRecords(): Promise<void> {
    for (const filename of await this.jsonFiles(this.ingressDurableRecordsDirectory)) {
      const recordPath = join(this.ingressDurableRecordsDirectory, filename);
      const encodedRecord = await this.readJson(recordPath, "Recorder Gateway ingress durable record");
      if (isCurrentRecorderGatewayIngressDurableRecord(encodedRecord)) {
        validateRecorderGatewayIngressDurableRecord(encodedRecord);
        continue;
      }
      const migratedRecord = migrateLegacyDeliveryOnlyRecorderGatewayIngressDurableRecord(encodedRecord);
      await this.writeJsonAtomically(recordPath, migratedRecord);
    }
  }

  private async readRecorderGatewayIngressDurableRecord(receiptId: string): Promise<RecorderGatewayIngressDurableRecord> {
    const value = await this.readJson(this.recorderGatewayIngressDurableRecordPath(receiptId), "Recorder Gateway ingress durable record");
    validateRecorderGatewayIngressDurableRecord(value);
    return value;
  }

  private async writeRecorderGatewayIngressDurableRecord(record: RecorderGatewayIngressDurableRecord): Promise<void> {
    validateRecorderGatewayIngressDurableRecord(record);
    await this.writeJsonAtomically(this.recorderGatewayIngressDurableRecordPath(record.receipt.id), record);
  }

  private async findRecorderColdPathCaptureFinalizationReceipt(
    predicate: (receipt: RecorderColdPathCaptureFinalizationReceipt) => boolean,
  ): Promise<RecorderColdPathCaptureFinalizationReceipt | undefined> {
    const matches: RecorderColdPathCaptureFinalizationReceipt[] = [];
    for (const filename of await this.jsonFiles(this.recorderColdPathCapturesDirectory)) {
      const value = await this.readJson(join(this.recorderColdPathCapturesDirectory, filename), "Recorder Cold-Path Capture");
      validateRecorderColdPathCapture(value);
      const receipt = value.finalizationReceipt;
      if (receipt !== undefined && predicate(receipt)) {
        matches.push(receipt);
      }
    }
    if (matches.length > 1) {
      throw new RecorderGatewayIngressDurableStateStoreError("more than one Recorder Cold-Path Capture finalization receipt matches one identity");
    }
    return matches[0];
  }

  private recorderGatewayIngressDurableRecordPath(receiptId: string): string {
    return join(this.ingressDurableRecordsDirectory, `${receiptId}.json`);
  }

  private vitalServerDeliveryReceiptPath(receiptId: string): string {
    return join(this.vitalServerDeliveryReceiptsDirectory, `${receiptId}.json`);
  }

  private recorderColdPathCapturePath(captureId: string): string {
    return join(this.recorderColdPathCapturesDirectory, `${captureId}.json`);
  }

  private async jsonFiles(directory: string): Promise<string[]> {
    let entries;
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch (error) {
      throw new RecorderGatewayIngressDurableStateStoreError("could not enumerate the Recorder Gateway durable state directory", error);
    }
    const names: string[] = [];
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith(".json")) {
        throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway durable state directory contains an incomplete or unsupported entry");
      }
      names.push(entry.name);
    }
    return names.sort();
  }

  private async readJson(path: string, label: string): Promise<unknown> {
    let encoded: string;
    try {
      encoded = await readFile(path, "utf8");
    } catch (error) {
      if (isNotFound(error)) {
        throw new RecorderGatewayIngressDurableStateResourceNotFoundError(`${label} does not exist`);
      }
      throw new RecorderGatewayIngressDurableStateStoreError(`could not read ${label}`, error);
    }
    try {
      return JSON.parse(encoded) as unknown;
    } catch (error) {
      throw new RecorderGatewayIngressDurableStateStoreError(`could not decode ${label}`, error);
    }
  }

  private async writeJsonAtomically(path: string, value: unknown): Promise<void> {
    const temporaryPath = `${path}.tmp-${randomUUID()}`;
    let handle: Awaited<ReturnType<typeof open>> | undefined;
    try {
      await mkdir(dirname(path), { recursive: true, mode: 0o700 });
      handle = await open(temporaryPath, "wx", 0o600);
      await handle.writeFile(`${JSON.stringify(value)}\n`, "utf8");
      await handle.sync();
      await handle.close();
      handle = undefined;
      await rename(temporaryPath, path);
    } catch (error) {
      try {
        if (handle !== undefined) {
          await handle.close();
        }
      } catch {
        // The original state write failure is the actionable result.
      }
      try {
        await unlink(temporaryPath);
      } catch (cleanupError) {
        if (!isNotFound(cleanupError)) {
          throw new RecorderGatewayIngressDurableStateStoreError("could not clean up an incomplete Recorder Gateway durable state write", cleanupError);
        }
      }
      throw new RecorderGatewayIngressDurableStateStoreError("could not atomically persist Recorder Gateway durable state", error);
    }
  }
}

function isNotFound(error: unknown): boolean {
  return typeof error === "object" && error !== null && "code" in error && (error as { code?: string }).code === "ENOENT";
}

function isRecorderGatewayDeliveryReplayDue(nextAttemptAt: string | undefined, now: Date): boolean {
  if (nextAttemptAt === undefined) {
    return true;
  }
  const parsed = new Date(nextAttemptAt);
  if (Number.isNaN(parsed.getTime())) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway delivery replay contains an invalid next attempt timestamp");
  }
  return parsed.getTime() <= now.getTime();
}

interface LegacyDeliveryOnlyRecorderGatewayIngressDurableRecord {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  receipt: unknown;
  payloadBase64?: string;
  payloadEncoding?: "binary" | "binary-string";
  attempt: number;
  state: RecorderGatewayDeliveryReplayState;
  nextAttemptAt?: string;
  leaseExpiresAt?: string;
}

interface LegacyRecorderIngressReceiptWithSpoolHandoff {
  schemaVersion: typeof recorderGatewaySchemaVersion;
  id: string;
  requestId: string;
  recorderId: string;
  connection: RecorderIngressReceipt["connection"];
  packet: RecorderIngressReceipt["packet"];
  ingressState: "accepted";
  spoolHandoff: {
    state: "stored";
    spoolReceiptId: string;
    persistedAt: string;
  };
  delivery: RecorderIngressReceipt["delivery"];
  recordedAt: string;
}

function isCurrentRecorderGatewayIngressDurableRecord(value: unknown): value is RecorderGatewayIngressDurableRecord {
  return typeof value === "object" && value !== null && "deliveryReplay" in value;
}

function migrateLegacyDeliveryOnlyRecorderGatewayIngressDurableRecord(value: unknown): RecorderGatewayIngressDurableRecord {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new RecorderGatewayIngressDurableStateStoreError("legacy Recorder Gateway ingress durable record must be an object");
  }
  const legacy = value as Partial<LegacyDeliveryOnlyRecorderGatewayIngressDurableRecord>;
  const allowedLegacyFields = new Set([
    "schemaVersion",
    "receipt",
    "payloadBase64",
    "payloadEncoding",
    "attempt",
    "state",
    "nextAttemptAt",
    "leaseExpiresAt",
  ]);
  for (const fieldName of Object.keys(legacy)) {
    if (!allowedLegacyFields.has(fieldName)) {
      throw new RecorderGatewayIngressDurableStateStoreError("legacy Recorder Gateway ingress durable record contains an unsupported field");
    }
  }
  if (
    legacy.schemaVersion !== recorderGatewaySchemaVersion ||
    legacy.receipt === undefined ||
    !Number.isInteger(legacy.attempt) ||
    (legacy.attempt ?? -1) < 0 ||
    !isRecorderGatewayDeliveryReplayState(legacy.state) ||
    (legacy.payloadBase64 !== undefined && typeof legacy.payloadBase64 !== "string") ||
    (legacy.payloadEncoding !== undefined && legacy.payloadEncoding !== "binary" && legacy.payloadEncoding !== "binary-string") ||
    (legacy.nextAttemptAt !== undefined && typeof legacy.nextAttemptAt !== "string") ||
    (legacy.leaseExpiresAt !== undefined && typeof legacy.leaseExpiresAt !== "string")
  ) {
    throw new RecorderGatewayIngressDurableStateStoreError("legacy Recorder Gateway ingress durable record is not eligible for explicit delivery replay migration");
  }
  const migratedReceipt = migrateLegacyRecorderIngressReceipt(legacy.receipt);
  const migratedRecord: RecorderGatewayIngressDurableRecord = {
    schemaVersion: recorderGatewaySchemaVersion,
    receipt: migratedReceipt,
    deliveryReplay: {
      payloadBase64: legacy.payloadBase64,
      payloadEncoding: legacy.payloadEncoding,
      attempt: legacy.attempt!,
      state: legacy.state,
      nextAttemptAt: legacy.nextAttemptAt,
      leaseExpiresAt: legacy.leaseExpiresAt,
    },
  };
  validateRecorderGatewayIngressDurableRecord(migratedRecord);
  return migratedRecord;
}

function migrateLegacyRecorderIngressReceipt(value: unknown): RecorderIngressReceipt {
  if (isCurrentRecorderIngressReceipt(value)) {
    validateRecorderIngressReceipt(value);
    if (value.coldPathCapture !== undefined) {
      throw new RecorderGatewayIngressDurableStateStoreError("legacy delivery-only Recorder Gateway ingress record cannot claim a cold-path capture");
    }
    return value;
  }
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new RecorderGatewayIngressDurableStateStoreError("legacy Recorder Gateway ingress receipt must be an object");
  }
  const legacyReceipt = value as Partial<LegacyRecorderIngressReceiptWithSpoolHandoff>;
  const allowedLegacyReceiptFields = new Set([
    "schemaVersion",
    "id",
    "requestId",
    "recorderId",
    "connection",
    "packet",
    "ingressState",
    "spoolHandoff",
    "delivery",
    "recordedAt",
  ]);
  for (const fieldName of Object.keys(legacyReceipt)) {
    if (!allowedLegacyReceiptFields.has(fieldName)) {
      throw new RecorderGatewayIngressDurableStateStoreError("legacy Recorder Gateway ingress receipt contains an unsupported field");
    }
  }
  if (
    legacyReceipt.schemaVersion !== recorderGatewaySchemaVersion ||
    !isRecorderGatewayIdentifier(legacyReceipt.id ?? "") ||
    !isRecorderGatewayIdentifier(legacyReceipt.requestId ?? "") ||
    !isRecorderGatewayIdentifier(legacyReceipt.recorderId ?? "") ||
    legacyReceipt.connection === undefined ||
    legacyReceipt.packet === undefined ||
    legacyReceipt.ingressState !== "accepted" ||
    legacyReceipt.spoolHandoff === undefined ||
    legacyReceipt.spoolHandoff.state !== "stored" ||
    !isRecorderGatewayIdentifier(legacyReceipt.spoolHandoff.spoolReceiptId) ||
    legacyReceipt.spoolHandoff.persistedAt === "" ||
    legacyReceipt.delivery === undefined ||
    legacyReceipt.recordedAt === ""
  ) {
    throw new RecorderGatewayIngressDurableStateStoreError("legacy Recorder Gateway ingress receipt is not eligible for explicit durable-ingress-state handoff migration");
  }
  const migratedReceipt: RecorderIngressReceipt = {
    schemaVersion: recorderGatewaySchemaVersion,
    id: legacyReceipt.id!,
    requestId: legacyReceipt.requestId!,
    recorderId: legacyReceipt.recorderId!,
    connection: legacyReceipt.connection,
    packet: legacyReceipt.packet,
    ingressState: "accepted",
    durableIngressStateHandoff: {
      state: "stored",
      durableIngressStateReceiptId: legacyReceipt.spoolHandoff.spoolReceiptId,
      persistedAt: legacyReceipt.spoolHandoff.persistedAt,
    },
    delivery: legacyReceipt.delivery,
    recordedAt: legacyReceipt.recordedAt!,
  };
  validateRecorderIngressReceipt(migratedReceipt);
  return migratedReceipt;
}

function isCurrentRecorderIngressReceipt(value: unknown): value is RecorderIngressReceipt {
  return typeof value === "object" && value !== null && "durableIngressStateHandoff" in value;
}

function validateRecorderGatewayIngressDurableRecord(value: unknown): asserts value is RecorderGatewayIngressDurableRecord {
  if (typeof value !== "object" || value === null) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway ingress durable record must be an object");
  }
  const record = value as Partial<RecorderGatewayIngressDurableRecord>;
  if (record.schemaVersion !== recorderGatewaySchemaVersion || record.receipt === undefined || !isRecorderGatewayIdentifier(record.receipt.id)) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway ingress durable record has an invalid receipt identity");
  }
  validateRecorderIngressReceipt(record.receipt);
  if (record.deliveryReplay === undefined) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway ingress durable record has no delivery replay state");
  }
  const replay = record.deliveryReplay;
  if (!Number.isInteger(replay.attempt) || replay.attempt < 0 || !isRecorderGatewayDeliveryReplayState(replay.state)) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway delivery replay has invalid state");
  }
  if ((replay.state === "pending" || replay.state === "delivering") && (typeof replay.payloadBase64 !== "string" || replay.payloadEncoding === undefined)) {
    throw new RecorderGatewayIngressDurableStateStoreError("active Recorder Gateway delivery replay has no payload");
  }
  if (replay.payloadEncoding !== undefined && replay.payloadEncoding !== "binary" && replay.payloadEncoding !== "binary-string") {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway delivery replay has an invalid payload encoding");
  }
  if (replay.state === "delivering" && replay.leaseExpiresAt === undefined) {
    throw new RecorderGatewayIngressDurableStateStoreError("delivering Recorder Gateway delivery replay has no lease");
  }
  if (record.coldPathPacketCapture !== undefined) {
    const coldPathCapture = record.coldPathPacketCapture;
    if (
      coldPathCapture.captureReference.resourceType !== "recorder-cold-path-capture" ||
      !isRecorderGatewayIdentifier(coldPathCapture.captureReference.resourceId) ||
      typeof coldPathCapture.payloadBase64 !== "string" ||
      (coldPathCapture.payloadEncoding !== "binary" && coldPathCapture.payloadEncoding !== "binary-string") ||
      coldPathCapture.capturedAt === ""
    ) {
      throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway cold-path packet capture is invalid");
    }
    if (
      record.receipt.coldPathCapture === undefined ||
      record.receipt.coldPathCapture.captureReference.resourceId !== coldPathCapture.captureReference.resourceId ||
      record.receipt.coldPathCapture.persistedAt !== coldPathCapture.capturedAt
    ) {
      throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway cold-path packet capture does not match the public ingress receipt");
    }
  } else if (record.receipt.coldPathCapture !== undefined) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway ingress receipt claims cold-path capture without private retained payload");
  }
}

function validateRecorderIngressReceipt(receipt: RecorderIngressReceipt): void {
  if (
    receipt.schemaVersion !== recorderGatewaySchemaVersion ||
    !isRecorderGatewayIdentifier(receipt.id) ||
    !isRecorderGatewayIdentifier(receipt.requestId) ||
    !isRecorderGatewayIdentifier(receipt.recorderId) ||
    !isRecorderGatewayIdentifier(receipt.connection.sessionId) ||
    receipt.connection.protocolVersion !== "v2" ||
    !isRecorderGatewayIdentifier(receipt.packet.packetId) ||
    receipt.packet.byteCount < 0 ||
    receipt.packet.parseState !== "accepted" ||
    receipt.ingressState !== "accepted" ||
    receipt.durableIngressStateHandoff.state !== "stored" ||
    !isRecorderGatewayIdentifier(receipt.durableIngressStateHandoff.durableIngressStateReceiptId) ||
    receipt.durableIngressStateHandoff.persistedAt === "" ||
    receipt.delivery.state !== "requested" ||
    !isRecorderGatewayIdentifier(receipt.delivery.requestId) ||
    receipt.recordedAt === ""
  ) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway ingress receipt has invalid required fields");
  }
  if (
    receipt.coldPathCapture !== undefined &&
    (receipt.coldPathCapture.state !== "captured" ||
      receipt.coldPathCapture.captureReference.resourceType !== "recorder-cold-path-capture" ||
      !isRecorderGatewayIdentifier(receipt.coldPathCapture.captureReference.resourceId) ||
      receipt.coldPathCapture.persistedAt === "")
  ) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Gateway ingress receipt has invalid cold-path capture evidence");
  }
}

function validateVitalServerDeliveryReceipt(value: unknown): asserts value is VitalServerDeliveryReceipt {
  if (typeof value !== "object" || value === null) {
    throw new RecorderGatewayIngressDurableStateStoreError("VitalServer delivery receipt must be an object");
  }
  const receipt = value as Partial<VitalServerDeliveryReceipt>;
  if (
    receipt.schemaVersion !== recorderGatewaySchemaVersion ||
    !isRecorderGatewayIdentifier(receipt.id ?? "") ||
    !isRecorderGatewayIdentifier(receipt.deliveryRequestId ?? "") ||
    !Number.isInteger(receipt.attempt) ||
    (receipt.attempt ?? 0) < 1 ||
    receipt.outcome === undefined ||
    receipt.retry === undefined
  ) {
    throw new RecorderGatewayIngressDurableStateStoreError("VitalServer delivery receipt has invalid required fields");
  }
}

function validateRecorderColdPathCapture(value: unknown): asserts value is RecorderColdPathCapture {
  if (typeof value !== "object" || value === null) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Cold-Path Capture must be an object");
  }
  const capture = value as Partial<RecorderColdPathCapture>;
  if (
    capture.schemaVersion !== recorderGatewaySchemaVersion ||
    !isRecorderGatewayIdentifier(capture.id ?? "") ||
    !isRecorderGatewayIdentifier(capture.recorderId ?? "") ||
    capture.connection === undefined ||
    !isRecorderGatewayIdentifier(capture.connection.sessionId) ||
    capture.connection.protocolVersion !== "v2" ||
    !Number.isInteger(capture.resourceRevision) ||
    (capture.resourceRevision ?? 0) < 1 ||
    (capture.state !== "capturing" && capture.state !== "finalized") ||
    capture.openedAt === ""
  ) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Cold-Path Capture has invalid required fields");
  }
  if (capture.state === "capturing" && capture.finalizationReceipt !== undefined) {
    throw new RecorderGatewayIngressDurableStateStoreError("capturing Recorder Cold-Path Capture cannot have finalization evidence");
  }
  if (capture.state === "finalized") {
    if (capture.finalizationReceipt === undefined) {
      throw new RecorderGatewayIngressDurableStateStoreError("finalized Recorder Cold-Path Capture has no finalization receipt");
    }
    validateRecorderColdPathCaptureFinalizationReceipt(capture.finalizationReceipt);
    if (
      capture.finalizationReceipt.captureReference.resourceId !== capture.id ||
      capture.finalizationReceipt.recorderId !== capture.recorderId ||
      capture.finalizationReceipt.connection.sessionId !== capture.connection.sessionId ||
      capture.finalizationReceipt.finalizedCaptureRevision !== capture.resourceRevision
    ) {
      throw new RecorderGatewayIngressDurableStateStoreError("Recorder Cold-Path Capture finalization receipt does not match its capture aggregate");
    }
  }
}

function validateRecorderColdPathCaptureFinalizationReceipt(value: unknown): asserts value is RecorderColdPathCaptureFinalizationReceipt {
  if (typeof value !== "object" || value === null) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Cold-Path Capture finalization receipt must be an object");
  }
  const receipt = value as Partial<RecorderColdPathCaptureFinalizationReceipt>;
  if (
    receipt.schemaVersion !== recorderGatewaySchemaVersion ||
    !isRecorderGatewayIdentifier(receipt.id ?? "") ||
    !isRecorderGatewayIdentifier(receipt.requestId ?? "") ||
    receipt.captureReference?.resourceType !== "recorder-cold-path-capture" ||
    !isRecorderGatewayIdentifier(receipt.captureReference.resourceId) ||
    !isRecorderGatewayIdentifier(receipt.recorderId ?? "") ||
    receipt.connection === undefined ||
    !isRecorderGatewayIdentifier(receipt.connection.sessionId) ||
    receipt.connection.protocolVersion !== "v2" ||
    !Number.isInteger(receipt.expectedCaptureRevision) ||
    (receipt.expectedCaptureRevision ?? 0) < 1 ||
    !Number.isInteger(receipt.finalizedCaptureRevision) ||
    receipt.finalizedCaptureRevision !== (receipt.expectedCaptureRevision ?? 0) + 1 ||
    receipt.finalizedPacketSequence?.resourceType !== "recorder-cold-path-packet-sequence" ||
    receipt.finalizedPacketSequence.resourceId !== receipt.captureReference.resourceId ||
    receipt.finalizedPacketSequence.format !== "recorder-gateway-cold-path-packet-sequence-v1" ||
    receipt.finalizedPacketSequence.mediaType !== "application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl" ||
    !Number.isInteger(receipt.finalizedPacketSequence.packetCount) ||
    (receipt.finalizedPacketSequence.packetCount ?? 0) < 1 ||
    !Number.isInteger(receipt.finalizedPacketSequence.payloadByteCount) ||
    (receipt.finalizedPacketSequence.payloadByteCount ?? -1) < 0 ||
    typeof receipt.finalizedPacketSequence.sha256 !== "string" ||
    !/^[a-f0-9]{64}$/.test(receipt.finalizedPacketSequence.sha256) ||
    receipt.finalizedAt === ""
  ) {
    throw new RecorderGatewayIngressDurableStateStoreError("Recorder Cold-Path Capture finalization receipt has invalid required fields");
  }
}

function isRecorderGatewayDeliveryReplayState(value: unknown): value is RecorderGatewayDeliveryReplayState {
  return value === "pending" || value === "delivering" || value === "delivered" || value === "terminal-failed";
}

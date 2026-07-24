import { randomUUID } from "node:crypto";
import {
  mkdir,
  open,
  readFile,
  readdir,
  rename,
  stat,
  unlink,
} from "node:fs/promises";
import { join } from "node:path";

import {
  LabReplaySessionNotFoundError,
  type LabReplaySessionStore,
} from "../../labrecorderrunnerapplication/lab-recorder-runner-ports.js";
import type { LabReplaySession } from "../../labrecorderrunnerdomain/lab-replay-contracts.js";
import { isLabRecorderRunnerIdentifier } from "../../labrecorderrunnerdomain/lab-recorder-run-contracts.js";

export class FileLabReplaySessionStore implements LabReplaySessionStore {
  public constructor(private readonly rootDirectory: string) {
    if (!rootDirectory.startsWith("/")) {
      throw new Error("Lab replay state directory must be an absolute Guest path");
    }
  }

  public async initialize(): Promise<void> {
    await mkdir(this.rootDirectory, { recursive: true, mode: 0o700 });
    const entries = await readdir(this.rootDirectory, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith(".json")) {
        throw new Error("Lab replay state directory contains an unsupported entry");
      }
      await this.readPath(join(this.rootDirectory, entry.name));
    }
  }

  public readByReplayId(replayId: string): Promise<LabReplaySession> {
    if (!isLabRecorderRunnerIdentifier(replayId)) {
      return Promise.reject(new LabReplaySessionNotFoundError("invalid replay id"));
    }
    return this.readPath(this.path(replayId));
  }

  public async readByRunnerSessionId(runnerSessionId: string): Promise<LabReplaySession> {
    if (!isLabRecorderRunnerIdentifier(runnerSessionId)) {
      throw new LabReplaySessionNotFoundError("invalid Runner session id");
    }
    const matches: LabReplaySession[] = [];
    for (const entry of await readdir(this.rootDirectory, { withFileTypes: true })) {
      if (!entry.isFile() || !entry.name.endsWith(".json")) {
        throw new Error("Lab replay state directory contains an unsupported entry");
      }
      const candidate = await this.readPath(join(this.rootDirectory, entry.name));
      if (candidate.preparationReceipt.runnerSessionId === runnerSessionId) {
        matches.push(candidate);
      }
    }
    if (matches.length === 0) {
      throw new LabReplaySessionNotFoundError("Lab replay Runner session does not exist");
    }
    if (matches.length > 1) {
      throw new Error("multiple Lab replay sessions own one Runner session id");
    }
    return matches[0]!;
  }

  public async create(session: LabReplaySession): Promise<void> {
    validateLabReplaySession(session);
    const target = this.path(session.preparationReceipt.replayId);
    try {
      await stat(target);
      throw new Error("Lab replay session already exists");
    } catch (error) {
      if (!isNotFound(error)) {
        throw error;
      }
    }
    await this.writeAtomically(target, session);
  }

  public async replace(current: LabReplaySession, next: LabReplaySession): Promise<void> {
    validateLabReplaySession(current);
    validateLabReplaySession(next);
    if (
      current.preparationReceipt.replayId !== next.preparationReceipt.replayId ||
      current.preparationReceipt.runnerSessionId !== next.preparationReceipt.runnerSessionId
    ) {
      throw new Error("Lab replay session identity cannot change");
    }
    const target = this.path(current.preparationReceipt.replayId);
    const stored = await this.readPath(target);
    if (JSON.stringify(stored) !== JSON.stringify(current)) {
      throw new Error("Lab replay session changed before replacement");
    }
    await this.writeAtomically(target, next);
  }

  private async writeAtomically(target: string, value: LabReplaySession): Promise<void> {
    const temporary = `${target}.tmp-${randomUUID()}`;
    try {
      const handle = await open(temporary, "wx", 0o600);
      try {
        await handle.writeFile(`${JSON.stringify(value)}\n`, "utf8");
        await handle.sync();
      } finally {
        await handle.close();
      }
      await rename(temporary, target);
      const directory = await open(this.rootDirectory, "r");
      try {
        await directory.sync();
      } finally {
        await directory.close();
      }
    } catch (error) {
      await unlink(temporary).catch(() => undefined);
      throw error;
    }
  }

  private async readPath(path: string): Promise<LabReplaySession> {
    try {
      await stat(path);
    } catch (error) {
      if (isNotFound(error)) {
        throw new LabReplaySessionNotFoundError("Lab replay session does not exist");
      }
      throw error;
    }
    const decoded = JSON.parse(await readFile(path, "utf8")) as unknown;
    validateLabReplaySession(decoded);
    return decoded;
  }

  private path(replayId: string): string {
    return join(this.rootDirectory, `${replayId}.json`);
  }
}

function validateLabReplaySession(value: unknown): asserts value is LabReplaySession {
  if (!isRecord(value) || value.schemaVersion !== "v1" || !isRecord(value.preparationReceipt)) {
    throw new Error("Lab replay session document is invalid");
  }
  const preparation = value.preparationReceipt;
  if (
    preparation.schemaVersion !== "v1" ||
    !isLabRecorderRunnerIdentifier(preparation.replayId) ||
    !isLabRecorderRunnerIdentifier(preparation.runnerSessionId) ||
    typeof preparation.spoolDatabaseSha256 !== "string" ||
    !/^[a-f0-9]{64}$/.test(preparation.spoolDatabaseSha256) ||
    !Number.isSafeInteger(preparation.frameCount) ||
    (preparation.frameCount as number) < 1 ||
    typeof preparation.outputStartedAt !== "number" ||
    !Number.isFinite(preparation.outputStartedAt) ||
    preparation.outputStartedAt <= 0 ||
    typeof preparation.preparedAt !== "string" ||
    Number.isNaN(Date.parse(preparation.preparedAt)) ||
    !isLabRecorderRunnerIdentifier(value.recorderGatewayRecorderCode) ||
    !Array.isArray(value.batches)
  ) {
    throw new Error("Lab replay session preparation evidence is invalid");
  }
  let frameCount = 0;
  for (const batch of value.batches) {
    if (
      !isRecord(batch) ||
      typeof batch.commandDigest !== "string" ||
      !/^[a-f0-9]{64}$/.test(batch.commandDigest) ||
      !isRecord(batch.receipt) ||
      batch.receipt.schemaVersion !== "v1" ||
      batch.receipt.replayId !== preparation.replayId ||
      batch.receipt.runnerSessionId !== preparation.runnerSessionId ||
      batch.receipt.startOffsetSecond !== frameCount ||
      !Number.isSafeInteger(batch.receipt.frameCount) ||
      (batch.receipt.frameCount as number) < 1 ||
      typeof batch.receipt.finalBatch !== "boolean" ||
      typeof batch.receipt.acceptedAt !== "string" ||
      Number.isNaN(Date.parse(batch.receipt.acceptedAt)) ||
      !Array.isArray(batch.ingressReceiptIds) ||
      batch.ingressReceiptIds.length !== batch.receipt.frameCount ||
      batch.ingressReceiptIds.some((id) => !isLabRecorderRunnerIdentifier(id))
    ) {
      throw new Error("Lab replay session batch evidence is invalid");
    }
    frameCount += batch.receipt.frameCount as number;
    if (batch.receipt.finalBatch !== (frameCount === preparation.frameCount)) {
      throw new Error("Lab replay session final batch evidence is invalid");
    }
  }
  if (frameCount > (preparation.frameCount as number)) {
    throw new Error("Lab replay session accepted frame count exceeds preparation");
  }
  if (value.upstreamDeliveryReceipt !== undefined) {
    const receipt = value.upstreamDeliveryReceipt;
    if (
      !isRecord(receipt) ||
      receipt.schemaVersion !== "v1" ||
      receipt.replayId !== preparation.replayId ||
      receipt.runnerSessionId !== preparation.runnerSessionId ||
      !isLabRecorderRunnerIdentifier(receipt.deliveryReceiptId) ||
      receipt.deliveredFrameCount !== preparation.frameCount ||
      typeof receipt.deliveryConfirmedAt !== "string" ||
      Number.isNaN(Date.parse(receipt.deliveryConfirmedAt)) ||
      frameCount !== preparation.frameCount
    ) {
      throw new Error("Lab replay session upstream delivery evidence is invalid");
    }
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNotFound(error: unknown): boolean {
  return isRecord(error) && error.code === "ENOENT";
}

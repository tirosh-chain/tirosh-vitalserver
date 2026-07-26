import { createHash, randomUUID } from "node:crypto";
import {
  createReadStream,
  createWriteStream,
  type ReadStream,
} from "node:fs";
import {
  mkdir,
  open,
  readdir,
  readFile,
  rename,
  rm,
  stat,
} from "node:fs/promises";
import type { IncomingHttpHeaders } from "node:http";
import { basename, join } from "node:path";
import { pipeline } from "node:stream/promises";

import Busboy from "busboy";

import type {
  RecorderVitalUploadMultipartSource,
  RecorderVitalUploadSpool,
} from "../../recordergatewayapplication/recorder-gateway-vital-upload-application-ports.js";
import {
  recorderGatewaySchemaVersion,
  isRecorderGatewayIdentifier,
} from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";
import {
  initialRecorderVitalUploadDispatch,
  validVitalFileName,
  validateRecorderVitalUploadDispatch,
  validateRecorderVitalUploadSourceReceipt,
  type RecorderVitalUploadDispatch,
  type RecorderVitalUploadSourceReceipt,
} from "../../recordergatewaydomain/recorder-gateway-vital-upload-contracts.js";

export class RecorderVitalUploadRejectedError extends Error {
  public readonly code: string;

  public constructor(code: string, message: string) {
    super(message);
    this.name = "RecorderVitalUploadRejectedError";
    this.code = code;
  }
}

export class RecorderVitalUploadSpoolError extends Error {
  public constructor(message: string, options?: ErrorOptions) {
    super(message, options);
    this.name = "RecorderVitalUploadSpoolError";
  }
}

export interface FileRecorderVitalUploadSpoolConfiguration {
  stateDirectory: string;
  maximumUploadBytes: number;
}

interface ParsedRecorderVitalUpload {
  uploadId?: string;
  reportedBedName?: string;
  declaredRecorderId?: string;
  declaredRecorderCode?: string;
  declaredSizeBytes?: number;
  originalFileName: string;
  byteSize: number;
  sha256: string;
}

export class FileRecorderVitalUploadSpool implements RecorderVitalUploadSpool {
  private readonly stagingDirectory: string;
  private readonly admissionsDirectory: string;

  public constructor(
    private readonly configuration: FileRecorderVitalUploadSpoolConfiguration,
  ) {
    if (
      configuration.stateDirectory === ""
      || !Number.isSafeInteger(configuration.maximumUploadBytes)
      || configuration.maximumUploadBytes < 1
    ) {
      throw new TypeError("Recorder Vital upload spool configuration is invalid");
    }
    const root = join(configuration.stateDirectory, "recorder-vital-uploads");
    this.stagingDirectory = join(root, "staging");
    this.admissionsDirectory = join(root, "admissions");
  }

  public async initializeRecorderVitalUploadSpool(): Promise<void> {
    try {
      await mkdir(this.stagingDirectory, { recursive: true, mode: 0o700 });
      await mkdir(this.admissionsDirectory, { recursive: true, mode: 0o700 });
    } catch (error) {
      throw new RecorderVitalUploadSpoolError(
        "could not initialize Recorder Vital upload spool",
        { cause: error },
      );
    }
  }

  public async admitRecorderVitalUpload(
    source: RecorderVitalUploadMultipartSource,
  ): Promise<RecorderVitalUploadSourceReceipt> {
    const transactionId = randomUUID();
    const transactionDirectory = join(this.stagingDirectory, transactionId);
    const contentPath = join(transactionDirectory, "content.vital");
    try {
      await mkdir(transactionDirectory, { mode: 0o700 });
      const parsed = await this.parseMultipartUpload(source.headers, source.body, contentPath);
      const receiptId = `recorder-vital-upload-${parsed.uploadId ?? transactionId}`;
      const uploadId = parsed.uploadId ?? receiptId;
      if (!isRecorderGatewayIdentifier(receiptId) || !isRecorderGatewayIdentifier(uploadId)) {
        throw new RecorderVitalUploadRejectedError(
          "recorder-vital-upload-identity-invalid",
          "Recorder Vital upload identity is invalid",
        );
      }
      const receipt: RecorderVitalUploadSourceReceipt = {
        schemaVersion: recorderGatewaySchemaVersion,
        id: receiptId,
        sourceKind: "recorder-upload",
        uploadId,
        originalFileName: parsed.originalFileName,
        mediaType: "application/x-vital",
        byteSize: parsed.byteSize,
        sha256: parsed.sha256,
        reportedBedName: parsed.reportedBedName!,
        declaredRecorderId: parsed.declaredRecorderId,
        declaredRecorderCode: parsed.declaredRecorderCode,
        state: "admitted",
        contentReference: {
          resourceType: "recorder-vital-upload-content",
          resourceId: receiptId,
        },
        receivedAt: source.receivedAt,
        finalizedAt: new Date().toISOString(),
      };
      validateRecorderVitalUploadSourceReceipt(receipt);
      await this.writeReceipt(transactionDirectory, receipt);
      await this.writeInitialDispatch(transactionDirectory, receipt);
      await this.syncDirectory(transactionDirectory);
      const admissionDirectory = this.admissionDirectory(receiptId);
      try {
        await rename(transactionDirectory, admissionDirectory);
      } catch (error) {
        if (await this.pathExists(admissionDirectory)) {
          throw new RecorderVitalUploadRejectedError(
            "recorder-vital-upload-id-conflict",
            "Recorder Vital upload identity already exists",
          );
        }
        throw error;
      }
      await this.syncDirectory(this.admissionsDirectory);
      return receipt;
    } catch (error) {
      await rm(transactionDirectory, { recursive: true, force: true }).catch(() => undefined);
      if (error instanceof RecorderVitalUploadRejectedError) {
        throw error;
      }
      throw new RecorderVitalUploadSpoolError(
        "Recorder Vital upload durable admission outcome is unknown",
        { cause: error },
      );
    }
  }

  public async readRecorderVitalUploadSourceReceipt(
    receiptId: string,
  ): Promise<RecorderVitalUploadSourceReceipt> {
    if (!isRecorderGatewayIdentifier(receiptId)) {
      throw new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-receipt-id-invalid",
        "Recorder Vital upload receipt identity is invalid",
      );
    }
    try {
      const document = JSON.parse(
        await readFile(join(this.admissionDirectory(receiptId), "receipt.json"), "utf8"),
      ) as RecorderVitalUploadSourceReceipt;
      validateRecorderVitalUploadSourceReceipt(document);
      return document;
    } catch (error) {
      throw new RecorderVitalUploadSpoolError(
        "could not read Recorder Vital upload source receipt",
        { cause: error },
      );
    }
  }

  public async openRecorderVitalUploadContent(receiptId: string): Promise<ReadStream> {
    const receipt = await this.readRecorderVitalUploadSourceReceipt(receiptId);
    const contentPath = join(this.admissionDirectory(receipt.id), "content.vital");
    const content = await stat(contentPath);
    if (!content.isFile() || content.size !== receipt.byteSize) {
      throw new RecorderVitalUploadSpoolError(
        "Recorder Vital upload content does not match its durable receipt",
      );
    }
    return createReadStream(contentPath);
  }

  public async readRecorderVitalUploadDispatch(
    receiptId: string,
  ): Promise<RecorderVitalUploadDispatch> {
    if (!isRecorderGatewayIdentifier(receiptId)) {
      throw new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-receipt-id-invalid",
        "Recorder Vital upload receipt identity is invalid",
      );
    }
    try {
      const dispatchDirectory = join(this.admissionDirectory(receiptId), "dispatch");
      const entries = await readdir(dispatchDirectory, { withFileTypes: true });
      const revisions = entries
        .filter((entry) => entry.isFile() && /^[0-9]{12}\.json$/.test(entry.name))
        .map((entry) => entry.name)
        .sort();
      const latest = revisions.at(-1);
      if (latest === undefined) {
        throw new Error("Recorder Vital upload dispatch revision is missing");
      }
      const document = JSON.parse(
        await readFile(join(dispatchDirectory, latest), "utf8"),
      ) as RecorderVitalUploadDispatch;
      validateRecorderVitalUploadDispatch(document);
      if (dispatchRevisionFileName(document.revision) !== latest) {
        throw new Error("Recorder Vital upload dispatch filename and revision differ");
      }
      return document;
    } catch (error) {
      throw new RecorderVitalUploadSpoolError(
        "could not read Recorder Vital upload dispatch",
        { cause: error },
      );
    }
  }

  public async commitRecorderVitalUploadDispatch(
    expectedRevision: number,
    next: RecorderVitalUploadDispatch,
  ): Promise<void> {
    validateRecorderVitalUploadDispatch(next);
    if (
      !Number.isSafeInteger(expectedRevision)
      || expectedRevision < 0
      || next.revision !== expectedRevision + 1
    ) {
      throw new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-dispatch-revision-invalid",
        "Recorder Vital upload dispatch revision transition is invalid",
      );
    }
    const current = await this.readRecorderVitalUploadDispatch(next.sourceReceiptId);
    if (
      current.revision !== expectedRevision
      || current.sourceReceiptId !== next.sourceReceiptId
      || current.requestId !== next.requestId
    ) {
      throw new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-dispatch-revision-conflict",
        "Recorder Vital upload dispatch revision changed",
      );
    }
    const dispatchDirectory = join(
      this.admissionDirectory(next.sourceReceiptId),
      "dispatch",
    );
    try {
      await this.writeJSONDocument(
        join(dispatchDirectory, dispatchRevisionFileName(next.revision)),
        next,
      );
      await this.syncDirectory(dispatchDirectory);
      await this.syncDirectory(this.admissionDirectory(next.sourceReceiptId));
    } catch (error) {
      throw new RecorderVitalUploadSpoolError(
        "Recorder Vital upload dispatch commit outcome is unknown",
        { cause: error },
      );
    }
  }

  public async listRecoverableRecorderVitalUploadDispatches(
    limit: number,
  ): Promise<RecorderVitalUploadDispatch[]> {
    if (!Number.isSafeInteger(limit) || limit < 1 || limit > 1000) {
      throw new TypeError("Recorder Vital upload recovery limit must be between 1 and 1000");
    }
    try {
      const entries = await readdir(this.admissionsDirectory, { withFileTypes: true });
      const result: RecorderVitalUploadDispatch[] = [];
      for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
        if (!entry.isDirectory()) {
          throw new Error("Recorder Vital upload admissions directory contains an unexpected entry");
        }
        const dispatch = await this.readRecorderVitalUploadDispatch(entry.name);
        if (
          dispatch.state === "pending"
          || dispatch.state === "dispatching"
          || dispatch.state === "unknown"
        ) {
          result.push(dispatch);
        }
      }
      result.sort((left, right) => (
        left.updatedAt.localeCompare(right.updatedAt)
        || left.sourceReceiptId.localeCompare(right.sourceReceiptId)
      ));
      return result.slice(0, limit);
    } catch (error) {
      if (error instanceof RecorderVitalUploadSpoolError) {
        throw error;
      }
      throw new RecorderVitalUploadSpoolError(
        "could not list recoverable Recorder Vital upload dispatches",
        { cause: error },
      );
    }
  }

  private async parseMultipartUpload(
    headers: IncomingHttpHeaders,
    body: NodeJS.ReadableStream,
    contentPath: string,
  ): Promise<ParsedRecorderVitalUpload> {
    const uploadId = optionalSingleHeader(headers, "x-vital-upload-id");
    const headerBedName = optionalSingleHeader(headers, "x-vital-bed-name");
    const declaredRecorderId = optionalSingleHeader(headers, "x-vital-recorder-id");
    const headerRecorderCode = optionalSingleHeader(headers, "x-vital-recorder-code");
    const declaredSize = optionalSingleHeader(headers, "x-vital-file-size");
    const declaredSizeBytes = declaredSize === undefined
      ? undefined
      : parsePositiveInteger(declaredSize, "x-vital-file-size");
    const hash = createHash("sha256");
    let fileName: string | undefined;
    let fileCount = 0;
    let byteSize = 0;
    let fileLimitReached = false;
    const fields = new Map<string, string>();
    const busboy = Busboy({
      headers,
      limits: {
        fileSize: this.configuration.maximumUploadBytes,
        files: 1,
        fields: 10,
        parts: 12,
        fieldSize: 1024,
      },
    });
    let fileWrite: Promise<void> | undefined;
    busboy.on("file", (fieldName, file, info) => {
      fileCount += 1;
      if (fieldName !== "vitalfile" || fileCount !== 1) {
        file.resume();
        return;
      }
      fileName = basename(info.filename);
      if (!validVitalFileName(fileName) || fileName !== info.filename) {
        file.resume();
        return;
      }
      file.on("limit", () => {
        fileLimitReached = true;
      });
      file.on("data", (chunk: Buffer) => {
        byteSize += chunk.byteLength;
        hash.update(chunk);
      });
      fileWrite = pipeline(file, createWriteStream(contentPath, { flags: "wx", mode: 0o600 }));
    });
    busboy.on("field", (name, value) => {
      if (fields.has(name)) {
        fields.set(name, "");
        return;
      }
      fields.set(name, value.trim());
    });
    const parsing = new Promise<void>((resolve, reject) => {
      busboy.once("close", resolve);
      busboy.once("error", reject);
      busboy.once("filesLimit", () => reject(new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-file-count-invalid",
        "Recorder Vital upload must contain exactly one vitalfile part",
      )));
      busboy.once("partsLimit", () => reject(new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-part-count-exceeded",
        "Recorder Vital upload contains too many multipart parts",
      )));
      busboy.once("fieldsLimit", () => reject(new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-field-count-exceeded",
        "Recorder Vital upload contains too many form fields",
      )));
    });
    body.pipe(busboy);
    await parsing;
    if (fileWrite !== undefined) {
      await fileWrite;
    }
    if (fileLimitReached) {
      throw new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-size-exceeded",
        "Recorder Vital upload exceeds the configured byte limit",
      );
    }
    if (fileCount !== 1 || fileName === undefined || byteSize < 1) {
      throw new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-file-invalid",
        "Recorder Vital upload must contain one non-empty .vital file",
      );
    }
    if (declaredSizeBytes !== undefined && declaredSizeBytes !== byteSize) {
      throw new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-size-mismatch",
        "Recorder Vital upload declared size does not match received file bytes",
      );
    }
    const reportedBedName = explicitMatchingEvidence(
      headerBedName,
      fields.get("bedname") ?? fields.get("bedName"),
      "reported bed name",
    );
    if (reportedBedName === undefined || reportedBedName === "") {
      throw new RecorderVitalUploadRejectedError(
        "recorder-vital-upload-bed-name-missing",
        "Recorder Vital upload must report a bed name",
      );
    }
    const declaredRecorderCode = explicitMatchingEvidence(
      headerRecorderCode,
      fields.get("vrcode"),
      "declared Recorder code",
    );
    const contentHandle = await open(contentPath, "r");
    try {
      await contentHandle.sync();
    } finally {
      await contentHandle.close();
    }
    return {
      uploadId,
      reportedBedName,
      declaredRecorderId,
      declaredRecorderCode,
      declaredSizeBytes,
      originalFileName: fileName,
      byteSize,
      sha256: hash.digest("hex"),
    };
  }

  private async writeReceipt(
    transactionDirectory: string,
    receipt: RecorderVitalUploadSourceReceipt,
  ): Promise<void> {
    const handle = await open(join(transactionDirectory, "receipt.json"), "wx", 0o600);
    try {
      await handle.writeFile(`${JSON.stringify(receipt)}\n`, "utf8");
      await handle.sync();
    } finally {
      await handle.close();
    }
  }

  private async writeInitialDispatch(
    transactionDirectory: string,
    receipt: RecorderVitalUploadSourceReceipt,
  ): Promise<void> {
    const dispatchDirectory = join(transactionDirectory, "dispatch");
    await mkdir(dispatchDirectory, { mode: 0o700 });
    const dispatch = initialRecorderVitalUploadDispatch(receipt);
    await this.writeJSONDocument(
      join(dispatchDirectory, dispatchRevisionFileName(dispatch.revision)),
      dispatch,
    );
    await this.syncDirectory(dispatchDirectory);
  }

  private async writeJSONDocument(path: string, value: unknown): Promise<void> {
    const handle = await open(path, "wx", 0o600);
    try {
      await handle.writeFile(`${JSON.stringify(value)}\n`, "utf8");
      await handle.sync();
    } finally {
      await handle.close();
    }
  }

  private async syncDirectory(path: string): Promise<void> {
    const handle = await open(path, "r");
    try {
      await handle.sync();
    } finally {
      await handle.close();
    }
  }

  private admissionDirectory(receiptId: string): string {
    return join(this.admissionsDirectory, receiptId);
  }

  private async pathExists(path: string): Promise<boolean> {
    try {
      await stat(path);
      return true;
    } catch (error) {
      if (error instanceof Error && "code" in error && error.code === "ENOENT") {
        return false;
      }
      throw error;
    }
  }
}

function dispatchRevisionFileName(revision: number): string {
  if (!Number.isSafeInteger(revision) || revision < 0 || revision > 999999999999) {
    throw new TypeError("Recorder Vital upload dispatch revision is invalid");
  }
  return `${revision.toString().padStart(12, "0")}.json`;
}

function optionalSingleHeader(
  headers: IncomingHttpHeaders,
  name: string,
): string | undefined {
  const value = headers[name];
  if (value === undefined) {
    return undefined;
  }
  if (Array.isArray(value)) {
    throw new RecorderVitalUploadRejectedError(
      "recorder-vital-upload-header-invalid",
      `${name} must appear exactly once`,
    );
  }
  const normalized = value.trim();
  if (normalized === "") {
    throw new RecorderVitalUploadRejectedError(
      "recorder-vital-upload-header-invalid",
      `${name} must not be empty`,
    );
  }
  return normalized;
}

function parsePositiveInteger(value: string, name: string): number {
  if (!/^[1-9][0-9]*$/.test(value)) {
    throw new RecorderVitalUploadRejectedError(
      "recorder-vital-upload-header-invalid",
      `${name} must be a positive integer`,
    );
  }
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) {
    throw new RecorderVitalUploadRejectedError(
      "recorder-vital-upload-header-invalid",
      `${name} exceeds the supported integer range`,
    );
  }
  return parsed;
}

function explicitMatchingEvidence(
  headerValue: string | undefined,
  formValue: string | undefined,
  subject: string,
): string | undefined {
  if (
    headerValue !== undefined
    && formValue !== undefined
    && headerValue !== formValue
  ) {
    throw new RecorderVitalUploadRejectedError(
      "recorder-vital-upload-evidence-conflict",
      `${subject} differs between header and multipart form`,
    );
  }
  return headerValue ?? formValue;
}

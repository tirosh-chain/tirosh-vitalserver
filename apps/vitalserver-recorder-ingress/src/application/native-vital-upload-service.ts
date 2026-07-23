import type {
  NativeVitalUploadIndexPort,
} from "./ports/outbound/native-vital-upload-index-port";
import type {
  NativeVitalUploadRegistryPort,
} from "./ports/outbound/native-vital-upload-registry-port";
import {
  attemptedNativeVitalUploadReconciliation,
  beginNativeVitalUpload,
  failNativeVitalUpload,
  indexedNativeVitalUpload,
  reconcileNativeVitalUpload,
  type NativeVitalUploadMetadata,
  type NativeVitalUploadRecord,
} from "../domain/native-vital-upload";

"use strict";

type NativeVitalUploadClock = {
  now(): string;
};

type NativeVitalUploadServiceDependencies = {
  registry: NativeVitalUploadRegistryPort;
  vitalServerIndex: NativeVitalUploadIndexPort;
  clock?: NativeVitalUploadClock;
  reconciliation: {
    intervalMs: number;
    maxAttempts: number;
  };
};

export type NativeVitalUploadBeginResult = {
  kind: "started" | "alreadyIndexed";
  record: NativeVitalUploadRecord;
};

export type NativeVitalUploadService = ReturnType<
  typeof createNativeVitalUploadService
>;

export function createNativeVitalUploadService({
  registry,
  vitalServerIndex,
  clock = { now: () => new Date().toISOString() },
  reconciliation,
}: NativeVitalUploadServiceDependencies) {
  if (
    !reconciliation
    || !Number.isInteger(reconciliation.intervalMs)
    || reconciliation.intervalMs <= 0
    || !Number.isInteger(reconciliation.maxAttempts)
    || reconciliation.maxAttempts <= 0
  ) {
    throw new TypeError("native upload reconciliation settings are invalid");
  }
  let timer: ReturnType<typeof setInterval> | null = null;
  let reconciliationRun: Promise<void> | null = null;

  function begin(
    metadata: NativeVitalUploadMetadata,
  ): NativeVitalUploadBeginResult {
    const existing = registry.get(metadata.uploadId);
    if (existing) {
      assertSameMetadata(existing, metadata);
      if (existing.state === "indexed") {
        return { kind: "alreadyIndexed", record: existing };
      }
      throw new Error(
        `native uploadId is already ${existing.state}: ${metadata.uploadId}`,
      );
    }
    const record = beginNativeVitalUpload(metadata, clock.now());
    registry.save(record);
    return { kind: "started", record };
  }

  function recordClientFailure(
    uploadId: string,
    error: unknown,
  ): NativeVitalUploadRecord {
    return failCurrent(uploadId, {
      stage: "clientStream",
      code: "clientStreamFailed",
      message: errorMessage(error),
      occurredAt: clock.now(),
    });
  }

  function recordUpstreamFailure(
    uploadId: string,
    error: unknown,
  ): NativeVitalUploadRecord {
    return failCurrent(uploadId, {
      stage: "upstreamUpload",
      code: "upstreamUnavailable",
      message: errorMessage(error),
      occurredAt: clock.now(),
    });
  }

  function recordUpstreamResult(
    uploadId: string,
    result: { statusCode: number; responseBody: string },
  ): NativeVitalUploadRecord {
    const current = requiredRecord(uploadId);
    if (
      result.statusCode >= 200
      && result.statusCode < 300
      && result.responseBody.trim() === "success"
    ) {
      const record = reconcileNativeVitalUpload(current, {
        upstreamStatusCode: result.statusCode,
        upstreamResponse: result.responseBody,
        occurredAt: clock.now(),
      });
      registry.save(record);
      return record;
    }
    return failCurrent(uploadId, {
      stage: "upstreamUpload",
      code: "upstreamRejected",
      message: (
        `VitalServer upload rejected the file: status=${result.statusCode} `
        + `response=${boundedMessage(result.responseBody)}`
      ),
      occurredAt: clock.now(),
    });
  }

  function runReconciliationOnce(): Promise<void> {
    if (reconciliationRun) return reconciliationRun;
    reconciliationRun = reconcilePendingUploads().finally(() => {
      reconciliationRun = null;
    });
    return reconciliationRun;
  }

  async function reconcilePendingUploads(): Promise<void> {
    for (const current of registry.list()) {
      if (current.state !== "reconciling") continue;
      const occurredAt = clock.now();
      try {
        const evidence = await vitalServerIndex.find(current.filename);
        if (evidence) {
          if (
            evidence.filename !== current.filename
            || evidence.sizeBytes !== current.declaredSizeBytes
          ) {
            registry.save(failNativeVitalUpload(current, {
              stage: "indexVerification",
              code: "indexedMetadataMismatch",
              message: (
                "VitalServer index evidence differs from the declared upload: "
                + `filename=${evidence.filename} sizeBytes=${evidence.sizeBytes}`
              ),
              occurredAt,
            }));
            continue;
          }
          registry.save(indexedNativeVitalUpload(
            current,
            evidence,
            occurredAt,
          ));
          continue;
        }
        persistReconciliationMiss(
          current,
          "indexedFileNotFound",
          `VitalServer index does not contain ${current.filename}`,
          occurredAt,
        );
      } catch (error) {
        persistReconciliationMiss(
          current,
          "indexDependencyFailed",
          errorMessage(error),
          occurredAt,
        );
      }
    }
  }

  function persistReconciliationMiss(
    current: NativeVitalUploadRecord,
    code: string,
    message: string,
    occurredAt: string,
  ): void {
    const attempted = attemptedNativeVitalUploadReconciliation(
      current,
      occurredAt,
    );
    registry.save(attempted);
    if (attempted.reconciliationAttempts >= reconciliation.maxAttempts) {
      registry.save(failNativeVitalUpload(attempted, {
        stage: "indexVerification",
        code,
        message,
        occurredAt,
      }));
    }
  }

  function recoverInterrupted(): void {
    for (const current of registry.list()) {
      if (current.state !== "receiving") continue;
      registry.save(failNativeVitalUpload(current, {
        stage: "processInterrupted",
        code: "ingressRestarted",
        message: (
          "Recorder ingress restarted before the upload response was known."
        ),
        occurredAt: clock.now(),
      }));
    }
  }

  function start(): void {
    if (timer) return;
    recoverInterrupted();
    timer = setInterval(() => {
      runReconciliationOnce().catch((error) => {
        console.error(
          "[recorder-ingress] native upload reconciliation failed:",
          errorMessage(error),
        );
      });
    }, reconciliation.intervalMs);
  }

  function stop(): void {
    if (!timer) return;
    clearInterval(timer);
    timer = null;
  }

  function list(): NativeVitalUploadRecord[] {
    return registry.list();
  }

  function get(uploadId: string): NativeVitalUploadRecord | null {
    return registry.get(uploadId);
  }

  function requiredRecord(uploadId: string): NativeVitalUploadRecord {
    const record = registry.get(uploadId);
    if (!record) {
      throw new Error(`native upload record is missing: ${uploadId}`);
    }
    return record;
  }

  function failCurrent(uploadId: string, failure): NativeVitalUploadRecord {
    const failed = failNativeVitalUpload(requiredRecord(uploadId), failure);
    registry.save(failed);
    return failed;
  }

  return {
    begin,
    get,
    list,
    recordClientFailure,
    recordUpstreamFailure,
    recordUpstreamResult,
    recoverInterrupted,
    runReconciliationOnce,
    start,
    stop,
  };
}

function assertSameMetadata(
  existing: NativeVitalUploadRecord,
  metadata: NativeVitalUploadMetadata,
): void {
  if (
    existing.bedName !== metadata.bedName
    || existing.declaredVrcode !== metadata.declaredVrcode
    || existing.filename !== metadata.filename
    || existing.declaredSizeBytes !== metadata.declaredSizeBytes
  ) {
    throw new Error(
      `native upload metadata conflict: uploadId=${metadata.uploadId}`,
    );
  }
}

function errorMessage(error: unknown): string {
  return error && typeof error === "object" && "message" in error
    ? String(error.message)
    : String(error);
}

function boundedMessage(value: string): string {
  const normalized = String(value || "").trim();
  return normalized.length <= 1024
    ? JSON.stringify(normalized)
    : `${JSON.stringify(normalized.slice(0, 1024))}…`;
}

module.exports = { createNativeVitalUploadService };

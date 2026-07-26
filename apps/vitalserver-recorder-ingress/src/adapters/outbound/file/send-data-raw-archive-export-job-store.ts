import type {
  SendDataRawArchiveExportJobStorePort,
  SendDataRawArchiveExportStateDocument,
} from "../../../application/ports/outbound/send-data-raw-archive-export-job-store-port";

"use strict";

const fs = require("fs");
const path = require("path");

function createSendDataRawArchiveExportJobStore(config): SendDataRawArchiveExportJobStorePort {
  const autoExport = config && config.rawArchive && config.rawArchive.autoExport
    ? config.rawArchive.autoExport
    : {};
  const statePath = autoExport.statePath || "";
  const resolvedPath = statePath || "/var/lib/vitalserver-recorder-ingress/recovery/raw-archive-auto-export-state.json";
  if (autoExport.enabled) {
    fs.mkdirSync(path.dirname(resolvedPath), { recursive: true });
  }

  return {
    read(): SendDataRawArchiveExportStateDocument {
      try {
        const document = JSON.parse(fs.readFileSync(resolvedPath, "utf8"));
        return normalizeDocument(document);
      } catch (error) {
        if (error && error.code === "ENOENT") return emptyDocument();
        throw error;
      }
    },
    write(document: SendDataRawArchiveExportStateDocument): void {
      const normalized = normalizeDocument(document);
      const tmpPath = `${resolvedPath}.${process.pid}.${Date.now()}.tmp`;
      fs.writeFileSync(tmpPath, `${JSON.stringify(normalized, null, 2)}\n`, "utf8");
      fs.renameSync(tmpPath, resolvedPath);
    },
  };
}

function emptyDocument(): SendDataRawArchiveExportStateDocument {
  return {
    schemaVersion: 3,
    updatedAt: new Date(0).toISOString(),
    observedByVrcode: {},
    checkpointsByVrcode: {},
    pendingFinalizations: [],
    activeJob: null,
    history: [],
  };
}

function normalizeDocument(document): SendDataRawArchiveExportStateDocument {
  if (document && document.schemaVersion === 1) {
    if (document.activeJob) {
      throw new Error("raw archive export state schemaVersion 1 has an active job and cannot be migrated safely");
    }
    return emptyDocument();
  }
  if (document && document.schemaVersion === 2) {
    return migrateVersion2Document(document);
  }
  if (!document || document.schemaVersion !== 3) {
    throw new Error("raw archive export state document schemaVersion must be 3");
  }
  return {
    schemaVersion: 3,
    updatedAt: requiredString(document.updatedAt, "updatedAt"),
    observedByVrcode: requiredObject(document.observedByVrcode, "observedByVrcode"),
    checkpointsByVrcode: requiredObject(document.checkpointsByVrcode, "checkpointsByVrcode"),
    pendingFinalizations: requiredArray(document.pendingFinalizations, "pendingFinalizations"),
    activeJob: document.activeJob ? normalizeVersion3Job(document.activeJob) : null,
    history: requiredArray(document.history, "history").map(normalizeVersion3Job),
  };
}

function migrateVersion2Document(document): SendDataRawArchiveExportStateDocument {
  const updatedAt = requiredString(document.updatedAt, "updatedAt");
  const checkpoints = requiredObject(document.checkpointsByVrcode, "checkpointsByVrcode");
  return {
    schemaVersion: 3,
    updatedAt,
    observedByVrcode: requiredObject(document.observedByVrcode, "observedByVrcode"),
    checkpointsByVrcode: Object.fromEntries(
      Object.entries(checkpoints).map(([vrcode, checkpoint]) => [
        vrcode,
        migrateVersion2Checkpoint(checkpoint),
      ]),
    ),
    pendingFinalizations: requiredArray(document.pendingFinalizations, "pendingFinalizations"),
    activeJob: document.activeJob ? migrateVersion2Job(document.activeJob) : null,
    history: requiredArray(document.history, "history").map(migrateVersion2Job),
  };
}

function migrateVersion2Job(job) {
  const legacyState = requiredString(job.state, "job.state");
  const completed = legacyState === "uploaded";
  const pending = legacyState === "pending" || legacyState === "running";
  const failed = legacyState === "retryable_failed" || legacyState === "failed";
  if (!completed && !pending && !failed) {
    throw new Error(`raw archive export state schemaVersion 2 job state is invalid: ${legacyState}`);
  }
  const migratedFailure = failed
    ? {
        stage: "unknownLegacyStage" as const,
        reason: job.lastFailure && job.lastFailure.reason
          ? String(job.lastFailure.reason)
          : "unknown_legacy_failure",
        message: job.lastFailure && job.lastFailure.message
          ? String(job.lastFailure.message)
          : "legacy export/upload failure stage is unknown",
        occurredAt: job.lastFailure && job.lastFailure.occurredAt
          ? String(job.lastFailure.occurredAt)
          : requiredString(job.updatedAt, "job.updatedAt"),
      }
    : null;
  return {
    ...job,
    schemaVersion: 3 as const,
    origin: "coldPathRecovery" as const,
    state: completed
      ? "exported" as const
      : failed
        ? "export_failed" as const
        : "export_pending" as const,
    publishState: completed ? "published" as const : failed ? "unknownLegacy" as const : "notRequested" as const,
    artifacts: [],
    startedAt: pending ? null : job.startedAt || null,
    completedAt: completed || legacyState === "failed" ? job.completedAt || job.updatedAt : null,
    nextAttemptAt: null,
    lastFailure: migratedFailure,
  };
}

function migrateVersion2Checkpoint(checkpoint) {
  if (!checkpoint || typeof checkpoint !== "object" || Array.isArray(checkpoint)) {
    throw new Error("raw archive export state schemaVersion 2 checkpoint must be an object");
  }
  return {
    ...checkpoint,
    origin: "coldPathRecovery" as const,
    artifactIds: [],
    publishState: "published" as const,
  };
}

function normalizeVersion3Job(job) {
  if (!job || typeof job !== "object" || Array.isArray(job)) {
    throw new Error("raw archive export state document job must be an object");
  }
  if (job.schemaVersion !== 3) {
    throw new Error("raw archive export state document job schemaVersion must be 3");
  }
  if (job.origin !== "coldPathRecovery" && job.origin !== "productLabGenerated") {
    throw new Error("raw archive export state document job origin is invalid");
  }
  const states = new Set([
    "export_pending",
    "exporting",
    "exported",
    "export_retryable_failed",
    "export_failed",
  ]);
  if (!states.has(job.state)) {
    throw new Error("raw archive export state document job state is invalid");
  }
  const publishStates = new Set(["notRequested", "published", "unknownLegacy"]);
  if (!publishStates.has(job.publishState)) {
    throw new Error("raw archive export state document job publishState is invalid");
  }
  requiredArray(job.artifacts, "job.artifacts");
  return job;
}

function requiredString(value, field) {
  if (typeof value !== "string" || !value) {
    throw new Error(`raw archive export state document requires string ${field}`);
  }
  return value;
}

function requiredObject(value, field) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`raw archive export state document requires object ${field}`);
  }
  return value;
}

function requiredArray(value, field) {
  if (!Array.isArray(value)) {
    throw new Error(`raw archive export state document requires array ${field}`);
  }
  return value;
}

module.exports = { createSendDataRawArchiveExportJobStore };

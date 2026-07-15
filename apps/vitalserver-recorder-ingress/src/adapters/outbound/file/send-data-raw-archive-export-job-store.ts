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
    schemaVersion: 2,
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
  if (!document || document.schemaVersion !== 2) {
    throw new Error("raw archive export state document schemaVersion must be 2");
  }
  return {
    schemaVersion: 2,
    updatedAt: requiredString(document.updatedAt, "updatedAt"),
    observedByVrcode: requiredObject(document.observedByVrcode, "observedByVrcode"),
    checkpointsByVrcode: requiredObject(document.checkpointsByVrcode, "checkpointsByVrcode"),
    pendingFinalizations: requiredArray(document.pendingFinalizations, "pendingFinalizations"),
    activeJob: document.activeJob || null,
    history: requiredArray(document.history, "history"),
  };
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

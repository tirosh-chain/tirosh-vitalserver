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
    schemaVersion: 1,
    updatedAt: new Date(0).toISOString(),
    lastObserved: null,
    checkpoint: null,
    activeJob: null,
    history: [],
  };
}

function normalizeDocument(document): SendDataRawArchiveExportStateDocument {
  if (!document || document.schemaVersion !== 1) {
    throw new Error("raw archive export state document schemaVersion must be 1");
  }
  return {
    schemaVersion: 1,
    updatedAt: stringValue(document.updatedAt, new Date(0).toISOString()),
    lastObserved: document.lastObserved || null,
    checkpoint: document.checkpoint || null,
    activeJob: document.activeJob || null,
    history: Array.isArray(document.history) ? document.history : [],
  };
}

function stringValue(value, fallback) {
  return typeof value === "string" && value ? value : fallback;
}

module.exports = { createSendDataRawArchiveExportJobStore };

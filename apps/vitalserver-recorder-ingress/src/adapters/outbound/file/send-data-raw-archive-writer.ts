import type {
  SendDataRawArchiveAppendResult,
  SendDataRawArchivePort,
} from "../../../application/ports/outbound/send-data-raw-archive-port";
import type { SendDataSpoolItem } from "../../../domain/send-data-spool-types";

"use strict";

const fs = require("fs");
const path = require("path");
const { createSendDataRawArchiveRecord } = require("../../../application/send-data-raw-archive-record");

function createSendDataRawArchiveWriter(config): SendDataRawArchivePort {
  const settings = config || { enabled: false, path: "" };
  const archivePath = settings.path || "";
  if (settings.enabled) {
    ensureLogDirectory(archivePath);
  }

  return {
    append(item: SendDataSpoolItem): SendDataRawArchiveAppendResult {
      if (!settings.enabled) {
        return {
          ok: false,
          reason: "raw_archive_unavailable",
          message: "send_data raw archive is disabled",
        };
      }

      try {
        const line = `${JSON.stringify(createSendDataRawArchiveRecord(item))}\n`;
        const bytes = Buffer.byteLength(line);
        rotateArchiveIfNeeded(archivePath, bytes, settings);
        const offset = currentOffset(archivePath);
        fs.appendFileSync(archivePath, line, "utf8");
        return {
          ok: true,
          archiveId: path.basename(archivePath),
          path: archivePath,
          offset,
          endOffset: offset + bytes,
          bytes,
        };
      } catch (error) {
        return {
          ok: false,
          reason: "raw_archive_write_failed",
          message: error && error.message ? error.message : "send_data raw archive write failed",
          error,
        };
      }
    },
  };
}

function rotateArchiveIfNeeded(filePath, nextBytes, settings) {
  const maxFileBytes = Number.isFinite(settings.maxFileBytes) ? Number(settings.maxFileBytes) : 0;
  if (maxFileBytes <= 0) return;
  const offset = currentOffset(filePath);
  if (offset === 0 || offset + nextBytes <= maxFileBytes) return;

  const rotatedPath = rotatedArchivePath(filePath, new Date());
  fs.renameSync(filePath, rotatedPath);
  pruneRotatedArchives(filePath, settings.maxFiles);
}

function rotatedArchivePath(filePath, now) {
  const directory = path.dirname(filePath);
  const extension = path.extname(filePath);
  const base = path.basename(filePath, extension);
  const timestamp = now.toISOString().replace(/[:.]/g, "-");
  const suffix = extension || ".jsonl";
  let candidate = path.join(directory, `${base}.${timestamp}${suffix}`);
  let index = 1;
  while (fs.existsSync(candidate)) {
    candidate = path.join(directory, `${base}.${timestamp}.${index}${suffix}`);
    index += 1;
  }
  return candidate;
}

function pruneRotatedArchives(filePath, maxFiles) {
  const maxTotalFiles = Number.isFinite(maxFiles) ? Math.max(1, Number(maxFiles)) : 0;
  if (maxTotalFiles <= 0) return;

  const rotatedLimit = Math.max(0, maxTotalFiles - 1);
  const directory = path.dirname(filePath);
  const extension = path.extname(filePath);
  const base = path.basename(filePath, extension);
  const prefix = `${base}.`;
  const suffix = extension || ".jsonl";
  const rotated = fs.readdirSync(directory)
    .filter((name) => name.startsWith(prefix) && name.endsWith(suffix))
    .map((name) => {
      const fullPath = path.join(directory, name);
      return { name, path: fullPath, mtimeMs: fs.statSync(fullPath).mtimeMs };
    })
    .sort((left, right) => right.mtimeMs - left.mtimeMs);

  for (const entry of rotated.slice(rotatedLimit)) {
    fs.unlinkSync(entry.path);
  }
}

function currentOffset(filePath) {
  try {
    return fs.statSync(filePath).size;
  } catch (error) {
    if (error && error.code === "ENOENT") return 0;
    throw error;
  }
}

function ensureLogDirectory(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

module.exports = { createSendDataRawArchiveWriter };

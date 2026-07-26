import type {
  NativeVitalUploadRegistryPort,
} from "../../../application/ports/outbound/native-vital-upload-registry-port";
import {
  nativeVitalUploadRecordFromDocument,
  type NativeVitalUploadRecord,
} from "../../../domain/native-vital-upload";

"use strict";

const fs = require("fs");
const path = require("path");

type NativeVitalUploadRegistryConfig = {
  statePath: string;
};

type NativeVitalUploadRegistryDocument = {
  schemaVersion: 1;
  uploads: NativeVitalUploadRecord[];
};

export function createNativeVitalUploadRegistry(
  config: NativeVitalUploadRegistryConfig,
): NativeVitalUploadRegistryPort {
  if (!config || typeof config.statePath !== "string" || !config.statePath) {
    throw new TypeError("native upload registry statePath is required");
  }
  const statePath = config.statePath;
  fs.mkdirSync(path.dirname(statePath), { recursive: true });

  function read(): NativeVitalUploadRegistryDocument {
    let raw: string;
    try {
      raw = fs.readFileSync(statePath, "utf8");
    } catch (error) {
      if (error && error.code === "ENOENT") {
        return { schemaVersion: 1, uploads: [] };
      }
      throw error;
    }
    const parsed = JSON.parse(raw);
    if (
      !parsed
      || parsed.schemaVersion !== 1
      || !Array.isArray(parsed.uploads)
    ) {
      throw new TypeError(
        "native upload registry document contract is invalid",
      );
    }
    const uploads = parsed.uploads.map(nativeVitalUploadRecordFromDocument);
    const identities = new Set<string>();
    for (const upload of uploads) {
      if (identities.has(upload.uploadId)) {
        throw new TypeError(
          `native upload registry contains duplicate uploadId=${upload.uploadId}`,
        );
      }
      identities.add(upload.uploadId);
    }
    return { schemaVersion: 1, uploads };
  }

  function write(document: NativeVitalUploadRegistryDocument): void {
    const tmpPath = `${statePath}.${process.pid}.${Date.now()}.tmp`;
    fs.writeFileSync(
      tmpPath,
      `${JSON.stringify(document, null, 2)}\n`,
      "utf8",
    );
    fs.renameSync(tmpPath, statePath);
  }

  return {
    get(uploadId: string): NativeVitalUploadRecord | null {
      return read().uploads.find((upload) => upload.uploadId === uploadId)
        || null;
    },
    list(): NativeVitalUploadRecord[] {
      return read().uploads.sort((left, right) => (
        right.receivedAt.localeCompare(left.receivedAt)
        || left.uploadId.localeCompare(right.uploadId)
      ));
    },
    save(record: NativeVitalUploadRecord): void {
      const validated = nativeVitalUploadRecordFromDocument(record);
      const document = read();
      const index = document.uploads.findIndex(
        (upload) => upload.uploadId === validated.uploadId,
      );
      if (index < 0) {
        document.uploads.push(validated);
      } else {
        const existing = document.uploads[index];
        assertImmutableMetadata(existing, validated);
        assertAllowedTransition(existing, validated);
        document.uploads[index] = validated;
      }
      write(document);
    },
  };
}

function assertImmutableMetadata(
  existing: NativeVitalUploadRecord,
  replacement: NativeVitalUploadRecord,
): void {
  const differs = (
    existing.bedName !== replacement.bedName
    || existing.declaredVrcode !== replacement.declaredVrcode
    || existing.filename !== replacement.filename
    || existing.declaredSizeBytes !== replacement.declaredSizeBytes
    || existing.receivedAt !== replacement.receivedAt
  );
  if (differs) {
    throw new TypeError(
      `native upload immutable metadata differs: uploadId=${existing.uploadId}`,
    );
  }
}

function assertAllowedTransition(
  existing: NativeVitalUploadRecord,
  replacement: NativeVitalUploadRecord,
): void {
  if (existing.state === replacement.state) return;
  const allowed = (
    existing.state === "receiving"
      && ["reconciling", "failed"].includes(replacement.state)
  ) || (
    existing.state === "reconciling"
      && ["indexed", "failed"].includes(replacement.state)
  );
  if (!allowed) {
    throw new TypeError(
      `native upload state transition is invalid: ${existing.state} -> ${replacement.state}`,
    );
  }
}

module.exports = { createNativeVitalUploadRegistry };

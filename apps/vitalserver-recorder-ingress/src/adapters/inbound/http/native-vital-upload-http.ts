import type { IncomingHttpHeaders } from "http";
import type {
  NativeVitalUploadMetadata,
} from "../../../domain/native-vital-upload";

"use strict";

const TRACKING_HEADERS = Object.freeze([
  "x-vital-upload-id",
  "x-vital-bed-name",
  "x-vital-recorder-code",
  "x-vital-filename",
  "x-vital-file-size",
]);

export function nativeVitalUploadMetadataFromHeaders(
  headers: IncomingHttpHeaders,
): NativeVitalUploadMetadata | null {
  const hasTrackingIntent = TRACKING_HEADERS.some(
    (header) => headers[header] !== undefined,
  );
  if (!hasTrackingIntent) return null;

  const uploadId = requiredHeader(headers, "x-vital-upload-id");
  const bedName = requiredHeader(headers, "x-vital-bed-name");
  const filename = requiredHeader(headers, "x-vital-filename");
  const fileSize = requiredHeader(headers, "x-vital-file-size");
  const declaredVrcode = optionalHeader(headers, "x-vital-recorder-code");

  if (uploadId.length > 128) {
    throw new TypeError("x-vital-upload-id exceeds 128 characters");
  }
  if (bedName.length > 128) {
    throw new TypeError("x-vital-bed-name exceeds 128 characters");
  }
  if (
    filename.length > 255
    || filename !== filename.split(/[\\/]/).pop()
    || !filename.toLowerCase().endsWith(".vital")
  ) {
    throw new TypeError("x-vital-filename must be a .vital basename");
  }
  const declaredSizeBytes = Number(fileSize);
  if (
    !/^[1-9][0-9]*$/.test(fileSize)
    || !Number.isSafeInteger(declaredSizeBytes)
  ) {
    throw new TypeError("x-vital-file-size must be a positive integer");
  }
  return {
    uploadId,
    bedName,
    declaredVrcode,
    filename,
    declaredSizeBytes,
  };
}

function requiredHeader(
  headers: IncomingHttpHeaders,
  name: string,
): string {
  const value = optionalHeader(headers, name);
  if (value === null) {
    throw new TypeError(`${name} is required for tracked native upload`);
  }
  return value;
}

function optionalHeader(
  headers: IncomingHttpHeaders,
  name: string,
): string | null {
  const value = headers[name];
  if (value === undefined) return null;
  if (Array.isArray(value)) {
    throw new TypeError(`${name} must appear exactly once`);
  }
  const normalized = String(value).trim();
  if (!normalized) {
    throw new TypeError(`${name} must not be empty`);
  }
  return normalized;
}

module.exports = { nativeVitalUploadMetadataFromHeaders };

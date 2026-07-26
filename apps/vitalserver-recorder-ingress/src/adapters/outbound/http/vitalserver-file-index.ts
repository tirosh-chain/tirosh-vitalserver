import type {
  NativeVitalUploadIndexPort,
} from "../../../application/ports/outbound/native-vital-upload-index-port";
import type {
  NativeVitalUploadIndexEvidence,
} from "../../../domain/native-vital-upload";

"use strict";

const zlib = require("zlib");

type VitalServerFileIndexConfig = {
  baseUrl: string;
  adminPassword: string;
  timeoutMs: number;
};

type FetchLike = (
  input: string | URL,
  init?: RequestInit,
) => Promise<Response>;

export function createVitalServerFileIndex(
  config: VitalServerFileIndexConfig,
  fetchImpl: FetchLike = fetch,
): NativeVitalUploadIndexPort {
  if (!config.baseUrl) {
    throw new TypeError("VitalServer file index baseUrl is required");
  }
  if (!config.adminPassword) {
    throw new TypeError("VitalServer file index adminPassword is required");
  }
  if (!Number.isInteger(config.timeoutMs) || config.timeoutMs <= 0) {
    throw new TypeError("VitalServer file index timeoutMs is invalid");
  }
  const baseUrl = config.baseUrl.replace(/\/+$/, "");

  return {
    async find(filename: string): Promise<NativeVitalUploadIndexEvidence | null> {
      const accessToken = await login();
      const response = await request(
        `${baseUrl}/api/filelist?access_token=${encodeURIComponent(accessToken)}&unixtimestamp=1`,
        { headers: { accept: "application/x-gzip, application/json" } },
      );
      if (response.status === 404) return null;
      if (!response.ok) {
        throw new Error(
          `VitalServer file index request failed: status=${response.status}`,
        );
      }
      const body = Buffer.from(await response.arrayBuffer());
      const decoded = isGzip(body) ? zlib.gunzipSync(body) : body;
      let document: unknown;
      try {
        document = JSON.parse(decoded.toString("utf8"));
      } catch (error) {
        throw new Error(
          `VitalServer file index returned invalid JSON: ${errorMessage(error)}`,
        );
      }
      if (!Array.isArray(document)) {
        throw new Error("VitalServer file index must be an array");
      }
      const matches = document.filter((item) => (
        item && typeof item === "object" && item.filename === filename
      ));
      if (matches.length === 0) return null;
      if (matches.length > 1) {
        throw new Error(
          `VitalServer file index contains duplicate filename=${filename}`,
        );
      }
      return indexEvidence(matches[0], filename);
    },
  };

  async function login(): Promise<string> {
    const response = await request(`${baseUrl}/api/login`, {
      method: "POST",
      headers: {
        accept: "application/json",
        "content-type": "application/json",
      },
      body: JSON.stringify({ id: "admin", pw: config.adminPassword }),
    });
    if (!response.ok) {
      throw new Error(
        `VitalServer file index login failed: status=${response.status}`,
      );
    }
    let document: unknown;
    try {
      document = await response.json();
    } catch (error) {
      throw new Error(
        `VitalServer file index login returned invalid JSON: ${errorMessage(error)}`,
      );
    }
    if (
      !document
      || typeof document !== "object"
      || typeof (document as { access_token?: unknown }).access_token !== "string"
      || !(document as { access_token: string }).access_token
    ) {
      throw new Error(
        "VitalServer file index login response lacks access_token",
      );
    }
    return (document as { access_token: string }).access_token;
  }

  async function request(url: string, init: RequestInit): Promise<Response> {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), config.timeoutMs);
    try {
      return await fetchImpl(url, { ...init, signal: controller.signal });
    } finally {
      clearTimeout(timeout);
    }
  }
}

function indexEvidence(
  item: Record<string, unknown>,
  filename: string,
): NativeVitalUploadIndexEvidence {
  if (!Number.isSafeInteger(item.filesize) || Number(item.filesize) < 0) {
    throw new Error(
      `VitalServer file index filesize is invalid: filename=${filename}`,
    );
  }
  return {
    filename,
    sizeBytes: Number(item.filesize),
    recordingStartedAt: optionalIndexValue(item.dtstart, "dtstart", filename),
    recordingEndedAt: optionalIndexValue(item.dtend, "dtend", filename),
    uploadedAt: optionalIndexValue(item.dtupload, "dtupload", filename),
  };
}

function optionalIndexValue(
  value: unknown,
  field: string,
  filename: string,
): number | string | null {
  if (value === undefined || value === null) return null;
  if (
    (typeof value === "number" && Number.isFinite(value))
    || (typeof value === "string" && value.length > 0)
  ) {
    return value;
  }
  throw new Error(
    `VitalServer file index ${field} is invalid: filename=${filename}`,
  );
}

function isGzip(body: Buffer): boolean {
  return body.length >= 2 && body[0] === 0x1f && body[1] === 0x8b;
}

function errorMessage(error: unknown): string {
  return error && typeof error === "object" && "message" in error
    ? String(error.message)
    : String(error);
}

module.exports = { createVitalServerFileIndex };

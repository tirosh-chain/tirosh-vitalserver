import type { IncomingMessage, ServerResponse } from "http";
import {
  recorderObservabilityResourceTypes,
  type RecorderObservabilityResourceType,
} from "../../../domain/recorder-observability";

"use strict";

type RecorderObservabilityRoute =
  | {
      kind: "valid";
      vrcode: string;
      resourceType: RecorderObservabilityResourceType;
    }
  | {
      kind: "invalid";
    };

type RecorderObservabilityIngress = {
  admit(input: {
    resourceType: RecorderObservabilityResourceType;
    vrcode: string;
    requestDeviceId: string;
    sourceIp: string;
    lines: Array<{
      lineNumber: number;
      rawDocument: string;
      document: unknown;
      parseFailure?: string;
    }>;
  }): Promise<unknown>;
};

type RecorderObservabilityMetrics = {
  requests: number;
  accepted: number;
  duplicates: number;
  quarantined: number;
  admissionFailures: number;
  lastAdmittedAt: string | null;
  lastFailure: {
    occurredAt: string;
    reason: string;
  } | null;
};

export function recorderObservabilityRoute(
  requestURL: string | undefined,
): RecorderObservabilityRoute | null {
  const pathname = new URL(
    requestURL || "/",
    "http://recorder-ingress",
  ).pathname;
  const match = pathname.match(
    /^\/api\/v1\/recorders\/([^/]+)\/(observations|diagnostic-events|kernel-incidents|profiles|boot-events)$/,
  );
  if (!match) {
    return pathname.startsWith("/api/v1/recorders/")
      ? { kind: "invalid" }
      : null;
  }
  let vrcode: string;
  try {
    vrcode = decodeURIComponent(match[1]);
  } catch (_error) {
    return { kind: "invalid" };
  }
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(vrcode)) {
    return { kind: "invalid" };
  }
  return {
    kind: "valid",
    vrcode,
    resourceType: recorderObservabilityResourceTypes[
      match[2] as keyof typeof recorderObservabilityResourceTypes
    ],
  };
}

export function receiveRecorderObservability(
  req: IncomingMessage,
  res: ServerResponse,
  {
    route,
    ingress,
    maxRequestBytes,
    sourceIp,
    metrics,
  }: {
    route: RecorderObservabilityRoute;
    ingress?: RecorderObservabilityIngress;
    maxRequestBytes: number;
    sourceIp: string;
    metrics?: RecorderObservabilityMetrics;
  },
): void {
  if (route.kind === "invalid") {
    req.resume();
    writeJson(res, 404, {
      state: "rejected",
      reason: "recorder_observability_path_invalid",
    });
    return;
  }
  if (req.method !== "POST") {
    req.resume();
    writeJson(res, 405, {
      state: "rejected",
      reason: "method_not_allowed",
    }, { allow: "POST" });
    return;
  }
  if (!ingress) {
    recordAdmissionRequest(metrics);
    recordAdmissionFailure(
      metrics,
      "recorder_observability_ingress_unavailable",
    );
    req.resume();
    writeJson(res, 503, {
      state: "failed",
      reason: "recorder_observability_ingress_unavailable",
    });
    return;
  }
  recordAdmissionRequest(metrics);
  if (mediaType(req.headers["content-type"]) !== "application/x-ndjson") {
    recordAdmissionFailure(metrics, "content_type_invalid");
    req.resume();
    writeJson(res, 415, {
      state: "rejected",
      reason: "content_type_invalid",
    });
    return;
  }
  const requestDeviceId = singleHeader(req.headers["x-device-id"]);
  if (!requestDeviceId || !validRequestIdentity(requestDeviceId)) {
    recordAdmissionFailure(metrics, "device_id_header_invalid");
    req.resume();
    writeJson(res, 400, {
      state: "rejected",
      reason: "device_id_header_invalid",
    });
    return;
  }

  const chunks: Buffer[] = [];
  let bytes = 0;
  let tooLarge = false;
  req.on("data", (chunk) => {
    bytes += chunk.length;
    if (bytes > maxRequestBytes) {
      tooLarge = true;
      return;
    }
    chunks.push(chunk);
  });
  req.on("error", (error) => {
    if (res.writableEnded) return;
    recordAdmissionFailure(metrics, "request_read_failed");
    writeJson(res, 400, {
      state: "rejected",
      reason: "request_read_failed",
      message: errorMessage(error),
    });
  });
  req.on("end", async () => {
    if (res.writableEnded) return;
    if (tooLarge) {
      recordAdmissionFailure(metrics, "request_too_large");
      writeJson(res, 413, {
        state: "rejected",
        reason: "request_too_large",
        maxRequestBytes,
      });
      return;
    }
    let lines;
    try {
      lines = parseNDJSON(Buffer.concat(chunks).toString("utf8"));
    } catch (error) {
      recordAdmissionFailure(metrics, "ndjson_framing_invalid");
      writeJson(res, 400, {
        state: "rejected",
        reason: "ndjson_framing_invalid",
        message: errorMessage(error),
      });
      return;
    }
    try {
      const result = await ingress.admit({
        resourceType: route.resourceType,
        vrcode: route.vrcode,
        requestDeviceId,
        sourceIp,
        lines,
      });
      recordAdmissionSuccess(
        metrics,
        result as {
          accepted: number;
          duplicates: number;
          quarantined: number;
        },
      );
      writeJson(res, 202, result);
    } catch (error) {
      recordAdmissionFailure(metrics, "durable_admission_failed");
      writeJson(res, 503, {
        state: "failed",
        reason: "durable_admission_failed",
        message: errorMessage(error),
      });
    }
  });
}

export function parseNDJSON(value: string): Array<{
  lineNumber: number;
  rawDocument: string;
  document: unknown;
  parseFailure?: string;
}> {
  const records = [];
  for (const [index, line] of value.split(/\r?\n/).entries()) {
    const rawDocument = line.trim();
    if (!rawDocument) continue;
    let document: unknown = null;
    let parseFailure: string | undefined;
    try {
      document = JSON.parse(rawDocument);
    } catch (error) {
      parseFailure = errorMessage(error);
    }
    records.push({
      lineNumber: index + 1,
      rawDocument,
      document,
      ...(parseFailure ? { parseFailure } : {}),
    });
  }
  if (records.length === 0) {
    throw new TypeError("request contains no JSON documents");
  }
  return records;
}

function mediaType(value: string | undefined): string {
  return typeof value === "string"
    ? value.split(";", 1)[0].trim().toLowerCase()
    : "";
}

function singleHeader(value: string | string[] | undefined): string | null {
  return typeof value === "string" ? value : null;
}

function validRequestIdentity(value: string): boolean {
  return (
    value.length > 0
    && value.length <= 128
    && value.trim() === value
    && !/[\u0000-\u001f\u007f]/.test(value)
  );
}

function writeJson(
  res: ServerResponse,
  statusCode: number,
  document: unknown,
  headers: Record<string, string> = {},
): void {
  const body = JSON.stringify(document);
  res.writeHead(statusCode, {
    ...headers,
    "content-type": "application/json",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

function errorMessage(error: unknown): string {
  return error && typeof error === "object" && "message" in error
    ? String(error.message)
    : String(error);
}

function recordAdmissionRequest(
  metrics: RecorderObservabilityMetrics | undefined,
): void {
  if (metrics) metrics.requests += 1;
}

function recordAdmissionSuccess(
  metrics: RecorderObservabilityMetrics | undefined,
  result: {
    accepted: number;
    duplicates: number;
    quarantined: number;
  },
): void {
  if (!metrics) return;
  metrics.accepted += result.accepted;
  metrics.duplicates += result.duplicates;
  metrics.quarantined += result.quarantined;
  metrics.lastAdmittedAt = new Date().toISOString();
}

function recordAdmissionFailure(
  metrics: RecorderObservabilityMetrics | undefined,
  reason: string,
): void {
  if (!metrics) return;
  metrics.admissionFailures += 1;
  metrics.lastFailure = {
    occurredAt: new Date().toISOString(),
    reason,
  };
}

module.exports = {
  parseNDJSON,
  receiveRecorderObservability,
  recorderObservabilityRoute,
};

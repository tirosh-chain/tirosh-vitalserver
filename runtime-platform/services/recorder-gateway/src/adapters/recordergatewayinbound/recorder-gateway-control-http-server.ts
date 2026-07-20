import { createServer, type IncomingMessage, type ServerResponse } from "node:http";

import type { RecorderGatewayIngressAndColdPathApplicationService } from "../../recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-service.js";
import {
  isRecorderGatewayIdentifier,
  recorderGatewaySchemaVersion,
  type RecorderColdPathCaptureFinalizationCommand,
} from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";

export function createRecorderGatewayControlHTTPServer(service: RecorderGatewayIngressAndColdPathApplicationService) {
  return createServer((request, response) => {
    void handleRecorderGatewayControlRequest(service, request, response).catch(() => {
      if (!response.headersSent) {
        writeJson(response, 500, {
          schemaVersion: recorderGatewaySchemaVersion,
          state: "failed",
          issue: {
            code: "recorder-gateway-control-http-adapter-failed",
            message: "Recorder Gateway control HTTP adapter could not complete the request",
            retryable: true,
            dependency: "recorder-gateway-control-http",
          },
        });
      }
    });
  });
}

async function handleRecorderGatewayControlRequest(
  service: RecorderGatewayIngressAndColdPathApplicationService,
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  const url = new URL(request.url ?? "/", "http://gateway.local");
  if (request.method === "GET") {
    const ingressReceiptID = readRecorderGatewayControlPathIdentifier(url.pathname, "/v1/recorder-ingress/receipts/");
    if (ingressReceiptID !== undefined) {
      writeJson(response, 200, await service.readRecorderIngressReceipt(ingressReceiptID));
      return;
    }
    const deliveryReceiptID = readRecorderGatewayControlPathIdentifier(url.pathname, "/v1/recorder-ingress/delivery-receipts/");
    if (deliveryReceiptID !== undefined) {
      writeJson(response, 200, await service.readVitalServerDeliveryReceipt(deliveryReceiptID));
      return;
    }
    const coldPathCaptureID = readRecorderGatewayControlPathIdentifier(url.pathname, "/v1/recorder-cold-path/captures/");
    const coldPathPacketSequenceCaptureID = readRecorderGatewayControlPacketSequenceCaptureIdentifier(url.pathname);
    if (coldPathPacketSequenceCaptureID !== undefined) {
      if (!isLoopbackRecorderGatewayControlClient(request)) {
        writeJson(response, 403, recorderGatewayControlAccessDenied());
        return;
      }
      const sequence = await service.readRecorderColdPathPacketSequence(coldPathPacketSequenceCaptureID);
      if (sequence.state !== "available" || sequence.value === undefined) {
        writeJson(response, 200, sequence);
        return;
      }
      writeRecorderColdPathPacketSequence(response, sequence.value);
      return;
    }
    if (coldPathCaptureID !== undefined) {
      if (!isLoopbackRecorderGatewayControlClient(request)) {
        writeJson(response, 403, recorderGatewayControlAccessDenied());
        return;
      }
      writeJson(response, 200, await service.readRecorderColdPathCapture(coldPathCaptureID));
      return;
    }
    const coldPathFinalizationReceiptID = readRecorderGatewayControlPathIdentifier(url.pathname, "/v1/recorder-cold-path/finalization-receipts/");
    if (coldPathFinalizationReceiptID !== undefined) {
      if (!isLoopbackRecorderGatewayControlClient(request)) {
        writeJson(response, 403, recorderGatewayControlAccessDenied());
        return;
      }
      writeJson(response, 200, await service.readRecorderColdPathCaptureFinalizationReceipt(coldPathFinalizationReceiptID));
      return;
    }
  }
  if (request.method === "POST") {
    const coldPathCaptureID = readRecorderGatewayControlFinalizationCaptureIdentifier(url.pathname);
    if (coldPathCaptureID !== undefined) {
      if (!isLoopbackRecorderGatewayControlClient(request)) {
        writeJson(response, 403, recorderGatewayControlAccessDenied());
        return;
      }
      await executeRecorderColdPathCaptureFinalization(service, coldPathCaptureID, request, response);
      return;
    }
  }
  writeJson(response, 404, { error: "Recorder Gateway control route is not implemented" });
}

async function executeRecorderColdPathCaptureFinalization(
  service: RecorderGatewayIngressAndColdPathApplicationService,
  pathCaptureID: string,
  request: IncomingMessage,
  response: ServerResponse,
): Promise<void> {
  let body: unknown;
  try {
    body = await readRecorderGatewayControlJsonBody(request);
  } catch {
    writeJson(response, 400, recorderGatewayControlCommandRejection(undefined, "invalid-recorder-cold-path-finalization-command", "request body must be valid JSON no larger than 64 KiB"));
    return;
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    writeJson(response, 400, recorderGatewayControlCommandRejection(undefined, "invalid-recorder-cold-path-finalization-command", "request body must be a JSON object"));
    return;
  }
  const command = body as RecorderColdPathCaptureFinalizationCommand;
  if (command.coldPathCaptureId !== pathCaptureID) {
    writeJson(response, 400, recorderGatewayControlCommandRejection(command.requestId, "cold-path-capture-path-command-mismatch", "path capture id and command coldPathCaptureId must match"));
    return;
  }
  const result = await service.finalizeRecorderColdPathCapture(command);
  if (result.state === "finalized") {
    writeJson(response, 201, result.receipt);
    return;
  }
  if (result.state === "rejected") {
    writeJson(response, 400, recorderGatewayControlCommandRejection(command.requestId, result.issue?.code ?? "recorder-cold-path-finalization-rejected", result.issue?.message ?? "Recorder Cold-Path Capture finalization was rejected"));
    return;
  }
  writeJson(response, 503, {
    schemaVersion: recorderGatewaySchemaVersion,
    state: "failed",
    requestId: command.requestId,
    observedAt: result.observedAt,
    admissionState: result.admissionState ?? "unknown",
    issue: result.issue ?? {
      code: "recorder-cold-path-finalization-result-invalid",
      message: "Recorder Gateway did not return a complete cold-path finalization result",
      retryable: true,
      dependency: "recorder-gateway",
    },
  });
}

function readRecorderGatewayControlPathIdentifier(path: string, prefix: string): string | undefined {
  if (!path.startsWith(prefix)) {
    return undefined;
  }
  const identifier = path.slice(prefix.length);
  if (identifier === "" || identifier.includes("/")) {
    return "invalid";
  }
  try {
    return decodeURIComponent(identifier);
  } catch {
    return "invalid";
  }
}

function readRecorderGatewayControlFinalizationCaptureIdentifier(path: string): string | undefined {
  const prefix = "/v1/recorder-cold-path/captures/";
  const suffix = ":finalize";
  if (!path.startsWith(prefix) || !path.endsWith(suffix)) {
    return undefined;
  }
  const identifier = path.slice(prefix.length, -suffix.length);
  if (identifier === "" || identifier.includes("/")) {
    return "invalid";
  }
  try {
    return decodeURIComponent(identifier);
  } catch {
    return "invalid";
  }
}

function readRecorderGatewayControlPacketSequenceCaptureIdentifier(path: string): string | undefined {
  const prefix = "/v1/recorder-cold-path/captures/";
  const suffix = ":packet-sequence";
  if (!path.startsWith(prefix) || !path.endsWith(suffix)) {
    return undefined;
  }
  const identifier = path.slice(prefix.length, -suffix.length);
  if (identifier === "" || identifier.includes("/")) {
    return "invalid";
  }
  try {
    return decodeURIComponent(identifier);
  } catch {
    return "invalid";
  }
}

async function readRecorderGatewayControlJsonBody(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let byteCount = 0;
  for await (const chunk of request) {
    const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    byteCount += bytes.byteLength;
    if (byteCount > 64 * 1024) {
      throw new Error("Recorder Gateway control request body exceeds 64 KiB");
    }
    chunks.push(bytes);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
  } catch {
    throw new Error("Recorder Gateway control request body is not valid JSON");
  }
}

function isLoopbackRecorderGatewayControlClient(request: IncomingMessage): boolean {
  const address = request.socket.remoteAddress;
  return address === "127.0.0.1" || address === "::1" || address === "::ffff:127.0.0.1";
}

function recorderGatewayControlAccessDenied(): object {
  return {
    schemaVersion: recorderGatewaySchemaVersion,
    state: "rejected",
    issue: {
      code: "recorder-gateway-control-loopback-required",
      message: "Recorder Gateway cold-path control routes require a Guest-loopback client",
      retryable: false,
      dependency: "recorder-gateway-control-http",
    },
  };
}

function recorderGatewayControlCommandRejection(requestId: unknown, code: string, message: string): object {
  return {
    schemaVersion: recorderGatewaySchemaVersion,
    state: "rejected",
    requestId: typeof requestId === "string" && isRecorderGatewayIdentifier(requestId) ? requestId : undefined,
    issue: { code, message, retryable: false, dependency: "recorder-gateway" },
  };
}

function writeJson(response: ServerResponse, status: number, value: unknown): void {
  response.statusCode = status;
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.end(`${JSON.stringify(value)}\n`);
}

function writeRecorderColdPathPacketSequence(response: ServerResponse, value: Uint8Array): void {
  response.statusCode = 200;
  response.setHeader("content-type", "application/vnd.tirosh.recorder-gateway.cold-path-packet-sequence+jsonl");
  response.setHeader("content-length", value.byteLength.toString());
  response.setHeader("cache-control", "no-store");
  response.end(value);
}

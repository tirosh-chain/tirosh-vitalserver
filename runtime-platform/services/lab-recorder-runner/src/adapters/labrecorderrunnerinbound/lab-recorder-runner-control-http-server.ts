import { createServer, type IncomingMessage, type ServerResponse } from "node:http";

import type { LabRecorderRunnerApplicationService } from "../../labrecorderrunnerapplication/lab-recorder-runner-application-service.js";
import type { LabScenarioCatalog } from "../labscenariocatalogfile/lab-scenario-catalog-file.js";
import { labRecorderRunnerSchemaVersion } from "../../labrecorderrunnerdomain/lab-recorder-run-contracts.js";

interface StartRequest {
  schemaVersion?: unknown;
  requestId?: unknown;
  virtualRecorderId?: unknown;
  recorderGatewayRecorderCode?: unknown;
  scenarioId?: unknown;
}

export function createLabRecorderRunnerControlHTTPServer(service: LabRecorderRunnerApplicationService, catalog: LabScenarioCatalog) {
  return createServer((request, response) => {
    void handleControlRequest(service, catalog, request, response).catch(() => {
      if (!response.headersSent) {
        writeJSON(response, 500, failed("lab-recorder-runner-control-http-adapter-failed", "Lab recorder Runner control HTTP adapter could not complete the request"));
      }
    });
  });
}

async function handleControlRequest(service: LabRecorderRunnerApplicationService, catalog: LabScenarioCatalog, request: IncomingMessage, response: ServerResponse): Promise<void> {
  if (!isLoopbackClient(request)) {
    writeJSON(response, 403, rejected("lab-recorder-runner-control-loopback-required", "Lab recorder Runner control requires a Guest-loopback client"));
    return;
  }
  const url = new URL(request.url ?? "/", "http://lab-recorder-runner.local");
  if (request.method === "POST" && url.pathname === "/v1/lab-recorder-runs") {
    await startRun(service, catalog, request, response);
    return;
  }
  const runID = runIDForStopPath(url.pathname);
  if (request.method === "POST" && runID !== undefined) {
    await stopRun(service, runID, request, response);
    return;
  }
  const readRunID = runIDForReadPath(url.pathname);
  if (request.method === "GET" && readRunID !== undefined) {
    const result = service.readLabRecorderRun(readRunID);
    writeJSON(response, 200, {
      schemaVersion: labRecorderRunnerSchemaVersion,
      state: result.state,
      observedAt: new Date().toISOString(),
      ...(result.state === "available" ? { value: result.value } : { issue: result.issue }),
    });
    return;
  }
  writeJSON(response, 404, rejected("lab-recorder-runner-control-route-not-found", "Lab recorder Runner control route is not implemented"));
}

async function startRun(service: LabRecorderRunnerApplicationService, catalog: LabScenarioCatalog, request: IncomingMessage, response: ServerResponse): Promise<void> {
  const decoded = await decodeJSONBody(request, response);
  if (decoded === undefined) {
    return;
  }
  if (!isRecord(decoded)) {
    writeJSON(response, 400, rejected("invalid-lab-recorder-run-command", "Lab recorder run command must be a JSON object"));
    return;
  }
  const command = decoded as StartRequest;
  if (typeof command.scenarioId !== "string") {
    writeJSON(response, 400, rejected("invalid-lab-recorder-scenario", "scenarioId must be a string"));
    return;
  }
  const scenario = catalog.find(command.scenarioId);
  if (scenario === undefined) {
    writeJSON(response, 400, rejected("lab-scenario-not-configured", "scenarioId is not present in the declared Lab scenario catalog"));
    return;
  }
  const result = await service.startLabRecorderRun({
    schemaVersion: stringValue(command.schemaVersion),
    requestId: stringValue(command.requestId),
    virtualRecorderId: stringValue(command.virtualRecorderId),
    recorderGatewayRecorderCode: stringValue(command.recorderGatewayRecorderCode),
    scenario,
  });
  if (result.state === "running") {
    writeJSON(response, 201, result.run);
    return;
  }
  writeJSON(response, result.state === "rejected" ? 400 : 503, {
    schemaVersion: labRecorderRunnerSchemaVersion,
    state: result.state,
    issue: result.issue,
  });
}

async function stopRun(service: LabRecorderRunnerApplicationService, runID: string, request: IncomingMessage, response: ServerResponse): Promise<void> {
  const decoded = await decodeJSONBody(request, response);
  if (decoded === undefined) {
    return;
  }
  if (!isRecord(decoded)) {
    writeJSON(response, 400, rejected("invalid-lab-recorder-stop-command", "Lab recorder stop command must be a JSON object"));
    return;
  }
  const result = await service.stopLabRecorderRun(runID, {
    schemaVersion: stringValue(decoded.schemaVersion),
    requestId: stringValue(decoded.requestId),
    expectedRunRevision: typeof decoded.expectedRunRevision === "number" ? decoded.expectedRunRevision : 0,
  });
  if (result.state === "finalized") {
    writeJSON(response, 201, result.run);
    return;
  }
  writeJSON(response, result.state === "rejected" ? 400 : 503, {
    schemaVersion: labRecorderRunnerSchemaVersion,
    state: result.state,
    issue: result.issue,
  });
}

async function decodeJSONBody(request: IncomingMessage, response: ServerResponse): Promise<unknown | undefined> {
  const chunks: Buffer[] = [];
  let byteCount = 0;
  try {
    for await (const chunk of request) {
      const bytes = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      byteCount += bytes.byteLength;
      if (byteCount > 64 * 1024) {
        throw new Error("body too large");
      }
      chunks.push(bytes);
    }
    return JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
  } catch {
    writeJSON(response, 400, rejected("invalid-lab-recorder-runner-command", "request body must be valid JSON no larger than 64 KiB"));
    return undefined;
  }
}

function runIDForStopPath(path: string): string | undefined {
  return readPathIdentifier(path, "/v1/lab-recorder-runs/", ":stop");
}

function runIDForReadPath(path: string): string | undefined {
  return readPathIdentifier(path, "/v1/lab-recorder-runs/", "");
}

function readPathIdentifier(path: string, prefix: string, suffix: string): string | undefined {
  if (!path.startsWith(prefix) || (suffix !== "" && !path.endsWith(suffix))) {
    return undefined;
  }
  const value = path.slice(prefix.length, suffix === "" ? undefined : -suffix.length);
  if (value === "" || value.includes("/")) {
    return "invalid";
  }
  try {
    return decodeURIComponent(value);
  } catch {
    return "invalid";
  }
}

function isLoopbackClient(request: IncomingMessage): boolean {
  return request.socket.remoteAddress === "127.0.0.1" || request.socket.remoteAddress === "::1" || request.socket.remoteAddress === "::ffff:127.0.0.1";
}

function writeJSON(response: ServerResponse, status: number, value: unknown): void {
  response.statusCode = status;
  response.setHeader("content-type", "application/json; charset=utf-8");
  response.setHeader("cache-control", "no-store");
  response.end(`${JSON.stringify(value)}\n`);
}

function rejected(code: string, message: string): object {
  return { schemaVersion: labRecorderRunnerSchemaVersion, state: "rejected", issue: { code, message, retryable: false, dependency: "lab-recorder-runner" } };
}

function failed(code: string, message: string): object {
  return { schemaVersion: labRecorderRunnerSchemaVersion, state: "failed", issue: { code, message, retryable: true, dependency: "lab-recorder-runner" } };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

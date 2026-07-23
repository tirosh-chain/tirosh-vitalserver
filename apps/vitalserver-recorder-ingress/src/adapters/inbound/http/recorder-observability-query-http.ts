import type { IncomingMessage, ServerResponse } from "http";
import type { RecorderObservabilityRepositoryPort } from "../../../application/ports/outbound/recorder-observability-repository-port";
import { mapRecorderObservabilityDetail } from "../../../domain/recorder-observability-detail";

export function recorderObservabilityQueryRoute(
  requestURL: string | undefined,
):
  | { kind: "list" }
  | { kind: "detail"; vrcode: string }
  | { kind: "invalid" }
  | null {
  const pathname = new URL(requestURL || "/", "http://recorder-ingress").pathname;
  if (pathname === "/runtime/vitaldb/recorders") return { kind: "list" };
  const match = pathname.match(
    /^\/runtime\/vitaldb\/recorders\/([^/]+)\/observability$/,
  );
  if (!match) {
    return pathname.startsWith("/runtime/vitaldb/recorders/")
      ? { kind: "invalid" }
      : null;
  }
  try {
    const vrcode = decodeURIComponent(match[1]);
    return /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/.test(vrcode)
      ? { kind: "detail", vrcode }
      : { kind: "invalid" };
  } catch (_error) {
    return { kind: "invalid" };
  }
}

export async function readRecorderObservabilityQuery(
  req: IncomingMessage,
  res: ServerResponse,
  route: ReturnType<typeof recorderObservabilityQueryRoute>,
  repository?: RecorderObservabilityRepositoryPort,
): Promise<void> {
  req.resume();
  if (!route || route.kind === "invalid") {
    writeJson(res, 404, { state: "not_found" });
    return;
  }
  if (req.method !== "GET") {
    writeJson(res, 405, { state: "rejected", reason: "method_not_allowed" });
    return;
  }
  if (!repository) {
    writeJson(res, 503, {
      state: "failed",
      reason: "recorder_observability_repository_unavailable",
    });
    return;
  }
  try {
    if (route.kind === "list") {
      const recorders = await repository.listCurrentRecorders();
      writeJson(res, 200, { state: "loaded", recorders });
      return;
    }
    const rows = await repository.readRecorderObservability(route.vrcode);
    if (rows.length === 0) {
      writeJson(res, 404, { state: "not_found", vrcode: route.vrcode });
      return;
    }
    const row = rows[0];
    writeJson(res, 200, mapRecorderObservabilityDetail(row));
  } catch (error) {
    writeJson(res, 503, {
      state: "failed",
      reason: "recorder_observability_query_failed",
      message: errorMessage(error),
    });
  }
}

function writeJson(
  res: ServerResponse,
  statusCode: number,
  value: unknown,
): void {
  const body = JSON.stringify(value);
  res.writeHead(statusCode, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

module.exports = {
  readRecorderObservabilityQuery,
  recorderObservabilityQueryRoute,
};

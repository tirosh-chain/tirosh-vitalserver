import type { IncomingMessage, ServerResponse } from "http";
import type { RecorderObservabilityRepositoryPort } from "../../../application/ports/outbound/recorder-observability-repository-port";
import { mapRecorderObservabilityDetail } from "../../../domain/recorder-observability-detail";
import {
  incidentsDocument,
  parseRecorderObservabilityHistoryRoute,
  timelineDocument,
} from "../../../domain/recorder-observability-history";

export function recorderObservabilityQueryRoute(
  requestURL: string | undefined,
) {
  return parseRecorderObservabilityHistoryRoute(requestURL);
}

export async function readRecorderObservabilityQuery(
  req: IncomingMessage,
  res: ServerResponse,
  route: ReturnType<typeof recorderObservabilityQueryRoute>,
  repository?: RecorderObservabilityRepositoryPort,
): Promise<void> {
  req.resume();
  if (!route) {
    writeJson(res, 404, { state: "not_found" });
    return;
  }
  if (route.kind === "invalid") {
    writeJson(res, route.reason === "path_invalid" ? 404 : 400, {
      state: "invalidRequest",
      reason: route.reason,
    });
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
    if (route.kind === "timeline") {
      const readModel = await repository.readRecorderObservabilityTimeline(
        route.query,
      );
      writeJson(res, 200, timelineDocument(route.query, readModel));
      return;
    }
    if (route.kind === "incidents") {
      const rows = await repository.readRecorderObservabilityIncidents(
        route.query,
      );
      writeJson(res, 200, incidentsDocument(route.query, rows));
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

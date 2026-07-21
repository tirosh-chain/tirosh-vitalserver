import type {
  SendDataRawArchiveExporterPort,
  SendDataRawArchiveExportRequest,
} from "../../../application/ports/outbound/send-data-raw-archive-recovery-executor-port";

"use strict";

function createRawArchiveExporter(config): SendDataRawArchiveExporterPort {
  const settings = config && config.rawArchive && config.rawArchive.autoExport
    ? config.rawArchive.autoExport
    : {};
  const exportUrl = settings.exportUrl || "";

  return {
    async export(request: SendDataRawArchiveExportRequest) {
      if (!exportUrl) {
        return {
          ok: false,
          reason: "not_configured",
          message: "raw archive export endpoint is not configured",
        };
      }
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), request.timeoutMs);
        let response;
        try {
          response = await fetch(exportUrl, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              rawArchivePath: request.rawArchivePath,
              outputDir: request.outputDir,
              vrcode: request.vrcode,
              startOffset: request.startOffset,
              endOffset: request.endOffset,
            }),
            signal: controller.signal,
          });
        } finally {
          clearTimeout(timeout);
        }
        const body = await responseTextOrJson(response);
        if (!response.ok) {
          return {
            ok: false,
            reason: "http_failed",
            message: `raw archive export failed with HTTP ${response.status}`,
            statusCode: response.status,
            response: body,
          };
        }
        if (!isExportResponseDocument(body)) {
          return {
            ok: false,
            reason: "invalid_response",
            message: "raw archive export response did not match the artifact receipt contract",
            statusCode: response.status,
            response: body,
          };
        }
        return {
          ok: true,
          statusCode: response.status,
          artifacts: body.artifacts,
          response: body,
        };
      } catch (error) {
        return {
          ok: false,
          reason: "request_failed",
          message: error && error.message ? error.message : "raw archive export request failed",
        };
      }
    },
  };
}

async function responseTextOrJson(response) {
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_error) {
    return text;
  }
}

function isExportResponseDocument(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  if (value.operation !== "export" || !Array.isArray(value.artifacts)) return false;
  return value.artifacts.length > 0 && value.artifacts.every(isArtifactReceipt);
}

function isArtifactReceipt(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  return typeof value.artifactId === "string" && value.artifactId.length > 0
    && (value.origin === "coldPathRecovery" || value.origin === "productLabGenerated")
    && typeof value.producer === "string" && value.producer.length > 0
    && typeof value.writerVersion === "string" && value.writerVersion.length > 0
    && typeof value.vrcode === "string" && value.vrcode.length > 0
    && Array.isArray(value.roomNames) && value.roomNames.every((room) => typeof room === "string" && room.length > 0)
    && typeof value.sourceArchiveId === "string" && value.sourceArchiveId.length > 0
    && Number.isInteger(value.sourceStartOffset) && value.sourceStartOffset >= 0
    && Number.isInteger(value.sourceEndOffset) && value.sourceEndOffset >= value.sourceStartOffset
    && Number.isFinite(value.coverageStartedAt)
    && Number.isFinite(value.coverageEndedAt)
    && value.coverageEndedAt >= value.coverageStartedAt
    && value.formatVersion === 3
    && typeof value.sha256 === "string" && /^[0-9a-f]{64}$/.test(value.sha256)
    && typeof value.filename === "string" && value.filename.endsWith(".vital")
    && Number.isInteger(value.sizeBytes) && value.sizeBytes > 0
    && Number.isFinite(value.createdAt)
    && Number.isInteger(value.trackCount) && value.trackCount > 0;
}

module.exports = { createRawArchiveExporter };

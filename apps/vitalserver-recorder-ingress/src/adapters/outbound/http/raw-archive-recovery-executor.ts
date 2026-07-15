import type {
  SendDataRawArchiveRecoveryExecutorPort,
  SendDataRawArchiveRecoveryRequest,
} from "../../../application/ports/outbound/send-data-raw-archive-recovery-executor-port";

"use strict";

function createRawArchiveRecoveryExecutor(config): SendDataRawArchiveRecoveryExecutorPort {
  const settings = config && config.rawArchive && config.rawArchive.autoExport
    ? config.rawArchive.autoExport
    : {};
  const recoverUrl = settings.recoverUrl || "";

  return {
    async recover(request: SendDataRawArchiveRecoveryRequest) {
      if (!recoverUrl) {
        return {
          ok: false,
          reason: "not_configured",
          message: "raw archive recovery endpoint is not configured",
        };
      }
      try {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), request.timeoutMs);
        let response;
        try {
          response = await fetch(recoverUrl, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              rawArchivePath: request.rawArchivePath,
              outputDir: request.outputDir,
              vitalserverUrl: request.vitalserverUrl,
              endpoint: request.endpoint,
              timeout: Math.max(1, Math.floor(request.timeoutMs / 1000)),
              skipFilenameCheck: true,
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
            message: `raw archive recovery failed with HTTP ${response.status}`,
            statusCode: response.status,
            response: body,
          };
        }
        if (!isRecoveryResponseDocument(body)) {
          return {
            ok: false,
            reason: "invalid_response",
            message: "raw archive recovery response did not match the recovery result contract",
            statusCode: response.status,
            response: body,
          };
        }
        return { ok: true, statusCode: response.status, response: body };
      } catch (error) {
        return {
          ok: false,
          reason: "request_failed",
          message: error && error.message ? error.message : "raw archive recovery request failed",
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

function isRecoveryResponseDocument(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  if (!Array.isArray(value.artifacts)) return false;
  if (!value.upload || typeof value.upload !== "object" || Array.isArray(value.upload)) return false;
  return Number.isFinite(value.upload.totalRequests)
    && Number.isFinite(value.upload.successfulRequests)
    && Number.isFinite(value.upload.failedRequests);
}

module.exports = { createRawArchiveRecoveryExecutor };

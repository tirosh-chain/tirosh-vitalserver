import type {
  SendDataRawArchiveRecoveryExecutorPort,
  SendDataRawArchiveRecoveryRequest,
} from "../../../application/ports/outbound/send-data-raw-archive-recovery-executor-port";

"use strict";

function createTestkitRawArchiveRecoveryExecutor(config): SendDataRawArchiveRecoveryExecutorPort {
  const settings = config && config.rawArchive && config.rawArchive.autoExport
    ? config.rawArchive.autoExport
    : {};
  const recoverUrl = settings.recoverUrl || "http://testkit:18322/raw-archive/recover-vital";

  return {
    async recover(request: SendDataRawArchiveRecoveryRequest) {
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
            message: `testkit raw archive recovery failed with HTTP ${response.status}`,
            statusCode: response.status,
            response: body,
          };
        }
        return { ok: true, statusCode: response.status, response: body };
      } catch (error) {
        return {
          ok: false,
          reason: "request_failed",
          message: error && error.message ? error.message : "testkit raw archive recovery request failed",
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

module.exports = { createTestkitRawArchiveRecoveryExecutor };

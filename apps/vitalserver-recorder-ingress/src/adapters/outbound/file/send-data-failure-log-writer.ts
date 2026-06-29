import type { SendDataFailureLogEvent, SendDataFailureSinkPort } from "../../../application/ports/outbound/send-data-failure-sink-port";

"use strict";

const fs = require("fs");
const path = require("path");

function createSendDataFailureLogWriter(config, metrics): SendDataFailureSinkPort {
  const settings = config || { enabled: false, path: "" };
  if (settings.enabled) {
    ensureLogDirectory(settings.path);
  }

  return {
    record(event: SendDataFailureLogEvent) {
      if (!settings.enabled) return;
      try {
        fs.appendFileSync(settings.path, `${JSON.stringify(event)}\n`, "utf8");
      } catch (error) {
        metrics.failureLogWriteFailures += 1;
        console.error(
          "[recorder-ingress] send_data failure log write failed:",
          error && error.message ? error.message : String(error)
        );
      }
    },
  };
}

function ensureLogDirectory(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

module.exports = { createSendDataFailureLogWriter };

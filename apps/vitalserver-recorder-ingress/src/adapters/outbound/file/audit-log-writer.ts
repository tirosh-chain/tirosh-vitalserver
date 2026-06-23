import type { AuditSinkPort } from "../../../application/ports/outbound/audit-sink-port";

"use strict";

const fs = require("fs");
const path = require("path");
const { formatAuditLogLine } = require("./audit-log-format");

function createAuditLogWriter(config, metrics): AuditSinkPort {
  ensureLogDirectory(config.path);

  return {
    write(event) {
      if (!config.enabled) return;
      fs.appendFile(config.path, formatAuditLogLine(event, config.format), (error) => {
        if (error) {
          metrics.auditFileWriteFailures += 1;
          console.error("[recorder-ingress] audit file write failed:", error.message);
        }
      });
    },
  };
}

function ensureLogDirectory(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

module.exports = { createAuditLogWriter };

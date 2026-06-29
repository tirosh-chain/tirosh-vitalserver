import type { AuditSinkPort } from "../../../application/ports/outbound/audit-sink-port";

"use strict";

const { formatAuditLogLine } = require("../file/audit-log-format");

function createAuditStdoutWriter(config, metrics, output = process.stdout): AuditSinkPort {
  return {
    write(event) {
      if (!config.enabled) return;
      output.write(formatAuditLogLine(event, config.format), (error) => {
        if (error) {
          metrics.auditStdoutWriteFailures += 1;
          console.error("[recorder-ingress] audit stdout write failed:", error.message);
        }
      });
    },
  };
}

module.exports = { createAuditStdoutWriter };

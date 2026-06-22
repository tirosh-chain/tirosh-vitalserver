"use strict";

const { mask } = require("./redaction-policy");

function createAuditEnvelope(eventType, fields, now = new Date()) {
  return {
    schema_version: 1,
    source: "vitalserver-recorder-ingress",
    event_type: eventType,
    ts: now.toISOString(),
    ts_unix_ms: now.getTime(),
    ...mask(fields || {}),
  };
}

module.exports = { createAuditEnvelope };

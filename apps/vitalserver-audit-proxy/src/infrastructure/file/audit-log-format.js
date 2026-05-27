"use strict";

function formatAuditLogLine(event, format) {
  if (format === "logfmt") return `${toLogfmt(event)}\n`;
  return `${JSON.stringify(event)}\n`;
}

function toLogfmt(event) {
  return Object.keys(event)
    .sort()
    .map((key) => `${key}=${formatLogfmtValue(event[key])}`)
    .join(" ");
}

function formatLogfmtValue(value) {
  if (value == null) return "";
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (typeof value === "object") return quoteLogfmt(JSON.stringify(value));
  const text = String(value);
  return /^[A-Za-z0-9_./:@-]+$/.test(text) ? text : quoteLogfmt(text);
}

function quoteLogfmt(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;
}

module.exports = { formatAuditLogLine };

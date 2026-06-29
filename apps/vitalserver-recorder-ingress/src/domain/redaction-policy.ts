"use strict";

const sensitiveKeyPattern = /(password|passwd|pw|token|secret|authorization|cookie|session|key)/i;

function mask(value, depth = 0) {
  if (depth > 8) return "[depth-limit]";
  if (value == null) return value;
  if (Buffer.isBuffer(value)) return `[buffer:${value.length}]`;
  if (Array.isArray(value)) return value.map((item) => mask(item, depth + 1));
  if (typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value)) {
      out[key] = sensitiveKeyPattern.test(key) ? "[masked]" : mask(value[key], depth + 1);
    }
    return out;
  }
  if (typeof value === "string" && value.length > 2000) {
    return `${value.slice(0, 2000)}...[truncated]`;
  }
  return value;
}

module.exports = { mask };

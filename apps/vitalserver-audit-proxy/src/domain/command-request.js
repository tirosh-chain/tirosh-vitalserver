"use strict";

function commandRequestFromPayload(payload) {
  const parsed = parseMaybeQuery(payload);
  return {
    job: parsed && parsed.job ? parsed.job : undefined,
    target_vrcode: parsed && (parsed.vrcode || parsed["dev-setting-vrcode"]),
  };
}

function parseMaybeQuery(value) {
  if (value && typeof value === "object") return value;
  if (typeof value !== "string") return {};
  const out = {};
  for (const part of value.split("&")) {
    const [rawKey, rawValue = ""] = part.split("=");
    if (!rawKey) continue;
    try {
      out[decodeURIComponent(rawKey.replace(/\+/g, " "))] = decodeURIComponent(rawValue.replace(/\+/g, " "));
    } catch {
      out[rawKey] = rawValue;
    }
  }
  return out;
}

module.exports = { commandRequestFromPayload };

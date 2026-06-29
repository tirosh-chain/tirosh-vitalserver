import type { RuntimeMemoryGuardRead } from "../../../domain/memory-guard-types";

"use strict";

const fs = require("fs/promises");

type RuntimeStateMemoryGuardReaderConfig = {
  runtimeStatePath?: string;
  maxAgeMs?: number;
};

type RuntimeContainerServiceDocument = {
  service?: unknown;
  memoryUsedBytes?: unknown;
  memoryLimitBytes?: unknown;
};

type RuntimeStateDocument = {
  updatedAt?: unknown;
  containerServices?: unknown;
};

function createRuntimeStateMemoryGuardReader(config: RuntimeStateMemoryGuardReaderConfig = {}) {
  const path = config.runtimeStatePath || "/run/tirosh/runtime/runtime-state.json";
  const maxAgeMs = positiveIntegerOrDefault(config.maxAgeMs, 15000);

  return {
    async read(): Promise<RuntimeMemoryGuardRead> {
      let raw: string;
      try {
        raw = await fs.readFile(path, "utf8");
      } catch (error) {
        if (error && error.code === "ENOENT") {
          return { status: "missing", message: `runtime state not found path=${path}` };
        }
        return { status: "failed", message: readErrorMessage(error, path) };
      }

      let document: RuntimeStateDocument;
      try {
        document = JSON.parse(raw);
      } catch (error) {
        return { status: "invalid", message: `runtime state decode failed path=${path}: ${error.message}` };
      }

      const observedAt = stringValue(document.updatedAt);
      if (!observedAt) {
        return { status: "invalid", message: `runtime state missing updatedAt path=${path}` };
      }
      const observedAtMs = Date.parse(observedAt);
      if (!Number.isFinite(observedAtMs)) {
        return { status: "invalid", message: `runtime state invalid updatedAt path=${path}` };
      }
      const ageMs = Date.now() - observedAtMs;
      if (ageMs > maxAgeMs) {
        return {
          status: "stale",
          message: `runtime state stale path=${path} ageMs=${Math.floor(ageMs)} maxAgeMs=${maxAgeMs}`,
        };
      }

      const service = vitalServerService(document.containerServices);
      if (!service) {
        return { status: "invalid", message: `runtime state missing app container service path=${path}` };
      }
      const memoryUsedBytes = nonNegativeInteger(service.memoryUsedBytes);
      const memoryLimitBytes = positiveInteger(service.memoryLimitBytes);
      if (memoryUsedBytes === null || memoryLimitBytes === null) {
        return {
          status: "unavailable",
          message: `runtime state missing app memory usage path=${path}`,
        };
      }

      return {
        status: "loaded",
        vitalServer: {
          memoryUsedBytes,
          memoryLimitBytes,
          usageRatio: memoryUsedBytes / memoryLimitBytes,
          observedAt,
        },
      };
    },
  };
}

function vitalServerService(services: unknown): RuntimeContainerServiceDocument | null {
  if (!Array.isArray(services)) return null;
  for (const service of services) {
    if (!service || typeof service !== "object") continue;
    const document = service as RuntimeContainerServiceDocument;
    if (document.service === "app") return document;
  }
  return null;
}

function stringValue(value: unknown) {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function nonNegativeInteger(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? Math.floor(value) : null;
}

function positiveInteger(value: unknown) {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.floor(value) : null;
}

function positiveIntegerOrDefault(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.floor(value) : fallback;
}

function readErrorMessage(error, path: string) {
  if (error && error.message) return `runtime state read failed path=${path}: ${error.message}`;
  return `runtime state read failed path=${path}`;
}

module.exports = { createRuntimeStateMemoryGuardReader };

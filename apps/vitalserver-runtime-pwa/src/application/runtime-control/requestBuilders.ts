import type { ZodType } from "zod";

import type {
  RuntimeBackupRequest,
  RuntimeTestKitDeleteBedsRequest,
  RuntimeTestKitSessionSelectionRequest,
  RuntimeUninstallRequest,
  RuntimeUpdateBundleRequest
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  runtimeBackupRequestSchema,
  runtimeTestKitDeleteBedsRequestSchema,
  runtimeTestKitSessionSelectionRequestSchema,
  runtimeUninstallRequestSchema,
  runtimeUpdateBundleRequestSchema
} from "@/domain/runtime-control/contracts/schemas/runtimeControlRequestSchemas";
import { RuntimeControlValidationError } from "@/domain/runtime-control/errors/runtimeControlError";

export function updateBundleRequest(path: string): RuntimeUpdateBundleRequest {
  return parseRuntimeControlRequest(runtimeUpdateBundleRequestSchema, {
    bundle: {
      kind: "localPath",
      value: path
    }
  });
}

export function backupRequest(path: string): RuntimeBackupRequest {
  return parseRuntimeControlRequest(runtimeBackupRequestSchema, {
    backup: {
      kind: "localPath" as const,
      value: path
    }
  });
}

export function uninstallRequest(clean: boolean): RuntimeUninstallRequest {
  return parseRuntimeControlRequest(runtimeUninstallRequestSchema, { clean });
}

export function testKitDeleteBedsRequest(
  roomNames: string[]
): RuntimeTestKitDeleteBedsRequest {
  return parseRuntimeControlRequest(runtimeTestKitDeleteBedsRequestSchema, {
    roomNames
  });
}

export function testKitSessionSelectionRequest(
  sessionID: string | null
): RuntimeTestKitSessionSelectionRequest {
  return parseRuntimeControlRequest(runtimeTestKitSessionSelectionRequestSchema, {
    sessionID
  });
}

export function parseRuntimeControlRequest<T>(
  schema: ZodType<T>,
  request: unknown
): T {
  const result = schema.safeParse(request);
  if (!result.success) {
    throw new RuntimeControlValidationError(
      "Runtime Control request validation failed",
      result.error.issues.map((issue) => {
        const path = issue.path.join(".");
        return path ? `${path}: ${issue.message}` : issue.message;
      })
    );
  }
  return result.data;
}

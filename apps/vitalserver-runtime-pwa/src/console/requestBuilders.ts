import type { ZodType } from "zod";

import type {
  RuntimeBackupRequest,
  RuntimeTestKitCreateBedsRequest,
  RuntimeTestKitDeleteBedsRequest,
  RuntimeTestKitSessionSelectionRequest,
  RuntimeUninstallRequest,
  RuntimeUpdateBundleRequest
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import {
  runtimeBackupRequestSchema,
  runtimeTestKitCreateBedsRequestSchema,
  runtimeTestKitDeleteBedsRequestSchema,
  runtimeTestKitSessionSelectionRequestSchema,
  runtimeUninstallRequestSchema,
  runtimeUpdateBundleRequestSchema
} from "@/domain/runtime-control/contracts/schemas/runtimeControlRequestSchemas";
import { RuntimeControlValidationError } from "@/domain/runtime-control/errors/runtimeControlError";

export function updateBundleRequest(path: string): RuntimeUpdateBundleRequest {
  return parseConsoleRequest(runtimeUpdateBundleRequestSchema, {
    bundle: {
      kind: "localPath",
      value: path
    }
  });
}

export function backupRequest(path: string): RuntimeBackupRequest {
  return parseConsoleRequest(runtimeBackupRequestSchema, {
    backup: {
      kind: "localPath" as const,
      value: path
    }
  });
}

export function uninstallRequest(clean: boolean): RuntimeUninstallRequest {
  return parseConsoleRequest(runtimeUninstallRequestSchema, { clean });
}

export function testKitCreateBedsRequest(
  count: number | null,
  prefix: string,
  roomNames: string[] = []
): RuntimeTestKitCreateBedsRequest {
  return parseConsoleRequest(runtimeTestKitCreateBedsRequestSchema, {
    count,
    roomNames,
    prefix,
    adminUserId: "admin"
  });
}

export function testKitDeleteBedsRequest(
  roomNames: string[]
): RuntimeTestKitDeleteBedsRequest {
  return parseConsoleRequest(runtimeTestKitDeleteBedsRequestSchema, {
    roomNames
  });
}

export function testKitSessionSelectionRequest(
  sessionID: string
): RuntimeTestKitSessionSelectionRequest {
  return parseConsoleRequest(runtimeTestKitSessionSelectionRequestSchema, {
    sessionID: sessionID.trim()
  });
}

export function parseConsoleRequest<T>(
  schema: ZodType<T>,
  request: unknown
): T {
  const result = schema.safeParse(request);
  if (!result.success) {
    throw new RuntimeControlValidationError(
      "Console request validation failed",
      result.error.issues.map((issue) => {
        const path = issue.path.join(".");
        return path ? `${path}: ${issue.message}` : issue.message;
      })
    );
  }
  return result.data;
}

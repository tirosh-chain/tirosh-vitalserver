import { z } from "zod";

import type {
  RuntimeApplySettingsRequest,
  RuntimeBackupRequest,
  RuntimeExportLogsRequest,
  RuntimeLogTextRequest,
  RuntimeTestKitCreateBedsRequest,
  RuntimeTestKitDeleteBedsRequest,
  RuntimeTestKitRecorderDeletionRequest,
  RuntimeTestKitRestartRequest,
  RuntimeTestKitSessionSelectionRequest,
  RuntimeTestKitVirtualRecorderStartRequest,
  RuntimeUninstallRequest,
  RuntimeUpdateBundleRequest
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { runtimeSettingsSchema } from "./runtimeControlSchemas";

const nonEmptyString = z.string().trim().min(1);
const nullableNonEmptyString = z
  .string()
  .trim()
  .min(1)
  .nullable()
  .optional();

const fileReferenceSchema = z.object({
  kind: z.enum(["localPath", "uploadedArtifact", "remoteURL"]),
  value: nonEmptyString
});

export const runtimeApplySettingsRequestSchema = z.object({
  settings: runtimeSettingsSchema
}) satisfies z.ZodType<RuntimeApplySettingsRequest>;

export const runtimeUninstallRequestSchema = z.object({
  clean: z.boolean().optional()
}) satisfies z.ZodType<RuntimeUninstallRequest>;

export const runtimeBackupRequestSchema = z.object({
  backup: fileReferenceSchema
}) satisfies z.ZodType<RuntimeBackupRequest>;

export const runtimeUpdateBundleRequestSchema = z.object({
  bundle: fileReferenceSchema
}) satisfies z.ZodType<RuntimeUpdateBundleRequest>;

export const runtimeExportLogsRequestSchema = z.object({
  destination: fileReferenceSchema
}) satisfies z.ZodType<RuntimeExportLogsRequest>;

export const runtimeLogTextRequestSchema = z.object({
  source: z.enum([
    "helperMessage",
    "install",
    "command",
    "launcher",
    "vmLaunchOutput",
    "vmLaunchError",
    "proxyOutput",
    "proxyError",
    "watchdog",
    "updateActivation",
    "containers"
  ]),
  helperMessage: z.string().optional(),
  lineLimit: z.number().int().min(1).max(5_000).optional()
}) satisfies z.ZodType<RuntimeLogTextRequest>;

export const runtimeRepairProxyRequestSchema = z.object({
  proxyPort: z.number().int().min(1).max(65_535).optional()
});

export const runtimeTestKitCreateBedsRequestSchema = z
  .object({
    count: z.number().int().min(1).max(500).nullable().optional(),
    roomNames: z.array(nonEmptyString).optional(),
    prefix: nonEmptyString.optional(),
    adminUserId: nonEmptyString.optional()
  })
  .refine((request) => request.count !== undefined || request.roomNames?.length, {
    message: "count or roomNames is required",
    path: ["count"]
  }) satisfies z.ZodType<RuntimeTestKitCreateBedsRequest>;

export const runtimeTestKitDeleteBedsRequestSchema = z.object({
  roomNames: z.array(nonEmptyString).min(1)
}) satisfies z.ZodType<RuntimeTestKitDeleteBedsRequest>;

export const runtimeTestKitVirtualRecorderStartRequestSchema = z
  .object({
    scenario: z.enum([
      "normal",
      "multiple_recorders",
      "burst_traffic",
      "disconnect_reconnect",
      "stale_recorder",
      "signal_anomaly"
    ]),
    signalProfile: z.enum([
      "normal",
      "tachycardia",
      "desaturation",
      "artifact",
      "device_disconnect"
    ]),
    recorders: z.number().int().min(1).max(500),
    bedRoomNames: z.array(nonEmptyString).min(1),
    vrcode: nullableNonEmptyString,
    version: nonEmptyString,
    intervalSeconds: z.number().positive(),
    durationSeconds: z.number().positive().nullable().optional(),
    maxMessages: z.number().int().positive().nullable().optional(),
    shiftTime: z.boolean(),
    generateFrames: z.boolean()
  })
  .refine((request) => request.bedRoomNames.length >= request.recorders, {
    message: "bedRoomNames must include at least one bed per recorder",
    path: ["bedRoomNames"]
  }) satisfies z.ZodType<RuntimeTestKitVirtualRecorderStartRequest>;

export const runtimeTestKitSessionSelectionRequestSchema = z.object({
  sessionID: nullableNonEmptyString
}) satisfies z.ZodType<RuntimeTestKitSessionSelectionRequest>;

export const runtimeTestKitRestartRequestSchema = z.object({
  sessionID: nullableNonEmptyString,
  bedRoomNames: z.array(nonEmptyString).min(1)
}) satisfies z.ZodType<RuntimeTestKitRestartRequest>;

export const runtimeTestKitRecorderDeletionRequestSchema = z.object({
  vrcode: nonEmptyString
}) satisfies z.ZodType<RuntimeTestKitRecorderDeletionRequest>;

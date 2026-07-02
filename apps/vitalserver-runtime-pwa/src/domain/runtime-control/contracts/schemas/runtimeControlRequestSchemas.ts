import { z } from "zod";

import type {
  RuntimeApplySettingsRequest,
  RuntimeBackupRequest,
  RuntimeExportLogsRequest,
  RuntimeLabBedCreateRequest,
  RuntimeLabBedDeleteRequest,
  RuntimeLabRecorderCreateRequest,
  RuntimeLabRecorderDeleteRequest,
  RuntimeLabSessionCreateRequest,
  RuntimeLabVitalFileReplayRequest,
  RuntimeGuestServiceControlRequest,
  RuntimeLogTextRequest,
  RuntimeUninstallRequest,
  RuntimeUpdateBundleRequest,
  VitalDBBedVisibilityRequest,
  VitalDBRecorderVisibilityRequest
} from "@/domain/runtime-control/contracts/runtimeControlTypes";
import { runtimeSettingsSchema } from "./runtimeControlSchemas";

const nonEmptyString = z.string().trim().min(1);
const fileReferenceSchema = z.object({
  kind: z.enum(["localPath", "uploadedArtifact", "remoteURL"]),
  value: nonEmptyString
});

export const runtimeApplySettingsRequestSchema = z.object({
  settings: runtimeSettingsSchema
}) satisfies z.ZodType<RuntimeApplySettingsRequest>;

export const runtimeUninstallRequestSchema = z.object({
  mode: z.enum(["standard", "clean", "forceCleanUninstaller"])
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
  helperMessage: z.string().nullable(),
  lineLimit: z.number().int().min(1).max(5_000)
}) satisfies z.ZodType<RuntimeLogTextRequest>;

export const runtimeRepairProxyRequestSchema = z.object({
  proxyPort: z.number().int().min(1).max(65_535)
});

export const runtimeLabSessionIdSchema = nonEmptyString;

export const runtimeLabSessionCreateRequestSchema = z.object({
  scenarioId: nonEmptyString,
  name: z.string().trim().min(1).nullable().optional(),
  recorderCount: z.number().int().min(1).max(500),
  targetURL: z.string().trim().min(1).nullable().optional()
}) satisfies z.ZodType<RuntimeLabSessionCreateRequest>;

export const runtimeLabBedCreateRequestSchema = z.object({
  count: z.number().int().min(1).max(500).nullable().optional(),
  roomNames: z.array(nonEmptyString).optional(),
  prefix: z.string().trim().min(1).nullable().optional(),
  targetURL: z.string().trim().min(1).nullable().optional()
}) satisfies z.ZodType<RuntimeLabBedCreateRequest>;

export const runtimeLabBedDeleteRequestSchema = z.object({
  bedIds: z.array(nonEmptyString).optional(),
  roomNames: z.array(nonEmptyString).optional(),
  sessionId: z.string().trim().min(1).nullable().optional()
}) satisfies z.ZodType<RuntimeLabBedDeleteRequest>;

export const runtimeLabRecorderCreateRequestSchema = z.object({
  bedIds: z.array(nonEmptyString).optional(),
  sessionId: z.string().trim().min(1).nullable().optional()
}) satisfies z.ZodType<RuntimeLabRecorderCreateRequest>;

export const runtimeLabRecorderDeleteRequestSchema = z.object({
  recorderIds: z.array(nonEmptyString).optional(),
  vrcodes: z.array(nonEmptyString).optional(),
  sessionId: z.string().trim().min(1).nullable().optional()
}) satisfies z.ZodType<RuntimeLabRecorderDeleteRequest>;

export const runtimeLabVitalFileReplayRequestSchema = z.object({
  vitalFilePath: nonEmptyString,
  sessionName: z.string().trim().min(1).nullable().optional(),
  targetURL: z.string().trim().min(1).nullable().optional()
}) satisfies z.ZodType<RuntimeLabVitalFileReplayRequest>;

export const vitalDBRecorderVisibilityRequestSchema = z.object({
  vrcodes: z.array(nonEmptyString).min(1)
}) satisfies z.ZodType<VitalDBRecorderVisibilityRequest>;

export const vitalDBBedVisibilityRequestSchema = z.object({
  bedIDs: z.array(nonEmptyString).min(1)
}) satisfies z.ZodType<VitalDBBedVisibilityRequest>;

export const runtimeGuestServiceControlRequestSchema = z.object({
  service: nonEmptyString,
  guestControlBaseURL: z.string().trim().min(1).nullable().optional()
}) satisfies z.ZodType<RuntimeGuestServiceControlRequest>;

import type {
  RecorderObservabilityResourceType,
  RecorderObservabilityValidation,
} from "../../../domain/recorder-observability";

export interface RecorderObservabilitySchemaPort {
  validate(
    resourceType: RecorderObservabilityResourceType,
    value: unknown,
    requestDeviceId: string,
  ): RecorderObservabilityValidation;
  receipts(): ReadonlyArray<Record<string, string>>;
}

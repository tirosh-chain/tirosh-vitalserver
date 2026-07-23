export const recorderObservabilityResourceTypes = {
  observations: "observation",
  "diagnostic-events": "diagnosticEvent",
  "kernel-incidents": "kernelIncident",
} as const;

export type RecorderObservabilityResourceType =
  (typeof recorderObservabilityResourceTypes)[keyof typeof recorderObservabilityResourceTypes];

export type RecorderObservabilityCandidate = {
  eventId: string;
  deviceId: string;
};

export type RecorderObservabilityValidation =
  | {
      kind: "valid";
      candidate: RecorderObservabilityCandidate;
    }
  | {
      kind: "invalid";
      eventId: string | null;
      documentDeviceId: string | null;
      reason: string;
    };

export function validateRecorderObservabilityDocument(
  resourceType: RecorderObservabilityResourceType,
  value: unknown,
  requestDeviceId: string,
): RecorderObservabilityValidation {
  if (!isObject(value)) {
    return invalid(null, null, "document_must_be_object");
  }
  const eventId = optionalString(value.eventId);
  const deviceId = optionalString(value.deviceId);
  if (value.schemaVersion !== "v1") {
    return invalid(eventId, deviceId, "unsupported_schema_version");
  }
  if (!eventId) {
    return invalid(null, deviceId, "event_id_required");
  }
  if (!deviceId) {
    return invalid(eventId, null, "device_id_required");
  }
  if (deviceId !== requestDeviceId) {
    return invalid(eventId, deviceId, "device_id_mismatch");
  }

  switch (resourceType) {
    case "observation":
      return validateObservation(value, eventId, deviceId);
    case "diagnosticEvent":
      return validateDiagnosticEvent(value, eventId, deviceId);
    case "kernelIncident":
      return validateKernelIncident(value, eventId, deviceId);
  }
}

function validateObservation(
  value: Record<string, unknown>,
  eventId: string,
  deviceId: string,
): RecorderObservabilityValidation {
  const bootId = optionalString(value.bootId);
  if (!hasOnlyKeys(value, [
    "schemaVersion",
    "eventId",
    "deviceId",
    "siteId",
    "bootId",
    "sequence",
    "kind",
    "collectionState",
    "deviceObservedAt",
    "uptimeSeconds",
    "ntpState",
    "payload",
    "readIssues",
  ])) {
    return invalid(eventId, deviceId, "observation_fields_invalid");
  }
  if (value.kind !== "device-health") {
    return invalid(eventId, deviceId, "observation_kind_invalid");
  }
  if (!bootId) {
    return invalid(eventId, deviceId, "boot_id_required");
  }
  if (!Number.isSafeInteger(value.sequence) || Number(value.sequence) < 1) {
    return invalid(eventId, deviceId, "sequence_invalid");
  }
  if (eventId !== `${deviceId}:${bootId}:${value.sequence}`) {
    return invalid(eventId, deviceId, "event_id_invalid");
  }
  if (!["ok", "partial"].includes(String(value.collectionState))) {
    return invalid(eventId, deviceId, "collection_state_invalid");
  }
  if (!validTimestamp(value.deviceObservedAt)) {
    return invalid(eventId, deviceId, "device_observed_at_invalid");
  }
  if (!isObject(value.uptimeSeconds) || !isObject(value.payload)) {
    return invalid(eventId, deviceId, "observation_payload_invalid");
  }
  if (!Array.isArray(value.readIssues)) {
    return invalid(eventId, deviceId, "read_issues_invalid");
  }
  if (![
    "synchronized",
    "host-clock-only",
    "unsynchronized",
    "invalid",
    "read-failed",
    "unsupported",
  ].includes(String(value.ntpState))) {
    return invalid(eventId, deviceId, "ntp_state_invalid");
  }
  return valid(eventId, deviceId);
}

function validateDiagnosticEvent(
  value: Record<string, unknown>,
  eventId: string,
  deviceId: string,
): RecorderObservabilityValidation {
  if (!hasOnlyKeys(value, [
    "schemaVersion",
    "eventId",
    "deviceId",
    "bootId",
    "kind",
    "source",
    "deviceObservedAt",
    "monotonicTimestampMicroseconds",
    "priority",
    "category",
    "code",
    "interface",
    "message",
  ])) {
    return invalid(eventId, deviceId, "diagnostic_fields_invalid");
  }
  if (value.kind !== "diagnostic-log") {
    return invalid(eventId, deviceId, "diagnostic_kind_invalid");
  }
  if (
    !optionalString(value.bootId)
    || !optionalString(value.message)
  ) {
    return invalid(eventId, deviceId, "diagnostic_identity_or_message_invalid");
  }
  if (!validTimestamp(value.deviceObservedAt)) {
    return invalid(eventId, deviceId, "device_observed_at_invalid");
  }
  if (![
    "kernel",
    "chrony",
    "systemd",
    "auth",
    "recovery-script",
    "reboot-intent",
    "vital-recorder",
    "heartbeat",
    "boot",
    "power",
    "observer",
    "maintenance",
  ].includes(String(value.source))) {
    return invalid(eventId, deviceId, "diagnostic_source_invalid");
  }
  if (!String(eventId).startsWith(`${deviceId}:${value.bootId}:`)) {
    return invalid(eventId, deviceId, "event_id_invalid");
  }
  return valid(eventId, deviceId);
}

function validateKernelIncident(
  value: Record<string, unknown>,
  eventId: string,
  deviceId: string,
): RecorderObservabilityValidation {
  if (!hasOnlyKeys(value, [
    "schemaVersion",
    "eventId",
    "deviceId",
    "siteId",
    "captureBootId",
    "kind",
    "capturedAt",
    "source",
    "incidentType",
    "kernelRelease",
    "model",
    "kernelCommandLine",
    "firmwareThrottleFlags",
    "artifacts",
    "previousBootJournal",
    "messageExcerpt",
    "truncated",
  ])) {
    return invalid(eventId, deviceId, "kernel_incident_fields_invalid");
  }
  if (value.kind !== "kernel-incident") {
    return invalid(eventId, deviceId, "kernel_incident_kind_invalid");
  }
  if (
    !optionalString(value.captureBootId)
    || value.source !== "pstore"
    || !optionalString(value.messageExcerpt)
  ) {
    return invalid(eventId, deviceId, "kernel_incident_identity_invalid");
  }
  if (!validTimestamp(value.capturedAt)) {
    return invalid(eventId, deviceId, "captured_at_invalid");
  }
  const incidentFingerprint = eventId.slice(
    `${deviceId}:kernel-incident:`.length,
  );
  if (
    !eventId.startsWith(`${deviceId}:kernel-incident:`)
    || !/^[a-f0-9]{64}$/.test(incidentFingerprint)
  ) {
    return invalid(eventId, deviceId, "event_id_invalid");
  }
  if (
    !["panic", "oops", "watchdog", "lockup", "unknown"].includes(
      String(value.incidentType),
    )
    || !optionalString(value.kernelRelease)
    || !optionalString(value.model)
    || typeof value.kernelCommandLine !== "string"
    || !Array.isArray(value.artifacts)
    || value.artifacts.length < 1
    || value.artifacts.length > 32
    || !isObject(value.previousBootJournal)
    || typeof value.truncated !== "boolean"
  ) {
    return invalid(eventId, deviceId, "kernel_incident_payload_invalid");
  }
  for (const artifact of value.artifacts) {
    if (
      !isObject(artifact)
      || !hasOnlyKeys(artifact, [
        "name",
        "sourcePath",
        "sourceRoot",
        "storedPath",
        "sizeBytes",
        "sha256",
      ])
      || !optionalString(artifact.name)
      || !absolutePath(artifact.sourcePath)
      || !absolutePath(artifact.sourceRoot)
      || !storedIncidentPath(artifact.storedPath)
      || !Number.isSafeInteger(artifact.sizeBytes)
      || Number(artifact.sizeBytes) < 1
      || !/^[a-f0-9]{64}$/.test(String(artifact.sha256))
    ) {
      return invalid(eventId, deviceId, "kernel_incident_artifact_invalid");
    }
  }
  if (
    !hasOnlyKeys(value.previousBootJournal, [
      "available",
      "storedPath",
      "sizeBytes",
      "sha256",
    ])
    || typeof value.previousBootJournal.available !== "boolean"
  ) {
    return invalid(eventId, deviceId, "previous_boot_journal_invalid");
  }
  if (
    value.previousBootJournal.available
    && (
      !storedIncidentPath(value.previousBootJournal.storedPath)
      || !Number.isSafeInteger(value.previousBootJournal.sizeBytes)
      || Number(value.previousBootJournal.sizeBytes) < 1
      || !/^[a-f0-9]{64}$/.test(String(value.previousBootJournal.sha256))
    )
  ) {
    return invalid(eventId, deviceId, "previous_boot_journal_invalid");
  }
  return valid(eventId, deviceId);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function optionalString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0
    ? value
    : null;
}

function validTimestamp(value: unknown): boolean {
  return Boolean(optionalString(value)) && !Number.isNaN(Date.parse(String(value)));
}

function hasOnlyKeys(
  value: Record<string, unknown>,
  allowed: string[],
): boolean {
  const allowedKeys = new Set(allowed);
  return Object.keys(value).every((key) => allowedKeys.has(key));
}

function absolutePath(value: unknown): boolean {
  return typeof value === "string" && value.startsWith("/");
}

function storedIncidentPath(value: unknown): boolean {
  return (
    typeof value === "string"
    && value.startsWith("/data/vitalrecorder-observer/kernel-incidents/")
  );
}

function valid(
  eventId: string,
  deviceId: string,
): RecorderObservabilityValidation {
  return { kind: "valid", candidate: { eventId, deviceId } };
}

function invalid(
  eventId: string | null,
  documentDeviceId: string | null,
  reason: string,
): RecorderObservabilityValidation {
  return { kind: "invalid", eventId, documentDeviceId, reason };
}

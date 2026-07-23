import { createHash } from "crypto";
import { readFileSync } from "fs";
import * as path from "path";
import { Ajv2020 } from "ajv/dist/2020";
import type { RecorderObservabilitySchemaPort } from "../../../application/ports/outbound/recorder-observability-schema-port";
import type {
  RecorderObservabilityDocumentIdentity,
  RecorderObservabilityResourceType,
  RecorderObservabilityValidation,
} from "../../../domain/recorder-observability";

type ContractReceipt = {
  resourceType: RecorderObservabilityResourceType;
  schemaVersion: string;
  kind: string;
  file: string;
  sha256: string;
  sourceRepository: string;
  sourcePath: string;
};

type CompiledContract = ContractReceipt & {
  validate: ReturnType<Ajv2020["compile"]>;
};

const addFormats = require("ajv-formats") as typeof import("ajv-formats").default;

export function createRecorderObservabilitySchemaRegistry({
  directory = path.resolve(
    __dirname,
    "../../../../../contracts/recorder-observability",
  ),
}: {
  directory?: string;
} = {}): RecorderObservabilitySchemaPort {
  const manifest = JSON.parse(
    readFileSync(path.join(directory, "manifest.json"), "utf8"),
  ) as {
    manifestVersion: number;
    sourceManifestFile: string;
    sourceManifestSha256: string;
    contracts: ContractReceipt[];
  };
  if (manifest.manifestVersion !== 1 || !Array.isArray(manifest.contracts)) {
    throw new Error("recorder_observability_contract_manifest_invalid");
  }
  const sourceManifestBytes = readFileSync(
    path.join(directory, manifest.sourceManifestFile),
  );
  if (sha256(sourceManifestBytes) !== manifest.sourceManifestSha256) {
    throw new Error("recorder_observability_source_manifest_receipt_mismatch");
  }
  const sourceManifest = JSON.parse(sourceManifestBytes.toString("utf8")) as {
    contracts: Array<{
      schemaVersion: string;
      path: string;
      sha256: string;
    }>;
  };
  if (sourceManifest.contracts.length !== manifest.contracts.length) {
    throw new Error("recorder_observability_contract_set_incomplete");
  }

  const ajv = new Ajv2020({
    allErrors: true,
    allowUnionTypes: true,
    // The authoritative contracts use valid JSON Schema 2020-12 constructs
    // (union `type`, inherited `properties`, and `required` inside `not`)
    // that Ajv's optional lint-style strict mode rejects.
    strict: false,
  });
  addFormats(ajv);
  const contracts = new Map<string, CompiledContract>();
  for (const receipt of manifest.contracts) {
    const sourcePath = receipt.sourcePath.replace(
      /^contracts\/observation\//,
      "",
    );
    const sourceReceipt = sourceManifest.contracts.find((contract) =>
      contract.path === sourcePath
      && contract.schemaVersion === receipt.schemaVersion
    );
    if (!sourceReceipt || sourceReceipt.sha256 !== receipt.sha256) {
      throw new Error(
        `recorder_observability_source_receipt_mismatch:${receipt.sourcePath}`,
      );
    }
    const schemaBytes = readFileSync(path.join(directory, receipt.file));
    const actualSha256 = sha256(schemaBytes);
    if (actualSha256 !== receipt.sha256) {
      throw new Error(
        `recorder_observability_contract_receipt_mismatch:${receipt.file}`,
      );
    }
    const schema = JSON.parse(schemaBytes.toString("utf8"));
    const key = contractKey(
      receipt.resourceType,
      receipt.schemaVersion,
      receipt.kind,
    );
    if (contracts.has(key)) {
      throw new Error(`recorder_observability_contract_duplicate:${key}`);
    }
    contracts.set(key, { ...receipt, validate: ajv.compile(schema) });
  }

  return {
    validate(
      resourceType: RecorderObservabilityResourceType,
      value: unknown,
      requestDeviceId: string,
    ): RecorderObservabilityValidation {
      if (!isObject(value)) {
        return invalid({}, "document_must_be_object", null, null);
      }
      const identity = extractIdentity(value);
      if (!identity.schemaVersion || !identity.kind) {
        return invalid(
          identity,
          "contract_identity_required",
          "schemaVersion and kind are required",
          null,
        );
      }
      const contract = contracts.get(
        contractKey(resourceType, identity.schemaVersion, identity.kind),
      );
      if (!contract) {
        return invalid(
          identity,
          "unsupported_contract",
          `${resourceType}/${identity.schemaVersion}/${identity.kind}`,
          null,
        );
      }
      if (!contract.validate(value)) {
        return invalid(
          identity,
          "schema_validation_failed",
          ajv.errorsText(contract.validate.errors, { separator: "; " }),
          contract.sha256,
        );
      }
      if (identity.deviceId !== requestDeviceId) {
        return invalid(
          identity,
          "device_id_mismatch",
          `header=${requestDeviceId}; document=${identity.deviceId || ""}`,
          contract.sha256,
        );
      }
      return {
        kind: "valid",
        identity: identity as RecorderObservabilityDocumentIdentity,
        contractReceipt: contract.sha256,
      };
    },
    receipts() {
      return manifest.contracts.map((contract) => ({ ...contract }));
    },
  };
}

function extractIdentity(
  value: Record<string, unknown>,
): Partial<RecorderObservabilityDocumentIdentity> {
  return {
    eventId: stringOrUndefined(value.eventId),
    deviceId: stringOrUndefined(value.deviceId),
    schemaVersion: stringOrUndefined(value.schemaVersion),
    kind: stringOrUndefined(value.kind),
    siteId: stringOrNull(value.siteId),
    bootId: stringOrNull(value.bootId ?? value.captureBootId),
    sequence: safeIntegerOrNull(value.sequence),
    deviceObservedAt: stringOrNull(
      value.deviceObservedAt ?? value.capturedAt ?? value.occurredAt,
    ),
    deviceTimeState: stringOrNull(
      value.deviceTimeState ?? value.captureTimeState ?? value.ntpState,
    ),
  };
}

function invalid(
  identity: Partial<RecorderObservabilityDocumentIdentity>,
  reason: string,
  detail: string | null,
  contractReceipt: string | null,
): RecorderObservabilityValidation {
  return {
    kind: "invalid",
    identity,
    reason,
    detail,
    contractReceipt,
  };
}

function contractKey(
  resourceType: RecorderObservabilityResourceType,
  schemaVersion: string,
  kind: string,
): string {
  return `${resourceType}\u0000${schemaVersion}\u0000${kind}`;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function stringOrUndefined(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function safeIntegerOrNull(value: unknown): number | null {
  return Number.isSafeInteger(value) ? Number(value) : null;
}

function sha256(value: Buffer): string {
  return createHash("sha256").update(value).digest("hex");
}

module.exports = { createRecorderObservabilitySchemaRegistry };

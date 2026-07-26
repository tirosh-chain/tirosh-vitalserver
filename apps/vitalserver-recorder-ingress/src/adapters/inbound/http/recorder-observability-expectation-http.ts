import { timingSafeEqual } from "crypto";
import type { IncomingMessage, ServerResponse } from "http";
import type { RecorderObservabilityRepositoryPort } from "../../../application/ports/outbound/recorder-observability-repository-port";
import type { RecorderObservabilityExpectationCommand } from "../../../domain/recorder-observability-expectation";

export type ExpectationControlCredential =
  | { state: "loaded"; token: string; reason: null }
  | { state: "unavailable"; token: null; reason: string };

export function recorderObservabilityExpectationCommandRoute(
  requestURL: string | undefined,
): boolean {
  return new URL(requestURL || "/", "http://recorder-ingress").pathname
    === "/internal/recorder-observability/expectations";
}

export function receiveRecorderObservabilityExpectationCommand(
  req: IncomingMessage,
  res: ServerResponse,
  {
    repository,
    credential,
    maxRequestBytes,
  }: {
    repository?: RecorderObservabilityRepositoryPort;
    credential: ExpectationControlCredential;
    maxRequestBytes: number;
  },
): void {
  if (req.method !== "POST") {
    req.resume();
    writeJson(res, 405, {
      state: "rejected",
      failure: "methodNotAllowed",
    }, { allow: "POST" });
    return;
  }
  if (credential.state !== "loaded") {
    req.resume();
    writeJson(res, 503, {
      state: "unavailable",
      failure: "expectationControlCredentialUnavailable",
      detail: credential.reason,
    });
    return;
  }
  if (!authorized(req.headers.authorization, credential.token)) {
    req.resume();
    writeJson(res, 401, {
      state: "rejected",
      failure: "expectationControlUnauthorized",
    });
    return;
  }
  if (!repository) {
    req.resume();
    writeJson(res, 503, {
      state: "unavailable",
      failure: "expectationRepositoryUnavailable",
    });
    return;
  }
  if (mediaType(req.headers["content-type"]) !== "application/json") {
    req.resume();
    writeJson(res, 415, {
      state: "rejected",
      failure: "contentTypeInvalid",
    });
    return;
  }

  const chunks: Buffer[] = [];
  let bytes = 0;
  let tooLarge = false;
  req.on("data", (chunk) => {
    bytes += chunk.length;
    if (bytes > maxRequestBytes) {
      tooLarge = true;
      return;
    }
    chunks.push(chunk);
  });
  req.on("error", (error) => {
    if (res.writableEnded) return;
    writeJson(res, 400, {
      state: "rejected",
      failure: "requestReadFailed",
      detail: errorMessage(error),
    });
  });
  req.on("end", async () => {
    if (res.writableEnded) return;
    if (tooLarge) {
      writeJson(res, 413, {
        state: "rejected",
        failure: "requestTooLarge",
        maxRequestBytes,
      });
      return;
    }
    let command: RecorderObservabilityExpectationCommand;
    try {
      command = decodeCommand(JSON.parse(Buffer.concat(chunks).toString("utf8")));
    } catch (error) {
      writeJson(res, 400, {
        state: "rejected",
        failure: "commandContractInvalid",
        detail: errorMessage(error),
      });
      return;
    }
    try {
      const decision = await repository.applyExpectationCommand(command);
      const receipt = {
        state: decision.kind,
        commandId: command.commandId,
        vrcode: command.vrcode,
        currentRevision: decision.currentRevision,
        eventId: "event" in decision ? decision.event.eventId : null,
        failure: "failure" in decision ? decision.failure : null,
      };
      writeJson(
        res,
        decision.kind === "accepted"
          ? 201
          : decision.kind === "idempotent"
            ? 200
            : decision.kind === "revisionConflict"
              ? 409
              : 422,
        receipt,
      );
    } catch (error) {
      writeJson(res, 503, {
        state: "failed",
        commandId: command.commandId,
        vrcode: command.vrcode,
        currentRevision: null,
        eventId: null,
        failure: "expectationCommandPersistenceFailed",
        detail: errorMessage(error),
      });
    }
  });
}

function decodeCommand(value: unknown): RecorderObservabilityExpectationCommand {
  if (!value || Array.isArray(value) || typeof value !== "object") {
    throw new Error("command must be an object");
  }
  const document = value as Record<string, unknown>;
  const fields = [
    "commandId",
    "vrcode",
    "expectedRevision",
    "action",
    "supportState",
    "source",
    "recorderVersion",
    "producerVersion",
    "protocolVersion",
    "catalogRevision",
    "expectedSince",
    "evidenceDocument",
    "decidedAt",
  ];
  const unknown = Object.keys(document).filter((key) => !fields.includes(key));
  const missing = fields.filter(
    (key) => !Object.prototype.hasOwnProperty.call(document, key),
  );
  if (unknown.length || missing.length) {
    throw new Error(
      `command fields invalid missing=${missing.join(",")} unknown=${unknown.join(",")}`,
    );
  }
  for (const field of ["commandId", "vrcode", "action", "decidedAt"]) {
    if (typeof document[field] !== "string") {
      throw new Error(`${field} must be a string`);
    }
  }
  if (!Number.isSafeInteger(document.expectedRevision)) {
    throw new Error("expectedRevision must be an integer");
  }
  for (const field of [
    "supportState",
    "source",
    "recorderVersion",
    "producerVersion",
    "protocolVersion",
    "catalogRevision",
    "expectedSince",
  ]) {
    if (document[field] !== null && typeof document[field] !== "string") {
      throw new Error(`${field} must be a string or null`);
    }
  }
  if (
    !document.evidenceDocument
    || Array.isArray(document.evidenceDocument)
    || typeof document.evidenceDocument !== "object"
  ) {
    throw new Error("evidenceDocument must be an object");
  }
  return document as RecorderObservabilityExpectationCommand;
}

function authorized(header: string | undefined, expectedToken: string): boolean {
  if (!header?.startsWith("Bearer ")) return false;
  const actual = Buffer.from(header.slice("Bearer ".length), "utf8");
  const expected = Buffer.from(expectedToken, "utf8");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function mediaType(value: string | undefined): string {
  return String(value || "").split(";", 1)[0].trim().toLowerCase();
}

function writeJson(
  res: ServerResponse,
  statusCode: number,
  value: unknown,
  headers: Record<string, string> = {},
): void {
  const body = JSON.stringify(value);
  res.writeHead(statusCode, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(body),
    ...headers,
  });
  res.end(body);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

module.exports = {
  receiveRecorderObservabilityExpectationCommand,
  recorderObservabilityExpectationCommandRoute,
};

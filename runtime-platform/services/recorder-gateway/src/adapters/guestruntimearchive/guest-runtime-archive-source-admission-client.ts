import { Readable } from "node:stream";

import type { RecorderVitalUploadArchivePublisher } from "../../recordergatewayapplication/recorder-gateway-vital-upload-application-ports.js";
import {
  validateArchiveSourceAdmissionReceipt,
  validateRecorderVitalUploadSourceReceipt,
  type ArchiveSourceAdmissionReceipt,
  type RecorderVitalUploadPublishOutcome,
  type RecorderVitalUploadSourceReceipt,
} from "../../recordergatewaydomain/recorder-gateway-vital-upload-contracts.js";
import {
  isRecorderGatewayIdentifier,
  recorderGatewaySchemaVersion,
  type RecorderGatewayIssue,
} from "../../recordergatewaydomain/recorder-gateway-ingress-and-cold-path-contracts.js";

export interface GuestRuntimeArchiveSourceAdmissionClientConfiguration {
  endpoint: string;
  bearerToken: string;
  requestTimeoutMs: number;
}

export class GuestRuntimeArchiveSourceAdmissionClient
implements RecorderVitalUploadArchivePublisher {
  private constructor(
    private readonly configuration: GuestRuntimeArchiveSourceAdmissionClientConfiguration,
  ) {}

  public static create(
    configuration: GuestRuntimeArchiveSourceAdmissionClientConfiguration,
  ): GuestRuntimeArchiveSourceAdmissionClient {
    const endpoint = new URL(configuration.endpoint);
    if (
      endpoint.protocol !== "http:"
      || endpoint.username !== ""
      || endpoint.password !== ""
      || endpoint.search !== ""
      || endpoint.hash !== ""
      || endpoint.pathname !== "/internal/v1/archive/recorder-uploads"
      || configuration.bearerToken === ""
      || configuration.bearerToken.trim() !== configuration.bearerToken
      || !Number.isSafeInteger(configuration.requestTimeoutMs)
      || configuration.requestTimeoutMs < 1
      || configuration.requestTimeoutMs > 300000
    ) {
      throw new TypeError("Guest Runtime Archive source admission client configuration is invalid");
    }
    return new GuestRuntimeArchiveSourceAdmissionClient(configuration);
  }

  public async publishRecorderVitalUpload(
    source: RecorderVitalUploadSourceReceipt,
    requestId: string,
    content: Readable,
  ): Promise<RecorderVitalUploadPublishOutcome> {
    validateRecorderVitalUploadSourceReceipt(source);
    if (!isRecorderGatewayIdentifier(requestId)) {
      throw new TypeError("Archive source admission request identity is invalid");
    }
    const command = {
      schemaVersion: recorderGatewaySchemaVersion,
      requestId,
      source,
    };
    let response: Response;
    try {
      const requestBody = Readable.toWeb(content) as unknown as BodyInit;
      response = await fetch(this.configuration.endpoint, {
        method: "POST",
        headers: {
          authorization: `Bearer ${this.configuration.bearerToken}`,
          "content-type": "application/x-vital",
          "content-length": source.byteSize.toString(),
          "x-vital-archive-source-command": Buffer.from(
            JSON.stringify(command),
            "utf8",
          ).toString("base64url"),
        },
        body: requestBody,
        duplex: "half",
        signal: AbortSignal.timeout(this.configuration.requestTimeoutMs),
      } as RequestInit & { duplex: "half" });
    } catch {
      return unknownPublishOutcome(
        "guest-archive-source-request-outcome-unknown",
        "Recorder Gateway could not determine the Guest Archive HTTP request outcome",
      );
    }
    let document: unknown;
    try {
      document = JSON.parse(await readBoundedResponseBody(response, 64 * 1024)) as unknown;
    } catch {
      return unknownPublishOutcome(
        "guest-archive-source-response-invalid",
        "Guest Archive source admission response was not bounded valid JSON",
      );
    }
    if (response.status === 200 || response.status === 202) {
      try {
        const receipt = document as ArchiveSourceAdmissionReceipt;
        validateArchiveSourceAdmissionReceipt(receipt, requestId);
        if (receipt.outcome !== "accepted" && receipt.outcome !== "duplicate") {
          throw new TypeError("successful status did not contain a successful receipt");
        }
        return { state: "admitted", receipt };
      } catch {
        return unknownPublishOutcome(
          "guest-archive-source-success-contract-invalid",
          "Guest Archive successful response did not match its admission receipt contract",
        );
      }
    }
    if (response.status === 422) {
      try {
        const receipt = document as ArchiveSourceAdmissionReceipt;
        validateArchiveSourceAdmissionReceipt(receipt, requestId);
        if (receipt.outcome !== "quarantined") {
          throw new TypeError("unprocessable status did not contain quarantine");
        }
        return { state: "quarantined", receipt };
      } catch {
        return unknownPublishOutcome(
          "guest-archive-source-quarantine-contract-invalid",
          "Guest Archive quarantine response did not match its admission receipt contract",
        );
      }
    }
    if ([400, 401, 403, 413, 415].includes(response.status)) {
      const issue = admissionFailureIssue(document);
      if (issue !== undefined) {
        return { state: "rejected", issue };
      }
      return unknownPublishOutcome(
        "guest-archive-source-rejection-contract-invalid",
        "Guest Archive rejection response did not contain a typed issue",
      );
    }
    return unknownPublishOutcome(
      "guest-archive-source-response-outcome-unknown",
      `Guest Archive returned HTTP ${response.status} without a terminal admission receipt`,
    );
  }
}

async function readBoundedResponseBody(
  response: Response,
  maximumBytes: number,
): Promise<string> {
  if (response.body === null) {
    throw new Error("response body is missing");
  }
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let byteCount = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) {
      break;
    }
    byteCount += next.value.byteLength;
    if (byteCount > maximumBytes) {
      await reader.cancel();
      throw new Error("response body exceeds limit");
    }
    chunks.push(next.value);
  }
  return Buffer.concat(chunks.map((chunk) => Buffer.from(chunk))).toString("utf8");
}

function admissionFailureIssue(document: unknown): RecorderGatewayIssue | undefined {
  if (
    typeof document !== "object"
    || document === null
    || !("issue" in document)
    || typeof document.issue !== "object"
    || document.issue === null
    || !("code" in document.issue)
    || typeof document.issue.code !== "string"
    || !isRecorderGatewayIdentifier(document.issue.code)
  ) {
    return undefined;
  }
  const issue = document.issue as {
    code: string;
    message?: unknown;
    retryable?: unknown;
    dependency?: unknown;
  };
  return {
    code: issue.code,
    message: typeof issue.message === "string" ? issue.message : undefined,
    retryable: typeof issue.retryable === "boolean" ? issue.retryable : undefined,
    dependency: typeof issue.dependency === "string" ? issue.dependency : undefined,
  };
}

function unknownPublishOutcome(
  code: string,
  message: string,
): RecorderVitalUploadPublishOutcome {
  return {
    state: "unknown",
    issue: {
      code,
      message,
      retryable: true,
      dependency: "guest-runtime-archive-source-admission",
    },
  };
}

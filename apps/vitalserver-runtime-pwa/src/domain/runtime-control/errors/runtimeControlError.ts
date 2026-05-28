export type RuntimeControlErrorKind =
  | "api"
  | "contract"
  | "validation"
  | "network"
  | "unknown";

export type RuntimeControlErrorSummary = {
  kind: RuntimeControlErrorKind;
  title: string;
  detail: string;
  recovery: string;
};

export class RuntimeControlValidationError extends Error {
  readonly fieldErrors: string[];

  constructor(message: string, fieldErrors: string[]) {
    super(message);
    this.name = "RuntimeControlValidationError";
    this.fieldErrors = fieldErrors;
  }
}

type ErrorLike = {
  name?: string;
  message?: string;
  status?: number;
  body?: string;
  path?: string;
};

export function summarizeRuntimeControlError(
  error: unknown
): RuntimeControlErrorSummary {
  const errorLike = asErrorLike(error);

  if (errorLike.name === "RuntimeControlAPIError") {
    return summarizeAPIError(errorLike);
  }

  if (errorLike.name === "RuntimeControlContractError") {
    return {
      kind: "contract",
      title: "Runtime Control API contract mismatch",
      detail: `The response for ${errorLike.path ?? "the requested route"} did not match the PWA contract.`,
      recovery:
        "Refresh after updating the Helper. If this persists, export logs and compare the RuntimeContractAPI version."
    };
  }

  if (error instanceof RuntimeControlValidationError) {
    return {
      kind: "validation",
      title: "Invalid request",
      detail: error.fieldErrors.length
        ? error.fieldErrors.join(", ")
        : error.message,
      recovery: "Review the highlighted values and retry the operation."
    };
  }

  if (error instanceof TypeError) {
    return {
      kind: "network",
      title: "Runtime Control API is unreachable",
      detail:
        "The PWA could not reach the local Runtime Control API endpoint.",
      recovery:
        "Check that VitalServer Helper is running and that the PWA is using the expected local API URL."
    };
  }

  return {
    kind: "unknown",
    title: "Operation failed",
    detail: errorLike.message ?? String(error),
    recovery: "Retry the operation. If it fails again, export logs for diagnosis."
  };
}

function summarizeAPIError(error: ErrorLike): RuntimeControlErrorSummary {
  const apiBody = parseAPIErrorBody(error.body);
  const status = error.status ?? 0;
  const code = apiBody?.code;
  const message = apiBody?.message ?? error.body ?? error.message;

  return {
    kind: "api",
    title: `Runtime Control API returned HTTP ${status || "error"}`,
    detail: [code, message].filter(Boolean).join(": "),
    recovery: recoveryForStatus(status, code)
  };
}

function parseAPIErrorBody(
  body: string | undefined
): { code?: string; message?: string } | null {
  if (!body) {
    return null;
  }

  try {
    const parsed = JSON.parse(body) as { code?: unknown; message?: unknown };
    return {
      code: typeof parsed.code === "string" ? parsed.code : undefined,
      message: typeof parsed.message === "string" ? parsed.message : undefined
    };
  } catch {
    return null;
  }
}

function recoveryForStatus(status: number, code: string | undefined): string {
  if (status === 401 || code === "unauthorized") {
    return "Verify the Runtime Control token configured for the PWA.";
  }

  if (status === 404 || code === "routeNotFound") {
    return "The Helper may be older than this PWA. Update the Helper or regenerate the PWA from the current API contract.";
  }

  if (status === 405 || code === "methodNotAllowed") {
    return "The PWA and Helper disagree on this endpoint method. Check the RuntimeContractAPI version.";
  }

  if (code === "endpointNotImplemented") {
    return "This feature is not implemented by the current Helper build.";
  }

  if (status >= 500 || code === "handlerFailed") {
    return "Inspect runtime logs and retry after the current runtime operation completes.";
  }

  return "Review the request values and retry the operation.";
}

function asErrorLike(error: unknown): ErrorLike {
  if (error && typeof error === "object") {
    return error as ErrorLike;
  }
  return { message: String(error) };
}

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
  readonly kind = "validation" as const;
  readonly fieldErrors: string[];

  constructor(message: string, fieldErrors: string[]) {
    super(message);
    this.name = "RuntimeControlValidationError";
    this.fieldErrors = fieldErrors;
  }
}

export class RuntimeControlAPIError extends Error {
  readonly kind = "api" as const;
  readonly status: number;
  readonly body: string;

  constructor(message: string, status: number, body: string) {
    super(message);
    this.name = "RuntimeControlAPIError";
    this.status = status;
    this.body = body;
  }
}

export class RuntimeControlNetworkError extends Error {
  readonly kind = "network" as const;
  readonly url: string;
  readonly cause: unknown;

  constructor(url: string, cause: unknown) {
    super(`Runtime Control API is unreachable: ${url}`);
    this.name = "RuntimeControlNetworkError";
    this.url = url;
    this.cause = cause;
  }
}

export class RuntimeControlContractError extends Error {
  readonly kind = "contract" as const;
  readonly path: string;
  readonly cause: unknown;

  constructor(path: string, cause: unknown) {
    super(`Runtime Control API contract validation failed: ${path}`);
    this.name = "RuntimeControlContractError";
    this.path = path;
    this.cause = cause;
  }
}

type ErrorLike = {
  kind?: RuntimeControlErrorKind;
  name?: string;
  message?: string;
  status?: number;
  body?: string;
  path?: string;
  url?: string;
  cause?: unknown;
};

export function summarizeRuntimeControlError(
  error: unknown
): RuntimeControlErrorSummary {
  const errorLike = asErrorLike(error);

  if (errorLike.kind === "api") {
    return summarizeAPIError(errorLike);
  }

  if (errorLike.kind === "contract") {
    return {
      kind: "contract",
      title: "Runtime Control API contract mismatch",
      detail: `The response for ${errorLike.path ?? "the requested route"} did not match the PWA contract.`,
      recovery:
        "Refresh after updating the Helper. If this persists, export logs and compare the RuntimeContractAPI version."
    };
  }

  if (errorLike.kind === "network") {
    return summarizeNetworkError(errorLike);
  }

  if (
    errorLike.kind === "validation" &&
    error instanceof RuntimeControlValidationError
  ) {
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
    return summarizeNetworkError(errorLike);
  }

  return {
    kind: "unknown",
    title: "Operation failed",
    detail: errorLike.message ?? String(error),
    recovery: "Retry the operation. If it fails again, export logs for diagnosis."
  };
}

function summarizeNetworkError(
  error: ErrorLike
): RuntimeControlErrorSummary {
  const cause = asErrorLike(error.cause);
  const causeMessage = cause.message ?? error.message;
  const detail = error.url
    ? `The Remote Console tried ${error.url}, but the Runtime Control API did not respond.`
    : "The Remote Console could not reach the Runtime Control API endpoint.";

  return {
    kind: "network",
    title: "Runtime Control API is unreachable",
    detail: causeMessage ? `${detail} ${causeMessage}` : detail,
    recovery:
      "Verify that VitalServer Helper is running, then check the Remote Console URL and port. In Vite dev mode, also check VITE_RUNTIME_CONTROL_DEV_PROXY_TARGET."
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
    return "Verify the Runtime Control token configured for the Remote Console.";
  }

  if (status === 404 || code === "routeNotFound") {
    return "The Helper may be older than this PWA. Update the Helper or regenerate the PWA from the current API contract.";
  }

  if (status === 405 || code === "methodNotAllowed") {
    return "The Remote Console and Helper disagree on this endpoint method. Check the RuntimeContractAPI version.";
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

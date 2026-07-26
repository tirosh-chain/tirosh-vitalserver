export interface RecorderObservationCatalogPublisher {
  publish(command: unknown): Promise<{ status: number; document: unknown }>;
}

export class GuestRuntimeObservationCatalogClient implements RecorderObservationCatalogPublisher {
  private constructor(
    private readonly endpoint: URL,
    private readonly bearerToken: string,
    private readonly timeoutMilliseconds: number,
  ) {}

  public static create(endpoint: string, bearerToken: string, timeoutMilliseconds = 5000): GuestRuntimeObservationCatalogClient {
    const parsed = new URL(endpoint);
    if (parsed.protocol !== "http:" || (parsed.hostname !== "127.0.0.1" && parsed.hostname !== "::1") || parsed.port === "" || parsed.username !== "" || parsed.password !== "" || (parsed.pathname !== "" && parsed.pathname !== "/") || parsed.search !== "" || parsed.hash !== "") {
      throw new Error("Guest Runtime observation Catalog endpoint must be a bare Guest-loopback HTTP URL with an explicit port");
    }
    if (bearerToken === "" || bearerToken.trim() !== bearerToken) {
      throw new Error("Guest Runtime observation Catalog bearer token must be explicit without surrounding whitespace");
    }
    if (!Number.isInteger(timeoutMilliseconds) || timeoutMilliseconds < 100 || timeoutMilliseconds > 60_000) {
      throw new Error("Guest Runtime observation Catalog timeout must be between 100 and 60000 milliseconds");
    }
    parsed.pathname = "";
    return new GuestRuntimeObservationCatalogClient(parsed, bearerToken, timeoutMilliseconds);
  }

  public async publish(command: unknown): Promise<{ status: number; document: unknown }> {
    const target = new URL(this.endpoint);
    target.pathname = "/internal/v1/recorder-catalog/observations";
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMilliseconds);
    try {
      const response = await fetch(target, {
        method: "POST",
        headers: {
          authorization: `Bearer ${this.bearerToken}`,
          "content-type": "application/json",
          accept: "application/json",
        },
        body: JSON.stringify(command),
        signal: controller.signal,
      });
      return { status: response.status, document: await decodeResponse(response) };
    } finally {
      clearTimeout(timeout);
    }
  }
}

async function decodeResponse(response: Response): Promise<unknown> {
  try {
    return await response.json() as unknown;
  } catch {
    return {
      schemaVersion: "v1",
      state: "failed",
      issue: {
        code: "guest-runtime-observation-catalog-response-invalid",
        message: "Guest Runtime observation Catalog response was not JSON",
        retryable: response.status >= 500,
        dependency: "guest-runtime-observation-catalog",
      },
    };
  }
}

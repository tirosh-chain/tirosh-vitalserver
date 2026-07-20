import type { RecorderObservationDelivery, RecorderObservationPublishCommand } from "../../labrecorderrunnerdomain/lab-recorder-run-contracts.js";
import type { RecorderObservationPublisher } from "../../labrecorderrunnerapplication/lab-recorder-runner-ports.js";

// GuestRuntimeRecorderObservationCatalogClient is the external C19 adapter.
// The Runner sends a Recorder-owned envelope; the Guest catalog alone assigns
// received/persisted timestamps and owns its projection/operation state.
export class GuestRuntimeRecorderObservationCatalogClient implements RecorderObservationPublisher {
  public constructor(private readonly endpoint: URL, private readonly timeoutMilliseconds = 5000) {}

  public static create(endpoint: string, timeoutMilliseconds = 5000): GuestRuntimeRecorderObservationCatalogClient {
    const parsed = new URL(endpoint);
    if (parsed.protocol !== "http:" || (parsed.hostname !== "127.0.0.1" && parsed.hostname !== "::1") || parsed.port === "" || parsed.username !== "" || parsed.password !== "" || (parsed.pathname !== "" && parsed.pathname !== "/") || parsed.search !== "" || parsed.hash !== "") {
      throw new Error("Guest Runtime observation catalog endpoint must be a bare Guest-loopback HTTP URL with an explicit port");
    }
    if (!Number.isInteger(timeoutMilliseconds) || timeoutMilliseconds < 100 || timeoutMilliseconds > 60_000) {
      throw new Error("Guest Runtime observation catalog timeout must be between 100 and 60000 milliseconds");
    }
    parsed.pathname = "";
    return new GuestRuntimeRecorderObservationCatalogClient(parsed, timeoutMilliseconds);
  }

  public async publishRecorderObservation(command: RecorderObservationPublishCommand): Promise<RecorderObservationDelivery> {
    const target = new URL(this.endpoint);
    target.pathname = "/v1/runtime/catalog/recorder-observations";
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMilliseconds);
    try {
      const response = await fetch(target, { method: "POST", headers: { "content-type": "application/json", accept: "application/json" }, body: JSON.stringify(command), signal: controller.signal });
      const decoded = await decodeResponse(response);
      if (response.status === 202 && decoded !== undefined && decoded.schemaVersion === "v1" && decoded.state === "succeeded") {
        return { state: "published", observationId: command.observationId };
      }
      return { state: "failed", issue: { code: "guest-runtime-observation-catalog-rejected", message: `Guest Runtime catalog did not accept Recorder observation (HTTP ${response.status})`, retryable: response.status >= 500, dependency: "guest-runtime-observation-catalog" } };
    } catch (error) {
      return { state: "failed", issue: { code: "guest-runtime-observation-catalog-unavailable", message: `Guest Runtime catalog request failed: ${error instanceof Error ? error.message : "unknown error"}`, retryable: true, dependency: "guest-runtime-observation-catalog" } };
    } finally {
      clearTimeout(timeout);
    }
  }
}

async function decodeResponse(response: Response): Promise<Record<string, unknown> | undefined> {
  try {
    const decoded = await response.json() as unknown;
    return typeof decoded === "object" && decoded !== null && !Array.isArray(decoded) ? decoded as Record<string, unknown> : undefined;
  } catch {
    return undefined;
  }
}

import type { RecorderObservationDelivery, RecorderObservationPublishCommand } from "../../labrecorderrunnerdomain/lab-recorder-run-contracts.js";
import type { RecorderObservationPublisher } from "../../labrecorderrunnerapplication/lab-recorder-runner-ports.js";

// RecorderGatewayObservationCatalogClient publishes only to the
// Recorder Gateway loopback admission route. Gateway owns the authenticated
// hop to Guest Runtime; the Runner never bypasses that owner boundary.
export class RecorderGatewayObservationCatalogClient implements RecorderObservationPublisher {
  public constructor(private readonly endpoint: URL, private readonly timeoutMilliseconds = 5000) {}

  public static create(endpoint: string, timeoutMilliseconds = 5000): RecorderGatewayObservationCatalogClient {
    const parsed = new URL(endpoint);
    if (parsed.protocol !== "http:" || (parsed.hostname !== "127.0.0.1" && parsed.hostname !== "::1") || parsed.port === "" || parsed.username !== "" || parsed.password !== "" || (parsed.pathname !== "" && parsed.pathname !== "/") || parsed.search !== "" || parsed.hash !== "") {
      throw new Error("Recorder Gateway observation catalog endpoint must be a bare Guest-loopback HTTP URL with an explicit port");
    }
    if (!Number.isInteger(timeoutMilliseconds) || timeoutMilliseconds < 100 || timeoutMilliseconds > 60_000) {
      throw new Error("Recorder Gateway observation catalog timeout must be between 100 and 60000 milliseconds");
    }
    parsed.pathname = "";
    return new RecorderGatewayObservationCatalogClient(parsed, timeoutMilliseconds);
  }

  public async publishRecorderObservation(command: RecorderObservationPublishCommand): Promise<RecorderObservationDelivery> {
    const target = new URL(this.endpoint);
    target.pathname = "/internal/v1/recorder-observations";
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMilliseconds);
    try {
      const response = await fetch(target, { method: "POST", headers: { "content-type": "application/json", accept: "application/json" }, body: JSON.stringify(command), signal: controller.signal });
      const decoded = await decodeResponse(response);
      if (response.status === 202 && decoded !== undefined && decoded.schemaVersion === "v1" && (decoded.outcome === "accepted" || decoded.outcome === "duplicate")) {
        return { state: "published", observationId: command.observationId };
      }
      return { state: "failed", issue: { code: "recorder-gateway-observation-catalog-rejected", message: `Recorder Gateway did not accept Recorder observation (HTTP ${response.status})`, retryable: response.status >= 500, dependency: "recorder-gateway-observation-catalog" } };
    } catch (error) {
      return { state: "failed", issue: { code: "recorder-gateway-observation-catalog-unavailable", message: `Recorder Gateway catalog request failed: ${error instanceof Error ? error.message : "unknown error"}`, retryable: true, dependency: "recorder-gateway-observation-catalog" } };
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

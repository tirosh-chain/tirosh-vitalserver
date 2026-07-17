import { parseArgs } from "node:util";

import { createRecorderGatewayRuntime } from "../recorder-gateway-runtime-composition.js";

const { values } = parseArgs({
  options: {
    listen: { type: "string" },
    "state-dir": { type: "string" },
    "vitalserver-delivery-url": { type: "string" },
    "provider-kind": { type: "string" },
    "provider-id": { type: "string" },
    "capability-revision": { type: "string" },
    "vitalserver-delivery-acknowledgement-timeout-ms": { type: "string" },
    "delivery-replay-max-items": { type: "string" },
    "delivery-replay-max-bytes": { type: "string" },
    "cold-path-capture-max-retained-packets": { type: "string" },
    "cold-path-capture-max-retained-payload-bytes": { type: "string" },
    "replay-interval-ms": { type: "string" },
    "replay-max-attempts": { type: "string" },
    "replay-retry-delay-ms": { type: "string" },
    "replay-lease-duration-ms": { type: "string" },
  },
});

const listen = values.listen;
const stateDirectory = values["state-dir"];
const vitalServerDeliveryURL = values["vitalserver-delivery-url"];
if (
  listen === undefined || stateDirectory === undefined || vitalServerDeliveryURL === undefined || values["provider-kind"] === undefined || values["provider-id"] === undefined ||
  values["capability-revision"] === undefined || values["vitalserver-delivery-acknowledgement-timeout-ms"] === undefined || values["delivery-replay-max-items"] === undefined ||
  values["delivery-replay-max-bytes"] === undefined || values["cold-path-capture-max-retained-packets"] === undefined || values["cold-path-capture-max-retained-payload-bytes"] === undefined || values["replay-interval-ms"] === undefined || values["replay-max-attempts"] === undefined ||
  values["replay-retry-delay-ms"] === undefined || values["replay-lease-duration-ms"] === undefined
) {
  console.error("--listen, --state-dir, --vitalserver-delivery-url, --provider-kind, --provider-id, --capability-revision, --vitalserver-delivery-acknowledgement-timeout-ms, --delivery-replay-max-items, --delivery-replay-max-bytes, --cold-path-capture-max-retained-packets, --cold-path-capture-max-retained-payload-bytes, --replay-interval-ms, --replay-max-attempts, --replay-retry-delay-ms, and --replay-lease-duration-ms are required");
  process.exitCode = 2;
} else {
  const address = parseListenAddress(listen);
  const capabilityRevision = integerOption(values["capability-revision"], "--capability-revision");
  const maxPendingItems = integerOption(values["delivery-replay-max-items"], "--delivery-replay-max-items");
  const maxPendingBytes = integerOption(values["delivery-replay-max-bytes"], "--delivery-replay-max-bytes");
  const maxRetainedPackets = integerOption(values["cold-path-capture-max-retained-packets"], "--cold-path-capture-max-retained-packets");
  const maxRetainedPayloadBytes = integerOption(values["cold-path-capture-max-retained-payload-bytes"], "--cold-path-capture-max-retained-payload-bytes");
  const vitalServerDeliveryAcknowledgementTimeoutMs = integerOption(values["vitalserver-delivery-acknowledgement-timeout-ms"], "--vitalserver-delivery-acknowledgement-timeout-ms");
  const replayIntervalMs = integerOption(values["replay-interval-ms"], "--replay-interval-ms");
  const maxAttempts = integerOption(values["replay-max-attempts"], "--replay-max-attempts");
  const retryDelayMs = integerOption(values["replay-retry-delay-ms"], "--replay-retry-delay-ms");
  const leaseDurationMs = integerOption(values["replay-lease-duration-ms"], "--replay-lease-duration-ms");
  const runtime = await createRecorderGatewayRuntime({
    stateDirectory,
    vitalServerDeliveryURL,
    vitalServerDeliveryAcknowledgementTimeoutMs,
    replayIntervalMs,
    ingressAdmission: { maxPendingItems, maxPendingBytes },
    coldPathCapture: { maxRetainedPackets, maxRetainedPayloadBytes },
    replay: { maxAttempts, retryDelayMs, leaseDurationMs },
    provider: { kind: values["provider-kind"], id: values["provider-id"], capabilityRevision },
  });
  const bound = await runtime.start(address.host, address.port);
  console.log(JSON.stringify({ event: "recorder-gateway.listening", address: bound.address, port: bound.port }));
  const shutdown = async (): Promise<void> => {
    await runtime.close();
  };
  process.once("SIGINT", () => {
    void shutdown();
  });
  process.once("SIGTERM", () => {
    void shutdown();
  });
}

function parseListenAddress(value: string): { host: string; port: number } {
  const separator = value.lastIndexOf(":");
  if (separator < 1) {
    throw new Error("--listen must be host:port");
  }
  return { host: value.slice(0, separator), port: integerOption(value.slice(separator + 1), "--listen port") };
}

function integerOption(value: string | undefined, name: string): number {
  const parsed = Number.parseInt(value ?? "", 10);
  if (!Number.isInteger(parsed) || parsed < 1) {
    throw new Error(`${name} must be a positive integer`);
  }
  return parsed;
}

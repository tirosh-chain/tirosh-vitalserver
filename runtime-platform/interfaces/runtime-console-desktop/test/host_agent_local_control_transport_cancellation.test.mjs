import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import test from "node:test";

import {
  HostAgentLocalControlTransport,
} from "../dist/host-agent-local-control-transport.mjs";

test("desktop transport passes cancellation to the pending Host local request", async () => {
  let observedSignal;
  const requestLocalHTTP = (options) => {
    observedSignal = options.signal;
    const pending = new EventEmitter();
    pending.setTimeout = () => pending;
    pending.write = () => true;
    pending.end = () => undefined;
    options.signal.addEventListener("abort", () => {
      const error = new Error("The operation was aborted");
      error.name = "AbortError";
      queueMicrotask(() => pending.emit("error", error));
    }, { once: true });
    return pending;
  };
  const transport = new HostAgentLocalControlTransport(
    {
      schemaVersion: "v1",
      transport: "unix-domain-socket",
      address: "/tmp/host-agent-cancellation-test.sock",
    },
    requestLocalHTTP,
  );
  const controller = new AbortController();
  const pending = transport.request(
    {
      kind: "recorder-detail-read",
      resource: "observability-summary",
      recorderId: "recorder-1",
    },
    { signal: controller.signal },
  );
  assert.equal(observedSignal, controller.signal);
  controller.abort();
  await assert.rejects(
    pending,
    (error) => error instanceof Error && error.name === "AbortError",
  );
});

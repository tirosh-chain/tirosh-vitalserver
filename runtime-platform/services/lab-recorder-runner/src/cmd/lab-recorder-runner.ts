import { parseArgs } from "node:util";

import {
  CryptoLabRecorderRunnerIdentifierGenerator,
  LabRecorderRunnerApplicationService,
  SystemLabRecorderRunnerClock,
} from "../labrecorderrunnerapplication/lab-recorder-runner-application-service.js";
import { LabReplayApplicationService } from "../labrecorderrunnerapplication/lab-replay-application-service.js";
import { LabScenarioCatalog } from "../adapters/labscenariocatalogfile/lab-scenario-catalog-file.js";
import { createLabRecorderRunnerControlHTTPServer } from "../adapters/labrecorderrunnerinbound/lab-recorder-runner-control-http-server.js";
import { RecorderGatewaySocketIoLabRecorderScenarioExecutionPort } from "../adapters/recordergatewaysocketio/lab-recorder-scenario-socketio-execution-port.js";
import { RecorderGatewayObservationCatalogClient } from "../adapters/recorder-gateway-observation-catalog/recorder-gateway-observation-catalog-client.js";
import { FileLabReplaySessionStore } from "../adapters/labreplaystatefile/file-lab-replay-session-store.js";
import { SocketIoLabReplayRecorderGatewayPort } from "../adapters/recordergatewaysocketio/lab-replay-recorder-gateway-port.js";

const { values } = parseArgs({
  options: {
    listen: { type: "string" },
    "recorder-gateway-endpoint": { type: "string" },
    "scenario-catalog": { type: "string" },
    "lab-replay-state-directory": { type: "string" },
  },
});

const listen = values.listen;
const recorderGatewayEndpoint = values["recorder-gateway-endpoint"];
const scenarioCatalogPath = values["scenario-catalog"];
const labReplayStateDirectory = values["lab-replay-state-directory"];
if (listen === undefined || recorderGatewayEndpoint === undefined || scenarioCatalogPath === undefined || labReplayStateDirectory === undefined) {
  console.error("--listen, --recorder-gateway-endpoint, --scenario-catalog, and --lab-replay-state-directory are required");
  process.exitCode = 2;
} else {
  try {
    const address = parseLoopbackListenAddress(listen);
    const catalog = await LabScenarioCatalog.read(scenarioCatalogPath);
    const execution = new RecorderGatewaySocketIoLabRecorderScenarioExecutionPort(recorderGatewayEndpoint);
    const observations = RecorderGatewayObservationCatalogClient.create(recorderGatewayEndpoint);
    const clock = new SystemLabRecorderRunnerClock();
    const identifiers = new CryptoLabRecorderRunnerIdentifierGenerator();
    const service = new LabRecorderRunnerApplicationService(execution, observations, clock, identifiers);
    const replayService = new LabReplayApplicationService(
      new FileLabReplaySessionStore(labReplayStateDirectory),
      new SocketIoLabReplayRecorderGatewayPort(recorderGatewayEndpoint),
      clock,
      identifiers,
    );
    await replayService.initialize();
    const server = createLabRecorderRunnerControlHTTPServer(service, replayService, catalog);
    await new Promise<void>((resolve, reject) => {
      server.once("error", reject);
      server.listen(address.port, address.host, () => {
        server.off("error", reject);
        resolve();
      });
    });
    console.log(JSON.stringify({ event: "lab-recorder-runner.listening", address: address.host, port: address.port, scenarioCatalogId: catalog.catalogID }));
    const shutdown = (): void => {
      service.close();
      server.close();
    };
    process.once("SIGINT", shutdown);
    process.once("SIGTERM", shutdown);
  } catch (error) {
    console.error(`Lab recorder Runner startup failed: ${error instanceof Error ? error.message : "unknown error"}`);
    process.exitCode = 2;
  }
}

function parseLoopbackListenAddress(value: string): { host: "127.0.0.1" | "::1"; port: number } {
  const separator = value.lastIndexOf(":");
  if (separator < 1) {
    throw new Error("--listen must be 127.0.0.1:port or ::1:port");
  }
  const host = value.slice(0, separator);
  const port = Number.parseInt(value.slice(separator + 1), 10);
  if ((host !== "127.0.0.1" && host !== "::1") || !Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error("--listen must be a Guest-loopback host and a valid port");
  }
  return { host, port };
}

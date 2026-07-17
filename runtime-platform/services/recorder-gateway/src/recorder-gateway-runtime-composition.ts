import type { AddressInfo } from "node:net";
import type { Server as HttpServer } from "node:http";

import type { Server as SocketIoServer } from "socket.io";

import { attachRecorderGatewaySocketIoIngress } from "./adapters/recordergatewayinbound/recorder-gateway-socketio-ingress-server.js";
import { createRecorderGatewayControlHTTPServer } from "./adapters/recordergatewayinbound/recorder-gateway-control-http-server.js";
import { FileRecorderGatewayIngressDurableStateStore } from "./adapters/recordergatewayingressdurablestatefile/file-recorder-gateway-ingress-durable-state-store.js";
import { SocketIoVitalServerPacketDeliveryPort } from "./adapters/vitalserverpacketdeliverysocketio/socketio-vital-server-packet-delivery-port.js";
import {
  CryptoRecorderGatewayIdentifierGenerator,
  RecorderGatewayIngressAndColdPathApplicationService,
  type RecorderGatewayDeliveryReplayRunResult,
  type RecorderGatewayIngressAndColdPathServiceConfiguration,
} from "./recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-service.js";
import { SystemRecorderGatewayClock } from "./recordergatewayapplication/recorder-gateway-ingress-and-cold-path-application-ports.js";

export interface RecorderGatewayRuntimeConfiguration extends RecorderGatewayIngressAndColdPathServiceConfiguration {
  stateDirectory: string;
  vitalServerDeliveryURL: string;
  vitalServerDeliveryAcknowledgementTimeoutMs: number;
  replayIntervalMs: number;
}

export interface RecorderGatewayRuntime {
  ingressAndColdPathService: RecorderGatewayIngressAndColdPathApplicationService;
  start(host: string, port: number): Promise<AddressInfo>;
  close(): Promise<void>;
}

export async function createRecorderGatewayRuntime(configuration: RecorderGatewayRuntimeConfiguration): Promise<RecorderGatewayRuntime> {
  if (configuration.stateDirectory === "" || configuration.vitalServerDeliveryURL === "" || configuration.vitalServerDeliveryAcknowledgementTimeoutMs < 1 || configuration.replayIntervalMs < 1) {
    throw new Error("Recorder Gateway runtime configuration is incomplete");
  }
  const identifiers = new CryptoRecorderGatewayIdentifierGenerator();
  const ingressAndColdPathService = new RecorderGatewayIngressAndColdPathApplicationService(
    new FileRecorderGatewayIngressDurableStateStore(configuration.stateDirectory),
    new SocketIoVitalServerPacketDeliveryPort({
      vitalServerDeliveryURL: configuration.vitalServerDeliveryURL,
      acknowledgementTimeoutMs: configuration.vitalServerDeliveryAcknowledgementTimeoutMs,
      vitalServerProviderID: configuration.provider.id,
    }),
    new SystemRecorderGatewayClock(),
    identifiers,
    configuration,
  );
  await ingressAndColdPathService.initializeRecorderGatewayIngressDurableState();
  const httpServer = createRecorderGatewayControlHTTPServer(ingressAndColdPathService);
  const socketServer = attachRecorderGatewaySocketIoIngress(httpServer, ingressAndColdPathService, identifiers);
  let replayTimer: NodeJS.Timeout | undefined;
  return {
    ingressAndColdPathService,
    start: async (host: string, port: number): Promise<AddressInfo> => {
      if (replayTimer !== undefined) {
        throw new Error("Recorder Gateway runtime is already listening");
      }
      const address = await listenRecorderGatewayControlHTTPServer(httpServer, host, port);
      replayTimer = setInterval(() => {
        void runOneDueVitalServerDeliveryReplay(ingressAndColdPathService);
      }, configuration.replayIntervalMs);
      return address;
    },
    close: async (): Promise<void> => {
      if (replayTimer !== undefined) {
        clearInterval(replayTimer);
        replayTimer = undefined;
      }
      await closeRecorderGatewaySocketIoIngressServer(socketServer);
      await closeRecorderGatewayControlHTTPServer(httpServer);
    },
  };
}

async function runOneDueVitalServerDeliveryReplay(service: RecorderGatewayIngressAndColdPathApplicationService): Promise<void> {
  const result: RecorderGatewayDeliveryReplayRunResult = await service.replayOneDueVitalServerDelivery();
  if (result.state === "failed") {
    // This is operational evidence only. It contains a typed code and never
    // packet bytes, recorder code, endpoint, credential, or payload digest.
    console.error(JSON.stringify({ event: "recorder-gateway.delivery-replay.failed", issue: result.issue }));
  }
}

function listenRecorderGatewayControlHTTPServer(server: HttpServer, host: string, port: number): Promise<AddressInfo> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, () => {
      server.off("error", reject);
      const address = server.address();
      if (address === null || typeof address === "string") {
        reject(new Error("Recorder Gateway did not expose a TCP address"));
        return;
      }
      resolve(address);
    });
  });
}

function closeRecorderGatewaySocketIoIngressServer(server: SocketIoServer): Promise<void> {
  return new Promise((resolve) => {
    server.close(() => resolve());
  });
}

function closeRecorderGatewayControlHTTPServer(server: HttpServer): Promise<void> {
  if (!server.listening) {
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error === undefined) {
        resolve();
        return;
      }
      reject(error);
    });
  });
}
